# Step9-1：TerraformでECR / ECS / CloudWatch LogsをIaC化する（apply/destroyで再現）

## ゴール（完了条件）
- `terraform apply` で **ECR / ECS / Logs（ログ基盤）** が再現できる
- `terraform destroy` で **片付く**
- つまり「AWSコンソール手作業に戻らない状態」を作る

---

## 前提（このStepで固定する値）
このStepでは、既存の手動構築で動いている環境の “固定値” をそのままTerraformに写す（名前を変えない）。

- Region：`ap-northeast-1`
- ECS Cluster：`infra-learning`
- ECS Service：`health-app-svc`
- Task Definition family：`health-app-task`
- Container name：`health-app`
- Log group：`/ecs/infra-learning/health-app`
- Log stream prefix：`ecs`

---

## 対象スコープ（IaC化するもの／しないもの）
### IaC化する（今回の対象）
最低限この6つをTerraform管理に入れる：

1. CloudWatch Logs：Log Group（`/ecs/infra-learning/health-app`）
2. IAM：ECS Task Execution Role（`ecsTaskExecutionRole`）＋必要権限
3. ECR：Repository（例：`health-app`）
4. ECS：Cluster（`infra-learning`）
5. ECS：Task Definition（`health-app-task`、awslogs設定を含む）
6. ECS：Service（`health-app-svc`）

### 今回はやらない（スコープ外）
- CloudWatch Alarm / SNS / EventBridge など「監視・通知の実装」（Step8側で扱う）
- VPC/Subnet/Security Group などネットワーク一式（既存のID参照が前提になりがち）

---

## 依存関係（ここを押さえると迷わない）
作る順番（依存の下から）：

1) CloudWatch Log Group  
2) IAM Execution Role（ECR pull / Logs送信に必要）  
3) ECR Repository（コンテナイメージの置き場＝“箱”）  
4) ECS Task Definition（ログ設定・ロール・イメージを参照）  
5) ECS Service（Task Definitionを参照して動かす）  
6) ECS Cluster（Serviceの器）

destroyは基本的に逆（上から）で安全：
Service → Task Definition → Cluster → Logs → ECR → IAM

---

## 進め方の方針（今回の本質）
このStepのポイントは **「新規で作り直す」よりも「既存をTerraform管理に入れる」**。

- 既にAWSに存在するリソースを **`terraform import` でstateに取り込む**
- 取り込み後に `terraform plan` を見て、まずは **差分0（現物一致）** を目指す  
  （差分が残ったままapplyすると、意図せず設定が変わって壊れることがある）

---

## 作業の流れ（ざっくり）
1. Terraformの骨格を用意（provider/variables/locals など）
2. Log Group をTerraform化（import → plan差分0）
3. `ecsTaskExecutionRole` をTerraform化（import → plan差分0）
4. ECR repo をTerraform化（import → plan差分0）
5. ECS Cluster をTerraform化（import → plan差分0）
6. ECS Task Definition をTerraform化（AWSからtask definition JSONを取得して現物一致に寄せる）
7. ECS Service をTerraform化（subnet/sg/assignPublicIp/desiredCount等を現物一致に寄せる）
8. 検証：`destroy → apply` が往復できることを確認

---

## 重要な注意点（ハマりどころ）
### 1) ECRは「箱」だけ。イメージは戻らない
`terraform destroy` で ECR repository を消すと、リポジトリ内の **イメージも消える**。  
`apply` でリポジトリは復活するが、**イメージはpushし直しが必要**。

### 2) Task Definitionのrevision番号は完全一致しないことがある
`apply` のたびにrevisionが積み上がる／過去revisionは残ることがある。  
重要なのは「同じ設定で動く」ことで、revision番号の一致自体は目的ではない。

### 3) `terraform destroy` は最初に必ず “何が消えるか” を確認する
いきなりdestroyせず、まずこれで対象を確認する：

```

terraform plan -destroy

```

---

## 完了チェックリスト（Doneの判定）
- `terraform plan` が `No changes` になる
- `terraform destroy` で対象が消える
- `terraform apply` で同じ箱が再作成できる

この3つが揃っていれば Step9-1 は完了でOK。