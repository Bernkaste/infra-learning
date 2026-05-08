# infra-learning

この学習プロジェクトは、AWSインフラを Terraform で構築し、GitHub Actions（OIDC）でCI/CDを回し、監視・ロールバック・改善（Before/After）まで含めて「説明できる／再現できる」状態になることを目的としている。

> ゴール：AWS設計 × Terraform × 運用改善を、第三者が読んで理解でき、手順に沿って再現できる成果物にする。

---

## 1. できること（要点）
- Terraformで **apply → 動作確認 → destroy** まで実行できる（環境を作って捨てられる運用前提）
- コンテナアプリ（`/health`）をECS(Fargate)で動かし、ECRへイメージを置いて更新できる
- GitHub ActionsからAWS操作する認証は **OIDC + AssumeRole（Access Keyを置かない）**
- デプロイ失敗時に「何をどこで戻すか」が明文化された **ロールバックRunbook** がある（Task Definition revisionを戻す）
- 監視は「ALB無し（Public IP直叩き）」前提で、最小構成から組み立てて通知まで到達させている
- 改善として **PRを作るだけで terraform plan が自動実行され、差分がレビュー可能**（remote state含む）

---

## 2. リポジトリ構成
- `.github/workflows/`
	- GitHub Actions のワークフロー定義（CI/CD、PRでのterraform plan等の自動化）
- `aws-terraform/`
	- TerraformでAWSリソースを管理するディレクトリ
	- 実行手順（init/plan/apply/destroy）や注意点は、`docs/` 側に整理（または今後 `aws-terraform/` 配下にREADMEを追加して集約する）
- `docs/`
	- 設計意図、運用、監視、ロールバック、改善の記録など「説明用ドキュメント」の置き場
- `ecs/`
	- ECSデプロイで参照する設定ファイル置き場
	- `task-definition.json`：GitHub Actionsのデプロイで参照するタスク定義（image差し替え→登録→service更新）
- `health-app/`
	- 動作確認用の最小アプリ（例：`/health`）＋Dockerfile（ECSに載せる対象）
- `README.md`
	- リポジトリの入口（第三者が最初に読む想定）

---

## 3. 主要コンポーネント（作ったもの）
- Container Registry：ECR（例：`health-app`）
- Compute：ECS(Fargate)（例：Cluster: `infra-learning` / Service: `health-app-svc`）
- Observability：CloudWatch Logs（ECSタスクからawslogsで送る導線）
- CI/CD：GitHub Actions
	- ECR push 自動化
	- ECS deploy 自動化
- AuthN/AuthZ：GitHub Actions → AWS は OIDC + AssumeRole
	- Trust policyで repo / branch を縛る（例：main縛り）
	- Permission policyは最小権限へ寄せる（特に `iam:PassRole` を特定ロールに限定）

---

## 4. 設計意図（Design Decisions）
### 4.1 OIDC（Access Keyを置かない）を採用
- 目的：CI/CDからAWS操作する際に長期Access Keyの管理を避ける
- 設計：GitHub ActionsのOIDCを使い、AssumeRoleで一時クレデンシャル発行
- Trust policyは `aud=sts.amazonaws.com` と `sub=repo:...` で利用元を限定（repo/branch縛り）

### 4.2 権限は「動く」から「最小」へ寄せる
- 最初は動作を優先し、ECS deploy権限が広くなりがち（`Resource:"*"` / `PassRole:"*"` 等）
- 最小権限に寄せる方針：
	- `ecs:UpdateService` は特定 Service ARN に限定
	- `iam:PassRole` は ECSタスクの execution role（必要なら task role）だけに限定（権限昇格リスクを潰す）

### 4.3 ロールバックは「ECRのイメージ」ではなく「Task Definition revision」を戻す
- 最短で確実な復旧は、ECS Service が参照する Task Definition revision を「正常稼働していた版」に戻すこと
- 復旧後に原因調査（復旧優先）

---

## 5. トレードオフ（やらない/後回しにしたこと）
- **ALBは導入しない**：現時点は Public IP 直叩き（`http://<PublicIP>:8080/health`）で成立させる方針  
	→ ALB前提のメトリクス（Target 5xx / UnhealthyHostCount）はこの構成では成立しないため、監視はECSメトリクスやログ起点で組み立てる
- 監視は「最小」から：まずはタスク停止通知・ログメトリクス化など、再現可能な形で到達させる
- 権限の厳密な絞り込み（`ecs:RegisterTaskDefinition` 等）は、仕様上絞りにくい部分があるため、重要度の高い箇所（PassRole / UpdateService対象）を優先して締める

---

## 6. 運用（Runbook）
### 6.1 ロールバック（デプロイ失敗時）
- 判断：デプロイが不安定／タスクが落ち続ける／疎通不可のとき
- 方針：Serviceが参照する Task Definition revision を、直前の安定版に戻す
- 確認：ECS Events / CloudWatch Logs / `/health` 疎通  
詳細：[`docs/Step6-3_ecs-rollback.md`](docs/Step6-3_ecs-rollback.md)

### 6.2 ログ確認（原因調査の入口）
- まず「タスク定義にawslogs設定があるか」と「execution roleにlogs権限があるか」を確認する
- ロググループ→最新log stream→ `error/exception/AccessDenied` などで探す  
詳細：[`docs/Step3-2_ecs-cloudwatch-logs.md`](docs/Step3-2_ecs-cloudwatch-logs.md)

---

## 7. 監視（最小構成）
ALB無し前提のため、以下の組み立てで「通知が飛ぶ」まで到達させる。
- EventBridgeで ECS Task STOPPED を拾ってSNS通知（最短で確実）
- Logs Metric Filterで ERROR/異常をメトリクス化してアラーム（ログが前提）

詳細： [`docs/Step8-1,2_monitoring.md`](docs/Step8-1,2_monitoring.md)

---

## 8. 改善（Before/After）
改善テーマ：**PRを作るだけで terraform plan が自動実行され、差分がレビュー可能になる**

- Before：レビュー時にローカルでplanを回す／差分共有が属人化しやすい
- After：PR上でplan結果が見える（再現性が上がり、レビュー負担が下がる）
- 重要な設計：remote state（S3 + DynamoDB lock）を用意し、CI上のplanを「信用できる」ものにする

詳細：[`docs/Step10_pr-terraform-plan.md`](docs/Step10_pr-terraform-plan.md)

---
## 9. 学習計画（12週間ロードマップ）

<details>
<summary>Step0：環境準備・課金ガード（親）</summary>

- Step0-1 Ubuntuで作業フォルダ作成（~/projects/infra-learning）
- Step0-2 AWS課金ガード（Budgets/Free Tierアラート）を設定
- Step0-3 GitHubリポジトリ作成＋READMEにゴールを書く

</details>

<details>
<summary>Step1：Terraform最小成功（S3→destroy）（親）</summary>

- Step1-1 Terraform公式チュートリアル開始（Install/AWS Get Started）
- Step1-2 TerraformでS3作成→destroy完了
- Step1-3 READMEにTerraform手順（init/plan/apply/destroy）を書く

</details>

<details>
<summary>Step2：AWSネットワーク（VPC基礎）（親）</summary>

- Step2-1 VPCの全体像を図解で理解（用語整理）
- Step2-2 TerraformでVPC+Public Subnet+IGW+Routeを構築
- Step2-3 Private Subnet追加（NATは必要週まで温存）

</details>

<details>
<summary>Step3：IAM/SSM/Logs（運用の入口）（親）</summary>

- Step3-1 IAMの最小権限方針メモを作る
- Step3-2 CloudWatch Logsでログを見る導線を作る（最小）

</details>

<details>
<summary>Step4：ECS(Fargate)手動で動かす（親）</summary>

- Step4-1 最小Webアプリ（/health）を用意してDocker化
- Step4-2 ECRリポジトリ作成＋手動pushで動作確認
- Step4-3 ECS(Fargate)最小構成で起動（手動）

</details>

<details>
<summary>Step5：CI（GitHub Actions）導入（親）</summary>

- Step5-1 GitHub ActionsでCI（テスト/ビルド）を追加
- Step5-2 CIが落ちた時に直す練習（失敗→修正）

</details>

<details>
<summary>Step6：CD（Actions→ECR→ECS）完成（親）</summary>

- Step6-1 ActionsでECR pushを自動化
- Step6-2 ActionsでECSデプロイを自動化（CD完成）
- Step6-3 ロールバック手順（手動）をREADMEに書く

</details>

<details>
<summary>Step7：OIDC化（鍵を置かない）実務寄せ（親）</summary>

- Step7-1 GitHub Actions→AWSをOIDCでAssumeRoleできるようにする
- Step7-2 OIDCロールを最小権限に寄せる（ポリシー整理）

</details>

<details>
<summary>Step8：監視・アラート・ロールバック（親）</summary>

- Step8-1 監視対象を3つに絞って決める（5xx/Unhealthy/再起動）
- Step8-2 CloudWatchアラームを作成（最小3つ）
- Step8-3 ポストモーテム雛形を作る（障害後の振り返り）

</details>

<details>
<summary>Step9：TerraformでECS周りもIaC化（親）</summary>

- Step9-1 TerraformでECR/ECS/Logsを管理する（IaC化）
- Step9-2 Terraform modules分割方針を決める（標準化の入口）

</details>

<details>
<summary>Step10：改善を1点深掘り（価値づくり）（親）</summary>

- Step10-1 改善テーマを1つ選ぶ（セキュリティ/運用/コスト/DX）
- Step10-2 改善を実装してBefore/AfterをREADMEに残す

</details>

<details>
<summary>Step11：成果の言語化（README/構成図/設計意図）（親）</summary>

- Step11-1 構成図を作成（VPC/ECS/ECR/Actions/Logs/Alarms）
- Step11-2 READMEを面接資料レベルに仕上げる（設計意図/運用/改善）

</details>

<details>
<summary>Step12：転職接続（想定QA/職務経歴書接続）（親）</summary>

- Step12-1 想定QAを10問作る（面接で聞かれる質問＋回答）
- Step12-2 職務経歴書に載せる文章を作る（成果物要約＋成果）

</details>

---

## 10. 成果物リンク（docs）

- [`docs/Step1-2_setup-awscli.md`](docs/Step1-2_setup-awscli.md)（AWS CLIの初期設定、認証の準備）
- [`docs/Step1-2_terraform-s3.md`](docs/Step1-2_terraform-s3.md)（Terraform最小成功としてS3作成→確認→destroyまで）
- [`docs/Step1-3_terraform-basics.md`](docs/Step1-3_terraform-basics.md)（terraform init/plan/apply/destroy の基本手順と注意点）
- [`docs/Step2-1_vpc-basics.md`](docs/Step2-1_vpc-basics.md)（VPCの基礎理解の整理）
- [`docs/Step2-2,3_terraform-vpc.md`](docs/Step2-2,3_terraform-vpc.md)（TerraformでVPC/サブネット/IGW/Routeを作った手順と要点）
- [`docs/Step3-1_iam-privilege-guide.md`](docs/Step3-1_iam-privilege-guide.md)（IAM最小権限の考え方／設計指針）
- [`docs/Step3-2_ecs-cloudwatch-logs.md`](docs/Step3-2_ecs-cloudwatch-logs.md)（ECS→CloudWatch Logsの導線、どこを見るか、詰まりどころ）
- [`docs/Step4_ecs-fargate-manual.md`](docs/Step4_ecs-fargate-manual.md)（ECS(Fargate)を手動で起動し、Public IPで疎通する最小構成）
- [`docs/Step5_ci-github-actions.md`](docs/Step5_ci-github-actions.md)（GitHub ActionsでCI（テスト/ビルド）を回す手順）
- [`docs/Step6-1,2_ci-cd-ecr-ecs.md`](docs/Step6-1,2_ci-cd-ecr-ecs.md)（ECR push〜ECS deployの自動化、変数設計、task-definition運用）
- [`docs/Step6-3_ecs-rollback.md`](docs/Step6-3_ecs-rollback.md)（デプロイ失敗時のロールバック手順：Task Definition revisionを戻す）
- [`docs/Step7_oidc-role-privilege.md`](docs/Step7_oidc-role-privilege.md)（OIDC Trust policyの縛り方と、Permission policy最小化（特にPassRole））
- [`docs/Step8-1,2_monitoring.md`](docs/Step8-1,2_monitoring.md)（監視：5xx/Unhealthy/タスク停止、CloudWatchアラーム設定）
- [`docs/Step8-3_incident-postmortem-template.md`](docs/Step8-3_incident-postmortem-template.md)（障害後に埋めるポストモーテム雛形）
- [`docs/Step8-3_incident-postmortem-guide.md`](docs/Step8-3_incident-postmortem-guide.md)（ポストモーテムの書き方・運用ルール・レビュー観点）
- [`docs/Step9-1_terraform-iac-ecr-ecs-logs.md`](docs/Step9-1_terraform-iac-ecr-ecs-logs.md)（ECR/ECS/LogsのIaC化）
- [`docs/Step9-2_terraform-module-strategy.md`](docs/Step9-2_terraform-module-strategy.md)（modules分割方針：いつ・どこで・どう分けるか）
- [`docs/Step10_pr-terraform-plan.md`](docs/Step10_pr-terraform-plan.md)（改善：PRでterraform plan自動実行＋差分可視化、remote state含む）


## 11. 構成図
![構成図](./architecture.drawio.svg)
