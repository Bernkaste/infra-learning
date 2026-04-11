# Terraform Modules 分割方針（このプロジェクト版 / Step9-2）

## 0. このプロジェクトの前提（今まで作ってきたもの）

本プロジェクトは、以下を Terraform で再現可能にすることを目的とする。

- AWS ネットワーク（VPC, Subnet, Route, IGW, （必要なら NAT））
- IAM（最小権限、CI/CDは OIDC による AssumeRole）
- コンテナ実行基盤（ECR, ECS Fargate, （必要なら ALB））
- ログ閲覧導線（CloudWatch Logs）

## 1. 目的（なぜ module を使うか）

modules を導入する目的は以下。

- 標準化：命名規則・タグ・IAM最小権限・ネットワーク構成などがブレないようにする
- 再現性：apply で同じ構成が作れて、destroy で片付く状態を維持する
- 分離：基盤（network/iam）とアプリ（app）で変更の影響範囲を分ける

## 2. Module の定義

- root module：実際に apply するディレクトリ（環境差分を持つ）
- child module：`modules/<name>/` 配下の再利用部品（inputs/outputs を持つ）

## 3. 分割の判断基準（いつ module 化するか）

次のどれかに当てはまる場合のみ module 化する。

1. 複数環境（dev/stg/prod）や将来の別アプリでも使い回したい
2. ルールが多く、root に置くと読みづらくなる（network/IAM/ECS/ALBなど）
3. 変更頻度が違うので、影響範囲を切りたい（基盤は安定、アプリは変わりやすい）

上記に当てはまらないものは、当面 root に置く（無理に module を増やさない）。

## 4. 採用する module 構成（最初は3つに固定）

初期段階では module を増やしすぎず、以下の3つを基本とする。

### 4.1 modules/network（ネットワーク基盤）

責務：

- VPC, Subnet（public/private）, RouteTable, IGW
- NAT Gateway は「必要になったタイミングで」導入（課金を避ける）
- Security Group は “ネットワーク基盤として共通化したいもの” のみ（増やしすぎない）

inputs（例）：

- env, name_prefix, vpc_cidr
- public_subnet_cidrs, private_subnet_cidrs
- enable_nat_gateway（true/false）
- tags

outputs（例）：

- vpc_id
- public_subnet_ids, private_subnet_ids
- （必要なら）alb_sg_id, app_sg_id など

### 4.2 modules/iam（最小権限 + OIDC前提のIAM）

責務：

- GitHub Actions 用の OIDC AssumeRole（長期Access Keyを置かない）
- ECS の task execution role / task role（必要な権限だけ付与）
- ポリシーは “必要最小限をテンプレ化し、足りなければ追加” の方針

inputs（例）：

- env, name_prefix, tags
- github_repository（例: "owner/repo"）
- github_ref_allowlist（例: ["refs/heads/main"]）

outputs（例）：

- github_actions_role_arn
- ecs_task_execution_role_arn
- ecs_task_role_arn

### 4.3 modules/app（ECR + ECS(Fargate) + （必要なら ALB））

責務：

- ECR repository（アプリのイメージ置き場）
- ECS cluster / task definition / service（Fargate実行）
- CloudWatch Logs（アプリログ出力先）
- （必要な場合のみ）ALB / TargetGroup / Listener

inputs（例）：

- env, name_prefix, tags
- vpc_id, subnet_ids, security_group_ids（network outputs）
- role_arns（iam outputs）
- image_uri（ActionsでpushしたECRイメージ）
- desired_count, cpu, memory
- enable_alb（true/false）

outputs（例）：

- ecr_repository_url
- ecs_cluster_name, ecs_service_name
- （enable_alb=true の場合）alb_dns_name

## 5. 依存関係の原則（module間のつなぎ方）

- module 間の参照は outputs → inputs で受け渡す（直接参照しない）
- 依存の向きは以下を基本とする
    
    network → （outputs）→ app
    
    iam → （outputs）→ app
    
- app は network/iam の情報を inputs として受け取り、内部実装に踏み込まない

## 6. 命名・タグの標準

命名：

- 基本は `${name_prefix}-${env}-<resource>` 形式で統一する

タグ：

- `tags` は root から渡し、module 内で標準タグ（Environmentなど）を merge する
- 例：`tags = merge(var.tags, { Environment = var.env, ManagedBy = "terraform" })`

## 7. やらないこと（初期スコープ外）

- module を細かく分割しすぎない（初期は network/iam/app の3つ固定）
- “リソース1個 = module1個” はしない（inputs/outputs が増えて学習効率が落ちる）
- module の output を増やしすぎない（他が本当に必要なものだけ出す）

## 8. 将来の拡張方針（必要になったら追加）

要件が固まったら以下を追加検討する。

- modules/observability：CloudWatch Alarm / Dashboard / 通知（Step8/10の改善テーマで固めてから）
- modules/alb：ALB を複数サービスで使い回す段階になったら切り出し検討
- modules/security：WAF/KMS/Secrets などが増えてきたら検討
