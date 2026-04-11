# Step5: CI（GitHub Actions）導入（pytest + Docker build）

このドキュメントは、最小のFlaskアプリ（`/health`）を対象に、GitHub ActionsでCIを動かす手順をまとめたもの。  

目的は「push/PRで自動的にテストとDocker buildを実行し、壊れたらCIが落ちる状態」を作ること。

## 完了条件

- push または pull request のたびに GitHub Actions のCIが自動実行される
- テストが失敗したらCIが落ちる（赤くなる）
- 意図的にCIを落として、Actionsログから原因を特定し、修正して成功（緑）に戻せる

---

## 前提（リポジトリ構成の例）

- `health-app/` 配下にFlaskアプリがある
- 例：
    - `health-app/app.py`
    - `health-app/requirements.txt`
    - `health-app/Dockerfile`

`working-directory` を使って、Actionsの実行ディレクトリを `health-app` に寄せるのがポイント。

---

## 1. テスト（pytest）の最小セットを用意する

### 1-1. テストファイルを追加

`health-app/tests/test_health.py`

```python
import app

def test_health_returns_ok():
    client = app.app.test_client()
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.data == b"ok"
```

### 1-2. 開発用依存にpytestを追加

`health-app/requirements-dev.txt`

```
pytest==8.1.1
```

---

## 2. GitHub Actions のCIワークフローを追加する

`.github/workflows/ci.yml` を作成する。

- `on: push` と `on: pull_request` を両方有効化する
- `pytest` と `docker build` はジョブを分ける（ログが読みやすい）

```yaml
name: CI

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        working-directory: health-app
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install -r requirements-dev.txt

      - name: Run tests
        working-directory: health-app
        run: |
          python -m pytest -q

  docker-build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build Docker image (sanity check)
        working-directory: health-app
        run: |
          docker build -t health-app:ci .
```

補足：`pytest` は `python -m pytest` 推奨。環境差で「pytestコマンドが参照しているPython」がズレる事故を避けられる。

---

## 3. 動作確認（push/PRで自動実行されること）

### 3-1. pushで確認

```bash
git add -A
git commit -m "Add CI (pytest + docker build)"
git push
```

GitHubリポジトリの Actions タブで `CI` が動き、成功（緑）になればOK。

### 3-2. PRで確認（推奨）

- mainからブランチを切る
- 変更をpush
- PR作成
- PRの Checks に `CI` が出て成功（緑）になればOK

---

## 4. Step5-2: CIを意図的に落として復旧する（練習）

### 4-1. わざと落とす（例）

`health-app/tests/test_health.py` の期待値を間違える（どれか1つでOK）

- `assert resp.status_code == 200` → `assert resp.status_code == 201`

または

- `assert resp.data == b"ok"` → `assert resp.data == b"ng"`

pushすると、`test` job が失敗する。

### 4-2. ログで原因を特定する

GitHub Actions → 該当Run → `test` job → `Run tests` step を開く。  

pytestの出力に「失敗した行（ファイル名と行番号）」と「期待値と実際の差分」が出るので、そこを読む。

### 4-3. 修正して緑に戻す

テストを元に戻してpush。CIが成功（緑）に戻れば復旧完了。

---

## よくある詰まりポイント（最小）

- `requirements-dev.txt not found`
    - ファイル名/場所ミス。CIで参照しているパスと一致しているか確認。
- `pytest: command not found`
    - `pip install -r requirements-dev.txt` がCI内で実行されているか確認。
- `ModuleNotFoundError: No module named 'app'`
    - `working-directory: health-app` が不足している可能性が高い。
    - テスト実行ディレクトリ（Pythonの探索パス）と `app.py` の位置を合わせる。

---

## 次のステップ

CIが安定して動いたら、次はCD（ECR push / ECS deploy）へ進む。