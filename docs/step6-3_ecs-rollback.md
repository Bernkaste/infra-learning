# ECS(Fargate) ロールバック手順（デプロイ失敗時の復旧Runbook）

## 0. 目的（完了条件）

デプロイ失敗時に、迷わず「何を」「どこで」「どう戻すか」を実行できるようにする。

本Runbookの復旧完了条件は以下：

- ECS Service のデプロイが安定している（新しいタスクが起動し続け、落ち続けない）
- CloudWatch Logs を見て、致命的なエラー（例外・権限拒否・設定ミス）が継続していない
- `curl -f http://<PublicIP>:8080/health` が成功する

---

## 1. この環境の固定値（Step6-1 / Step6-2より）

- AWS Region: `ap-northeast-1`
- AWS Account ID: `077024045672`
- ECR repo: `health-app`
- ECS Cluster: `infra-learning`
- ECS Service: `health-app-svc`
- ECS Task Definition family: `health-app-task`
- ECS Container name: `health-app`
- App Port: `8080`
- 疎通確認（Public IP直叩き）: `http://<PublicIP>:8080/health`

---

## 2. ロールバックの方針（最重要：何を戻すのか）

- ロールバックで戻す対象は「ECRのイメージ」そのものではなく、**ECS Service が参照する Task Definition revision**
- つまりやることは「Service が使う Task Definition を、直前に正常稼働していた revision に差し替える」だけ
- 原因調査は復旧後にやる（復旧が先）

補足：

- ECRに古いイメージが残っていても、Serviceが参照する Task Definition を変えない限り “古い版は起動しない”
- だから “Serviceが参照する revision を戻す” が最短で確実

---

# 手順A：AWS CLIでロールバックする（推奨：再現性が高い）

## A-1) 現在 Service が参照している Task Definition を確認する

目的：

- いま何が当たっているか（どのrevisionを使っているか）をまず確定する
- ここを飛ばすと「戻すべき先」が分からなくなる

```bash
aws ecs describe-services \\
  --region ap-northeast-1 \\
  --cluster infra-learning \\
  --services health-app-svc \\
  --query "services[0].taskDefinition" \\
  --output text
```

見方：

- `...task-definition/health-app-task:12` の `:12` が “現在のrevision”
- ロールバック先は通常「このひとつ前」になることが多いが、必ずしも1個前とは限らない（“正常稼働していた最後”が基準）

---

## A-2) ロールバック先候補（過去revision）を列挙する

目的：

- 戻せる候補（revision履歴）を一覧で見る

```bash
aws ecs list-task-definitions \\
  --region ap-northeast-1 \\
  --family-prefix health-app-task \\
  --sort DESC
```

判断ルール：

- “直前に正常だったrevision” が分かるならそれを選ぶ
- 分からない場合は「失敗したデプロイの直前に使っていたrevision」を選ぶ（ECSのEventsや時刻で照合する）

---

## A-3) 候補revisionの中身（特に image）を確認する

目的：

- “戻したい版のアプリ” を起動する設定になっているか確認する
- 事故防止（別repo / 別リージョン / 別コンテナ名など）に効く

```bash
aws ecs describe-task-definition \\
  --region ap-northeast-1 \\
  --task-definition health-app-task:<rollback-rev>
```

確認観点（パッと見る順）：

1. containerDefinitions の `name` が `health-app` か
2. `image` が `077024045672.dkr.ecr.ap-northeast-1.amazonaws.com/health-app:...` になっているか
3. `:...`（タグ）が “戻したい版” と一致しているか
- `latest` は判定が曖昧になりやすい
- コミットSHA等の一意タグなら「これに戻す」が判断しやすい

---

## A-4) Service をロールバック先revisionに切り替えて再デプロイ（ロールバック実行）

目的：

- Service が参照する Task Definition を戻す（= 起動するコンテナの版が戻る）

```bash
aws ecs update-service \\
  --region ap-northeast-1 \\
  --cluster infra-learning \\
  --service health-app-svc \\
  --task-definition health-app-task:<rollback-rev> \\
  --force-new-deployment
```

補足：

- `-force-new-deployment` は「差し替えを確実に走らせる」ためのスイッチ
- これを入れると、タスクの入れ替えが明示的に走るので初心者でも状況が追いやすい

---

## A-5) デプロイが落ち着いたか確認（安定確認）

```bash
aws ecs describe-services \\
  --region ap-northeast-1 \\
  --cluster infra-learning \\
  --services health-app-svc \\
  --query "services[0].deployments[*].{status:status,rolloutState:rolloutState,taskDefinition:taskDefinition}" \\
  --output table
```

見方：

- `rolloutState` が進んで、タスクが落ち着くこと
- ここで止まる/繰り返すなら、次の「CloudWatch Logs確認」に進む（原因はログに出る）

---

## A-6) 疎通確認（Public IPで /health）

```bash
curl -f http://<PublicIP>:8080/health
```

補足（初心者が迷う点）：

- Public IP はタスク再起動で変わりうる（固定URLではない）
- だから「ECSのTasks画面で Public IP を確認→curl」が最短

---

# 手順B：AWSコンソールでロールバックする（GUIで確実に実施）

## B-1) 現在の Service が参照しているrevisionを確認

1. AWS Console → ECS
2. Clusters → `infra-learning`
3. Services → `health-app-svc`
4. Service詳細で “Task definition（現在のrevision）” を確認

目的：

- “今のrevision” を確定して、戻す先を決めるため

---

## B-2) ロールバック先revisionを選ぶ（Task definitionsから選ぶ）

1. AWS Console → ECS → Task definitions
2. `health-app-task`（family）を開く
3. revision一覧から候補を選ぶ（直前に正常稼働していたrevision）
4. 対象revisionを開き、Container `health-app` の Image が想定通りか確認する

「想定通り」の判断軸（初心者用・短縮）：

- `077024045672`（アカウント） / `ap-northeast-1`（リージョン） / `health-app`（repo）になっているか
- タグ（`:xxxx`）が “戻したい版” を示しているか
    - `latest` は曖昧（ただし直前の安定revisionに戻すなら運用上は成立する）
    - SHAタグ等なら判断が簡単

---

## B-3) Serviceをロールバック先revisionに更新（ロールバック実行）

1. ECS → Clusters → `infra-learning`
2. Services → `health-app-svc`
3. Update（更新）
4. Task definition revision をロールバック先（例：`health-app-task:11`）に変更
5. Update（更新）を実行

---

## B-4) 復旧確認（Events → Tasks → Logs → /health）

迷いにくい確認順：

1. Services → `health-app-svc` → Events
- “デプロイが進んでいる/失敗している” がここに出る
2. Services → `health-app-svc` → Tasks
- RUNNINGになっているか
- 落ち続けていないか（起動→停止ループは失敗）
3. CloudWatch Logs（次章参照）
- タスクが落ちる理由はログに出ることが多い
4. /health 疎通
- Public IP をタスクから確認して `curl`

---

# CloudWatch Logs：見に行き方（Step3-2に合わせた導線）

## 目的

- 「タスクが落ちる理由」「アプリが起動できているか」を最短で確認する
- 復旧完了条件のうち “致命的エラーが出ていない” をここで判断する

---

## 1) まず“見る場所”の結論

CloudWatch → Logs → Log groups → 該当ロググループ → 最新の Log stream を開く

Step3-2での基準：

- ロググループは `/ecs/<project>/<service>` 系で固定すると迷わない
- nginx例：`/ecs/infra-learning/nginx`
- Log stream は `ecs/<container-name>/<task-id>` みたいな形になりやすい（prefixが `ecs` のため）

---

## 2) 今回（health-app）で、まず探すロググループ候補

タスク定義の Logging 設定次第で変わるので、「探し方」を固定する。

### 探し方（最短）

1. ECS → Task definitions → `health-app-task` → 対象revision
2. Container `health-app` を開く
3. Logging セクションを見る
    - Log driver が `awslogs` になっているか
    - Log group 名が何になっているか（ここが正解）

その Log group 名が、この後 CloudWatch で開くべき場所。

補足：

- “推測でロググループ名を当てに行く” と迷うので、タスク定義から逆引きが一番確実

---

## 3) CloudWatch Logsでの手順

1. AWS Console → CloudWatch
2. 左メニュー `Logs` → `Log groups`
3. 2)で確認した Log group を検索して開く
4. `Log streams` 一覧で `Last event time` が最新のものを開く
    - これが「今動いたタスクの最新ログ」である可能性が一番高い
5. まずこの順で検索（ブラウザ検索でOK）
    - `error`
    - `exception`
    - `traceback`
    - `AccessDenied`
    - `CannotPullContainerError`
    - `ResourceInitializationError`

---

## 4) 何を見れば「復旧できた」と言えるか（ログ観点）

- 起動直後にエラーが連発していない
- “アプリ起動完了” が分かるログが出ている、または少なくとも落ちていない
- 失敗しているなら、原因の単語（権限不足、環境変数不足、ポート不一致、依存不足）がログに出る

---

## 5) ログが見つからない時の切り分け（最短）

### パターンA：Log group が存在しない

- タスク定義の logging が `awslogs` になっていない可能性
- または Log group 名が別名になっている（タスク定義から再確認）

### パターンB：Log group はあるが Log stream が1本もない

- Task execution role の権限不足の可能性が高い（logs:CreateLogStream / logs:PutLogEvents）
- タスク定義の `awslogs-region` / `awslogs-group` のタイポ

### パターンC：Log stream はあるが中身が空

- 少し待つ（数十秒〜）
- それでも空なら execution role / awslogs設定を疑う

---

# よくある失敗と即チェック（ロールバック時）

## 症状1：ロールバック後もタスクが起動→停止を繰り返す

見る順：

1. ECS Service Events
2. CloudWatch Logs（直近Log stream）
3. タスク定義のポート/環境変数/イメージ

---

## 症状2：/health が見れない

- SG inbound が `8080/TCP` を My IP `/32` で許可しているか
- Public IP が付いているか（タスク詳細で確認）
- そもそもタスクがRUNNINGか（落ちてたらログへ）

---

# 復旧後（原因調査・再発防止）

- 失敗した revision と、復旧に使った revision を記録する
- CloudWatch Logsで見えた根本原因（例：env不足、ポート違い、権限拒否）を短くメモする
- 次回のために「安定revisionはこれ」を残す
