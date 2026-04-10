# infra-learning

- リポジトリ構成：
    - `aws-terraform/`
        - AWSインフラをTerraformで管理するメイン（VPC/IAM/ECS/ECR/Logsなど）
        - `README.md`（Terraform実行手順：init/plan/apply/destroy、前提、注意点）
        - `env/`（環境別：`dev/` `stg/` `prd/` など。最初は `dev/` だけでOK）
        - `modules/`（共通化したい部品：network/iam/ecs など。必要になったタイミングで作る）
    - `app/`
        - 動作確認用の最小アプリ（例：`/health`）＋Dockerfile
        - 将来的にECSへ載せる対象（CI/CDの検証にも使う）
    - `docs/`
        - 人に説明するための資料置き場（構成図、設計意図、運用メモ、改善Before/After）
        - ロールバック手順、監視/アラート方針、ポストモーテム雛形などもここに集約
    - `README.md`（このリポジトリの入口）

- 目的：
    - AWS設計 × Terraform × 運用改善を「説明できる」だけじゃなく「手を動かして再現できる」状態にする（転職で語れる実績を作る）。
    - 12週間で、AWSの基本構成（ネットワーク〜ECS）を IaC（Terraform）で構築→破棄まで通し、CI/CD・OIDC・監視・ロールバック・改善（Before/After）まで一連で触れる。
    - 成果がGitHub上で第三者に伝わる（README/設計図/運用メモ/改善記録が揃っている）状態にする。

- 完了条件：
    - リポジトリ構造が整っている（例：`aws-terraform/`, `app/`, `docs/`）。
    - Terraformで以下を再現できる（applyで作成→コンソールで確認→destroyで片付く）
        - 最小成功：S3（＋destroy）
        - ネットワーク：VPC / Public Subnet / IGW / Route（＋必要に応じてPrivate Subnet）
        - ECR / ECS / Logs（必要ならALBまで）
    - アプリ側の最小成果物
        - `/health` 等の最小Webアプリを用意してDocker化できている
    - GitHub Actions（実務寄せ）
        - CI（テスト/ビルド）が回る
        - CD（ECR push → ECS deploy）が動く
        - OIDCでAssumeRole（Access Keyを置かない）
    - 運用成果物（docsに残す）
        - IAM最小権限の方針メモ
        - 監視・アラート・ロールバック手順
        - ポストモーテム雛形（障害後の振り返り）
    - 改善（価値づくり）
        - 改善テーマを1つ選び、Before/Afterを指標付きでREADMEに残す
    - READMEの整備
        - Terraform手順（init/plan/apply/destroy）がREADMEにまとまっている
        - 最終的にREADMEが「面接資料レベル」（設計意図/運用/改善が説明できる）
    - 転職接続
        - 想定QA10問＋職務経歴書に載せる文章が用意できている

- 週次計画：
    - Week 0：環境準備・課金ガード・GitHub準備（作業フォルダ / AWSアラート / repo）
    - Week 1：Terraform最小成功（公式チュートリアル→S3→destroy→手順をREADME化）
    - Week 2：AWSネットワーク基礎（VPC/サブネット/IGW/RouteをTerraformで構築＋図解）
    - Week 3：IAM/SSM/Logs（最小権限の考え方と運用の入口を作る）
    - Week 4：ECS(Fargate)を手動で動かす（サービスの全体像を掴む）
    - Week 5：CI導入（GitHub Actionsでテスト/ビルド）＋失敗時の修正経験
    - Week 6：CD完成（Actions→ECR→ECS）＋ロールバック手順を残す
    - Week 7：OIDC化（鍵を置かずにAWS操作）＋権限を最小化
    - Week 8：監視・アラート・障害対応（ポストモーテム雛形含む）
    - Week 9：ECS周りもIaC化（ECR/ECS/Logs/必要ならALB）＋modules分割方針
    - Week 10：改善テーマ選定→Before/Afterを指標付きで残す
    - Week 11：成果の言語化（README/構成図/設計意図を面接水準に）
    - Week 12：転職接続（想定QA/職務経歴書用の文章作成）

- 各成果物リンク
    - docs/setup-awscli.md (AWS CLIの準備)
    - docs/terraform-basics.md (init/plan/apply/destroyの流れ)
    - docs/s3.md (s3作成→確認の流れ)
    - docs/vpc-basics.md（VPCの基礎）
    - docs/step2_terraform-vpc.md
    - docs/iam-privilege-guide.md
    - docs/step3-2_ecs-cloudwatch-logs.md
    - docs/step4_ecs-fargate-manual.md
    - docs/step5_ci-github-actions.md
    - docs/step6-1&2_ci-cd-ecr-ecs.md
    - docs/step6-3_ecs-rollback.md
    - docs/step7_oidc-role-privilege.md
    - docs/incident-postmortem-template.md（ポストモーテムひな型）
    - docs/incident-postmortem-guide.md（ポストモーテムの書き方・ルール）
    - docs/terraform-module-strategy.md


# 構成図
![構成図](./architecture.drawio.svg)