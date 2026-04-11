## GitHub Actions OIDCロールの権限設計（最小権限）

### 目的（この設計で達成したいこと）

- GitHub Actions から AWS へアクセスする際に、長期保管のAccess Keyを使わず OIDC（AssumeRoleWithWebIdentity）で認証する
- デプロイに必要な最小限の操作だけを許可し、万が一ワークフローが改ざん・誤操作されても被害範囲を最小化する

---

### 対象（このドキュメントが扱うロール）

- IAM Role名（OIDCロール）: `REPLACE_ME_ROLE_NAME`
- Role ARN: `REPLACE_ME_ROLE_ARN`

このロールは GitHub Actions がAssumeして、ECR push と ECS deploy を実行するために利用する。

---

## 1. 必要性（なぜ最小権限が必要か）

GitHub Actions のワークフローは、誤操作や改ざん（権限設定ミス、意図しない変更の混入など）によって、想定外のAWS操作を実行し得る。  

そのため、IAMロール側で「できる操作」と「対象リソース」を絞り、被害範囲を構造的に小さくする。

特に注意すべきは `iam:PassRole`。  

`iam:PassRole` が広いと、ECS経由で“別の強い権限ロール”をタスクに付与できる可能性があり、権限昇格（Privilege Escalation）の入口になり得る。

---

## 2. Trust policy（誰がこのロールを使えるか）

### 結論

- GitHub OIDC Provider（`token.actions.githubusercontent.com`）のみを信頼する
- `aud` を `sts.amazonaws.com` に限定する
- `sub` を「特定リポジトリ + mainブランチ」に限定する

### 設計意図

- “別リポジトリ” や “別ブランチ” からのAssumeを防ぐ
- OIDCトークンの用途（audience）を固定し、意図しないトークン利用を防ぐ

---

## 3. Permission policy（何を許可するか）

本ロールに付与するPermission policyは、大きく以下に分割して考える。

- ECR: Dockerイメージのpushに必要な権限
- ECS: タスク定義登録とサービス更新に必要な権限
- iam:PassRole: ECSタスクが利用するロールを指定するために必要（最重要）

---

## 4. 最小権限化のポイント（今回の本丸）

### 4.1 ECS Service更新の対象を「特定サービスARN」に限定する

ECSのサービス更新は、以下のサービスだけに限定する。

- 対象ECS Service ARN
    
    `arn:aws:ecs:ap-northeast-1:<AWS_ACCOUNT_ID>:service/infra-learning/health-app-svc`
    

設計意図：

- 同一AWSアカウント内に別サービスが存在しても、誤って別サービスを更新できない
- 将来、本番相当のサービスを作っても学習用CDが触れないようにする（事故の封じ込め）

---

### 4.2 `iam:PassRole` を「ECSタスク実行ロール（execution role）だけ」に限定する（最重要）

ECSデプロイでは、タスク定義内で `executionRoleArn`（必要に応じて `taskRoleArn`）を指定する。  

このロール指定は “Roleを渡す” 行為に該当し、IAM側で `iam:PassRole` が必要。

ここを `Resource: "*"` のままにすると、任意の強いロールをタスクに付与できる可能性があり、権限昇格の原因になり得る。  

よって、PassRoleを以下に限定する。

- executionRoleArn（例）
    
    `arn:aws:iam::<AWS_ACCOUNT_ID>:role/ecsTaskExecutionRole`
    

設計意図：

- “ECSの起動準備（ECR pull / CloudWatch Logs出力）” に必要な範囲に限定
- “別の強いロール” をタスクに付与する経路を封じる（Privilege Escalation対策）

補足：

- `taskRoleArn`（アプリがAWS APIを叩くためのロール）を今後使う場合は、そのARNも明示的に追加して許可する（必要になった時に最小範囲で追加する）

---

### 4.3 `ecs:RegisterTaskDefinition` の `Resource` を `*` 許容とする理由

`ecs:RegisterTaskDefinition` はデプロイのたびに新しいrevision（タスク定義の版）を登録するために必須。  

一方で、このアクションはIAMの `Resource` で綺麗に絞りにくい/絞れないケースが多く、 `Resource: "*"` 許容しても大きな問題はない。

ただし、以下2点を強く絞っているため、致命傷になりにくい構造になっている。

- `ecs:UpdateService` の対象が 1サービスARN に限定されている
- `iam:PassRole` の対象が execution role（必要ならtask role）に限定されている

つまり「タスク定義を登録できても、勝手に別サービスへ適用したり、強いロールで実行する」ことが難しい構造にしている。

---

## 5. 使用している最小権限ポリシー（最終形）

以下はこの環境の最小権限例。`REPLACE_ME` を自分の値に置換する。

- ECS（デプロイ用）
    - `ecs:DescribeServices`, `ecs:UpdateService` はサービスARNを固定
    - `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition` は `*` 許容
    - `iam:PassRole` は `ecsTaskExecutionRole` 等の必要ロールのARNに限定

（注）ECR push側はリポジトリARNを `health-app` に限定し、`ecr:GetAuthorizationToken` のみ `*` を許容する（仕様上の都合）

---

## 6. 動作確認（追加の難しい確認は不要）

確認は既存の Step6-1 / Step6-2 と同じ手順でOK。

- main へ push（小さい変更でOK）
- GitHub Actionsが成功（緑）
- ECS Service の Events でデプロイ成功
- Public IP で `/health` 疎通確認
