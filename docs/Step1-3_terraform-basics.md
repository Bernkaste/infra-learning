## 目的

Terraformの最小ループ（init → plan → apply → destroy）を、自分と第三者が再現できる状態にする。

## 設計方針

- まずは「1回通す」を最優先（過剰な最適化・汎用化は後回し）
- 再現性のため、実行したコマンドと確認方法を必ず残す

## 前提

- Terraform がインストール済み
- AWS CLI v2 がインストール済み
- AWS認証が通っていること（STSで確認）
- 作業環境例：Windows + WSL2(Ubuntu) + Cursor

確認コマンド

- terraform
    - `terraform -version`
- AWS CLI
    - `aws --version`
- AWS認証（最重要）
    - `aws sts get-caller-identity`

## Terraform 実行手順（最小ループ）

1. 作業ディレクトリに移動
- `cd <terraformのディレクトリ>`
2. 初期化（プロバイダ取得・初回セットアップ）
- `terraform init`
3. 変更内容の確認（実行前レビュー）
- `terraform plan`
4. リソース作成
- `terraform apply`
- `yes`
5. リソース削除（後片付け）
- `terraform destroy`
- `yes`

## 検証（再現できた判定）

- `terraform apply` が成功する
- AWSコンソール or AWS CLIでリソースが作成されていることが確認できる
- `terraform destroy` が成功する
- 再度確認して、リソースが消えていることが確認できる

## つまずきポイント（切り分けの順番）

1) AWS認証が通っているか

- `aws sts get-caller-identity`

2) リージョンの不一致

- `aws configure get region`
- Terraform側で `provider "aws" { region = "ap-northeast-1" }` のように固定しているか

3) 権限不足（AccessDenied）

- 誰の権限で実行しているか（STSのArn）
- どのAPIで拒否されたか（エラーメッセージ全文）
　→「今の主体（ユーザー/ロール）のポリシーに、拒否された操作（例：s3:CreateBucket）がない」or「明示Denyがある」のように切り分けできる。