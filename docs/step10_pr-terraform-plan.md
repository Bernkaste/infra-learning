## 改善内容（What / Why / Scope）

### What（何をやるか）
- PR作成/更新時に GitHub Actions を起動し、Terraform の以下を自動実行する
	- `terraform fmt`（フォーマットチェック）
	- `terraform validate`（構文・設定の妥当性チェック）
	- `terraform plan`（差分確認）
- `terraform plan` の結果（差分）を PR 上にコメント（またはサマリ）として表示する

### Why（なぜやるか）
- IaC変更を **安全に** かつ **早く** 届けるため
- Terraform plan をPRで自動実行し、**誰でも同じ差分** を確認できる状態にする（再現性の担保・レビュー品質向上）
- レビュアーがローカル実行しなくてよくなり、手作業と属人性を減らす

### Scope（範囲・やらないこと）
- PR時点では `apply` は実行しない（planまで）
- 対象：Terraform ディレクトリ（`infra-learning/aws-terraform/step9-1/`）
- plan をCI上で成立させるため、Terraform state を remote backend（S3）に移行し、ロックに DynamoDB を利用する（S3 + DynamoDB）

---

## Before / After（指標）

### Before / After（概要）
- Before：PR運用はあるが、plan/apply はローカルで実行。差分確認が人依存で再現性が弱い
- After：PRを作ると自動で plan が走り、差分がPRに表示される。レビューが再現可能になり、変更の安全性が上がる

### KPI 1：plan確認の手作業ステップ数
| 項目 | Before | After |
|---|---|---|
| 手作業ステップ数 | レビュアーがローカルで実行（手順あり） | PRを出すだけ（手作業0） |
| 具体例 | PRブランチ取得 → AWS認証（AssumeRole等）→ `terraform init` → `terraform plan` → 結果共有 | PR作成/更新 → Actionsが自動実行 → PR上で差分確認 |

### KPI 2：PRレビュー完了までの時間（目安）
| 項目 | Before | After |
|---|---:|---:|
| 差分確認にかかる時間 | 10〜20分 | 約5分 |

---

## 実装（構成・ワークフロー概要）

### 全体構成
- Terraform backend：S3（state保存） + DynamoDB（state lock）
- GitHub Actions：OIDCでAWSへ認証し、PR上で `fmt/validate/plan` を実行して結果を表示（全文は折りたたみ）

### ワークフロー（実行順）
1. Checkout
2. AWS認証（OIDC AssumeRole）
3. `terraform init`（backend = S3 + DynamoDB）
4. `terraform fmt`（必要なら差分検知で失敗させる）
5. `terraform validate`
6. `terraform plan`
7. plan結果をPRにコメント（またはサマリ）として投稿

### ワークフローの要点
- `terraform plan -out=tfplan` → `terraform show tfplan > plan.txt` で **plan.txt を確実に生成**
- `actions/github-script` で `plan.txt` を読み込み、PRにコメント

---

## 結果（動いた証拠）

- PRリンク：https://github.com/Bernkaste/infra-learning/pull/31
- Actions実行ログ：https://github.com/Bernkaste/infra-learning/actions/runs/24076341741
- PRに出力された plan の例：
### PRコメント（plan出力例）

<details>
<summary>Terraform Plan (aws-terraform/step9-1)</summary>

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  ~ update in-place

Terraform will perform the following actions:

  # aws_ecs_service.app will be updated in-place
  ~ resource "aws_ecs_service" "app" {
        id                                 = "arn:aws:ecs:ap-northeast-1:077024045672:service/infra-learning/health-app-svc"
        name                               = "health-app-svc"
        tags                               = {
            "Managed" = "terraform"
            "Project" = "infra-learning"
            "Step"    = "9-1"
        }
      ~ task_definition                    = "arn:aws:ecs:ap-northeast-1:077024045672:task-definition/health-app-task:12" -> "arn:aws:ecs:ap-northeast-1:077024045672:task-definition/health-app-task:9"
        # (16 unchanged attributes hidden)

        # (3 unchanged blocks hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.

</details>

- Backend: S3 + DynamoDB
- Trigger: pull_request

---

## 学び（詰まり→原因→対処）

- `defaults.run.working-directory` は `run:` には効くが、`uses:` ステップ（例：`actions/github-script`）ではカレントがズレることがある  
  → `readFileSync("aws-terraform/step9-1/plan.txt")` のように **repo root からのパスで読む**と安定する
- plan結果をPRで“信用できる形”にするには state の共有が必要  
  → S3 backend + DynamoDB lock に移行すると、CIでも同じ前提で plan が出せる
- plan全文は長くなりやすい  
  → 折りたたみ（`<details>`） + コメント上限対策（truncation）を設けることで、チーム運用を見据えてレビューしやすい見せ方にしている

### 次の改善案（任意）
- ブランチ保護で「Terraform Plan」を必須チェック化
　→mainにマージするにはTerraform Planワークフローが成功していることを必須条件にする
- 変更の種類に応じて（destroy含む等）注意喚起を自動で付ける