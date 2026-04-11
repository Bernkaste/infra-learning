## 目的

Terraform実行の前提として、WSL(Ubuntu)でAWS CLI v2を導入し、認証が通る状態（STSが成功）まで持っていく。

## 背景（なぜ公式インストーラを使うか）

- `sudo apt install awscli` が入らない / リポジトリ依存でハマることがある
- 公式インストーラはUbuntu環境差分の影響を受けにくく、確実に入る

## 前提

- WSL(Ubuntu) のターミナルで実行する

## 手順：AWS CLI v2 インストール（公式）

1. 依存ツールを入れる
- `sudo apt update`
- `sudo apt install -y curl unzip`
2. AWS CLI v2 をダウンロードしてインストール
- `curl -L "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip`
- `unzip -q awscliv2.zip`
- `sudo ./aws/install --update`
3. バージョン確認
- `/usr/local/bin/aws --version`
- `aws --version`

## 手順：認証（aws configure）

4. 設定
- `aws configure`

入力例

- Default region name: `ap-northeast-1`（東京）
- Default output format: `json`
5. 設定確認
- `aws configure list`
- `aws configure get region`

## ゴール確認（最重要）

- `aws sts get-caller-identity`

このコマンドが成功すれば「AWS認証が通っている」が確定し、Terraform側の検証に進める。

## つまずきメモ

- IAMユーザー/アクセスキー周りで権限不足が出る場合がある
　→PowerUserAccessポリシーでは、IAMユーザー自身がアクセスキーを作成できない
　　→Rootユーザーに作成してもらうか、JSON形式でアクセスキー周りの権限を記述する
- 原因切り分けは「STSが通るか」→「S3など対象サービスの権限があるか」の順で行う