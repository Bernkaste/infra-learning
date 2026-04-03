# CI/CD: GitHub Actions → ECR → ECS(Fargate)

## このdocsの目的

最小のWebアプリ（例：`/health`）を Docker 化し、GitHub Actions で

- mainへの変更をトリガーに Docker image をビルド
- ECRへpush
- ECS(Fargate)のServiceを更新して新しいタスクを起動

までを自動化する。

ポイント：

- ECSはECRを監視して自動更新しない。ECSを更新するには「Service更新（Task Definitionの新revision適用）」が必要。

---

## 全体像（何がどこにあるか）

- GitHub repository：ソースコード、GitHub Actions workflow、Task Definitionテンプレ（JSON）
- ECR：ビルドされたDocker image（成果物）
- ECS(Fargate)：Task Definition（起動設計図）と Service（運用）によってタスクを起動

デプロイの流れ（最小）：

1. mainにpush/merge
2. ActionsがDocker build
3. ActionsがECRへpush（タグはコミットSHA推奨）
4. ActionsがTask Definitionのimageだけ差し替えて新revision登録
5. ActionsがECS Serviceを更新（ローリング更新）
6. 稼働確認（/health）

---

## 固定値

この環境は以下のような値を想定する（必要に応じて置換）。

- AWS Region: `ap-northeast-1`
- AWS Account ID: `<AWS_ACCOUNT_ID>`
- GitHub repo: `<GITHUB_OWNER>/<GITHUB_REPO>`
- ECR repo: `health-app`
- ECS Cluster: `infra-learning`
- ECS Service: `health-app-svc`
- ECS Task Definition family: `health-app-task`
- ECS Container name: `health-app`
- App Port: `8080`

---

## Step6-1：GitHub Actionsで ECR push を自動化（要点）

### 何を作るか（最小）

- AWS側：GitHub Actions がAWSに入るための OIDC Provider + IAM Role
- GitHub側：ECRへpushするworkflow

### GitHub Actionsに渡す値（Repository Variables / Secrets）

以下の値をGitHub ActionsのVariables/Secretsに登録する。

例（VariablesでもSecretsでも可）：

- `AWS_REGION = ap-northeast-1`
- `AWS_ACCOUNT_ID = <AWS_ACCOUNT_ID>`
- `ECR_REPOSITORY = health-app`
- `AWS_ROLE_ARN = arn:aws:iam::<AWS_ACCOUNT_ID>:role/<GITHUB_ACTIONS_ROLE_NAME>`

注意：

- Variablesは「NameとValueを1個ずつ」登録する（まとめ貼りで参照ミスが起きやすい）

### 完了条件（ECR側で確認）

- mainに変更を入れるとActionsが成功する
- ECRに `health-app:<commit_sha>`（推奨）や `health-app:latest` が作成/更新される

推奨運用：

- “どのコミットが動いているか” を追えるので、タグはコミットSHAを主に使う（`latest`だけに依存しない）

---

## Step6-2：GitHub Actionsで ECSデプロイを自動化（要点）

### 先にECS側に「更新対象」を作っておく

CDは「既存のECS Serviceを更新」するので、最低限これが必要：

- Cluster（例：`infra-learning`）
- Service（例：`health-app-svc`）
- Task Definition family（例：`health-app-task`）

### 方式（なぜ task-definition.json を置くのか）

`ecs/task-definition.json` をリポジトリに置くと、次のメリットがある：

- コンソール手作業のブレが減る（再現性が上がる）
- 変更点を “image差し替え” に限定できて事故が減る
- revision履歴が残るのでロールバックが簡単になる（Serviceを前のrevisionに戻すだけ）

---

## 動作確認（最短）

1. mainに変更を反映（PR→merge推奨）
2. GitHub Actionsが成功（緑）
3. ECSコンソールで Service の deployment が進む
4. タスクの稼働確認（/health）

例：

- `curl -f http://<PUBLIC_IP>:8080/health`

補足：

- 学習用にPublic IP直叩き構成の場合、IPは変わりうるので “タスクの詳細画面から確認して叩く” が確実

---

## CloudWatch Logs（障害時にまず見る場所）

目的：

- タスクが落ちる理由（例外・設定不足・権限不足）を最短で特定する

見る手順（迷わない導線）：

1. ECS → Task definitions → 対象revision → Container `health-app`
2. Logging設定から “Log group 名” を確認（ここが正解）
3. CloudWatch → Logs → Log groups → そのLog groupを開く
4. Log streams で `Last event time` が最新のものを開く
5. まず検索する語：
- `error`
- `exception`
- `traceback`
- `AccessDenied`
- `CannotPullContainerError`
- `ResourceInitializationError`

---

## よくある詰まりポイント（最短チェック）

### Actions成功なのにECSが更新されない

- workflowの `ECS_CLUSTER` / `ECS_SERVICE` の参照先が正しいか
- ECS側にServiceが存在するか（作成できているか）

### デプロイが進むがタスクが落ち続ける

- ECS Service の Events
- CloudWatch Logs（上の手順）

### /healthが見れない

- Security Groupの inbound が `8080/TCP` を許可しているか（公開repoなら “My IP/32” の例は伏せて書く）
- Public IP が付いているか
- タスクがRUNNINGか（落ちてたらLogsへ）
