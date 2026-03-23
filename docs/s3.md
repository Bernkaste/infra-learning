## 目的

TerraformでS3バケットを作成し、AWS上で作成確認した後、destroyで削除まで完了させる。

## 設計方針

- まずは最小構成で「apply→確認→destroy」を通す
- 手順だけでなく「確認方法」「つまずきと対処」まで含めて再現性を担保する

## 前提

- AWS CLI v2 がインストール済み（手順は `docs/setup-awscli.md`）
- AWS認証が通っていること
    - `aws sts get-caller-identity`
- Terraformがインストール済み

推奨リージョン

- `ap-northeast-1`（東京）

## 構成（最小）

- `main.tf` に `provider aws` と `aws_s3_bucket` を定義する

注意（超重要）

- S3バケット名は全世界で一意。被ると作成に失敗する。
- バケット名には日付や乱数を含める（例：`<name>-20260323-001`）

## 手順（再現用）

1. 作業ディレクトリへ移動
- `cd <このstepのディレクトリ>`
2. `main.tf` を用意する（例）
- `terraform { required_providers { aws = { source = "hashicorp/aws" version = "~> 5.0" } } }`
- `provider "aws" { region = "ap-northeast-1" }`
- `resource "aws_s3_bucket" "this" { bucket = "<ユニークなバケット名>" }`
3. 初期化
- `terraform init`
4. 差分確認
- `terraform plan`
5. 作成
- `terraform apply`
- `yes`

## 検証（作成確認）

A. AWS CLIで確認（推奨）

- `aws s3api head-bucket --bucket <バケット名>`

成功するとエラーが出ない（または何も出ない）。

B. AWSコンソールで確認

- S3 → バケット一覧に表示されていること

## 破棄（destroy）

- `terraform destroy`
- `yes`

削除確認

- `aws s3api head-bucket --bucket <バケット名>`

`Not Found` 系のエラーになれば削除されている。
もしくは、AWSコンソールでバケット一覧から削除されていることを確認。

## つまずきと対処（原因別）

### 1) 認証が原因（Terraform以前）

症状

- `terraform apply` で認証/署名系エラー

対処

- まず `aws sts get-caller-identity` が通るか確認
- 通らなければ `docs/setup-awscli.md` に戻る

### 2) リージョン不一致

症状

- `AuthorizationHeaderMalformed` / `InvalidRegion` など

対処

- `aws configure get region` を確認
- Terraform側で `provider "aws" { region = "ap-northeast-1" }` のように固定

### 3) 権限不足（AccessDenied）

症状

- `AccessDenied` が出る

対処

- `aws sts get-caller-identity` の結果（Arn）で、実行主体を確認
- S3作成に必要な権限が付いているか確認（どのAPIで拒否されたかエラー全文を見る）

### 4) バケット名の重複

症状

- `BucketAlreadyExists` / `BucketAlreadyOwnedByYou`

対処

- バケット名を変更（末尾に日付＋連番＋乱数など）