# Monitoring & Alerts（Step8-1 / Step8-2）

## 目的
- Step8-1：監視対象を3つに絞って「何を・どう検知するか」を決める
- Step8-2：CloudWatch上でアラーム（最小3つ）を作り、SNSメール通知が「実際に飛ぶ」状態まで到達する

---

## 前提（この環境の構成）
- 現状の動作確認は **Public IP直叩き**（例：`http://<PublicIP>:8080/health`）
- この前提だと **ALBは必須ではない**
  - つまり、ALB前提の `HTTPCode_Target_5XX_Count` や `UnHealthyHostCount` などは使えない（/成立しない）
- したがって監視は **ECS（イベント/メトリクス） + CloudWatch Logs（ログ）** 中心で組む

### 固定値（環境の識別子）
- Region：`ap-northeast-1`
- ECS Cluster：`infra-learning`
- ECS Service：`health-app-svc`
- Task Definition family：`health-app-task`
- Container：`health-app`
- Port：`8080`

（例：ログ出力設定で使う値）
- Log group：`/ecs/infra-learning/health-app`
- Log stream prefix：`ecs`

---

## Step8-1：監視対象を3つに絞って決める（設計）
ここでは **「監視対象3つ・閾値・通知先」** を決めるだけ。作成作業（CloudWatch/SNS操作）は Step8-2 で実施する。

### 監視対象（3つ）
1) **5xx（アプリ内部エラー）**
- ALBが無いのでALBメトリクスでは監視できない
- 代替：**アプリログをCloudWatch Logsに出し、ログから “5xx/ERROR相当” をメトリクス化して検知する**

2) **Unhealthy（ヘルス失敗）**
- ALBが無いので `UnHealthyHostCount` は無い
- 代替：**`/health` の失敗を示すログ**（またはヘルスが維持できない兆候）をログから検知する

3) **タスク再起動/停止（タスクが維持できない）**
- 最重要。**ECS側（イベント/メトリクス）で成立する**
- 「タスクが落ちる・起動できない」を最短で検知して通知する

### 通知先（決めるだけ）
- 最短で検証しやすい：**SNS Topic → Email**

### 先に潰すべき前提（ログが届かない原因）
CloudWatch Logs にアプリログが溜まらない原因は、ほぼこのどちらか（または両方）。
- タスク定義に `logConfiguration`（awslogs）が入っていない
- `ecsTaskExecutionRole` に CloudWatch Logs 書き込み権限が足りない（`logs:CreateLogStream` / `logs:PutLogEvents` など）

---

## Step8-2：CloudWatchアラームを作成（最小3つ）
完了条件：**「5xx / Unhealthy / タスク再起動」のいずれかで、メール通知が実際に飛ぶ」**

### 全体像（ログ→通知）
1. ECSがログをCloudWatch Logsに出す
2. Logsの **Metric filter** が異常ログを検知してメトリクス化
3. CloudWatch Alarm がしきい値超えで SNS 通知
4. SNS が Email に配信

---

## 1) 事前ゲート：CloudWatch Logs にログを溜める（必須）
ここが通ってないと、5xx/Unhealthyのアラーム（ログ由来）が作れないし、原因調査も詰む。

### 1-A. タスク定義に awslogs を入れる（`ecs/task-definition.json`）
`containerDefinitions` の該当コンテナに追加（値は環境に合わせて置換）：

```

"logConfiguration": {

   "logDriver": "awslogs",

   "options": {

      "awslogs-group": "/ecs/infra-learning/health-app",

      "awslogs-region": "ap-northeast-1",

      "awslogs-stream-prefix": "ecs"

   }

}

```

### 1-B. `ecsTaskExecutionRole` の権限を確認
最低限必要：
- `logs:CreateLogStream`
- `logs:PutLogEvents`

（状況により必要）
- `logs:DescribeLogStreams`
- `logs:CreateLogGroup`

最短は `AmazonECSTaskExecutionRolePolicy` が付いていること。

### 1-C. ログが溜まっていることを確認
CloudWatch → Logs → Log groups → `/ecs/infra-learning/health-app`
- Log streams が増えて、アプリログが見えること

---

## 2) 通知先：SNS Topic → Email を作る
1. SNS → Topics → `health-app-alerts`（任意名）を作成
2. Subscriptions を作成
   - Protocol：Email
   - Endpoint：自分のメール
3. 届いたメールで **Confirm subscription**
   - これをやらないと通知は絶対に届かない

---

## 3) アラーム①（最短で確実）：タスク停止を通知（EventBridge → SNS）
狙い：**タスクが STOPPED になったら即メール**

### 3-A. EventBridge ルール作成
- Name：`ecs-task-stopped-alert`
- Event bus：default
- Rule type：event pattern

### 3-B. Event pattern（サービスで絞る例）
```

{

   "source": ["aws.ecs"],

   "detail-type": ["ECS Task State Change"],

   "detail": {

      "clusterArn": [{ "prefix": "arn:aws:ecs:ap-northeast-1:077024045672:cluster/infra-learning" }],

      "lastStatus": ["STOPPED"],

      "group": [{ "prefix": "service:health-app-svc" }]

   }

}

```

### 3-C. Target（通知先）
- SNS topic：`health-app-alerts`

---

## 4) アラーム②：5xx（ログ → メトリクスフィルタ → アラーム）
ALBが無いのでログから拾う。

### 4-A. まず「5xxの判定文字列」を決める
CloudWatch Logs で実ログを見て、以下のどれが出ているかで選ぶ。
- `500`
- `ERROR`
- `Exception` / `Traceback`

### 4-B. Logs Metric filter を作成
CloudWatch → Logs → Log groups → `/ecs/infra-learning/health-app` → Metric filters
- Filter pattern：例 `"ERROR"`（※実ログに合わせる）
- Namespace：`InfraLearning/HealthApp`
- Metric name：`App5xxCount`
- Metric value：`1`

### 4-C. そのメトリクスでアラーム作成
CloudWatch → Metrics → `InfraLearning/HealthApp` → `App5xxCount`
- Statistic：Sum
- Period：5 minutes（最初はこれでOK）
- Threshold：`>= 1`
- 通知：SNS `health-app-alerts`

NOTE：
- Metric filter は「1回でもマッチ」して初めてメトリクスが生成される
- まだ1回も `ERROR` 等が出ていないと、Metrics 側に Namespace/Metric が見えないことがある

---

## 5) アラーム③：Unhealthy（ログ → メトリクスフィルタ → アラーム）
### 5-A. 判定ルール
- `/health` の失敗を示すログがある前提で作る（例：`/health` + `500` / `timeout` 等）

### 5-B. Metric filter を作成
- Filter pattern（例）：`"/health"`（必要なら失敗条件を追加）
- Namespace：`InfraLearning/HealthApp`
- Metric name：`HealthUnhealthyCount`
- Metric value：`1`

### 5-C. アラーム作成
- Statistic：Sum
- Period：5 minutes
- Threshold：`>= 1`
- 通知：SNS `health-app-alerts`

---

## 6) 検証（メールを飛ばして完了にする）
最短で確実なのは **アラーム①（タスク停止通知）** を発報させること。

例：ECSサービスの Desired tasks を `1 → 0` にして意図的に止める
- 通知メールが来たら Step8-2 完了
- 検証後は Desired tasks を `1` に戻す
