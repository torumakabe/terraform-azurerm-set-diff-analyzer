# AzureRM Set Diff Analyzer Script

Terraform plan JSON を分析し、AzureRM Set型属性の「偽差分」を識別するPythonスクリプトです。

## 概要

AzureRM Provider の Set 型属性（`backend_address_pool`、`security_rule` など）は順序が保証されないため、要素の追加・削除時に全要素が「変更」として表示される問題があります。このスクリプトは、そのような「偽差分」と実際の変更を区別します。

### 使用用途

- **Copilot CLI Skill** として（推奨）
- **CLI ツール** として手動実行
- **CI/CD パイプライン** で自動分析

## 前提条件

- Python 3.8 以上
- 追加パッケージ不要（標準ライブラリのみ使用）

## 使用方法

### 基本的な使い方

```bash
# ファイルから読み込み
python analyze_plan.py plan.json

# 標準入力から読み込み
terraform show -json plan.tfplan | python analyze_plan.py
```

### オプション

| オプション | 短縮形 | 説明 | デフォルト |
|-----------|--------|------|-----------|
| `--format` | `-f` | 出力形式（markdown/json/summary） | markdown |
| `--exit-code` | `-e` | 変更に応じた終了コードを返す | false |
| `--quiet` | `-q` | 警告を抑制 | false |
| `--verbose` | `-v` | 詳細な警告を表示 | false |
| `--ignore-case` | - | 大文字小文字を無視して比較 | false |
| `--attributes` | - | カスタム属性定義ファイルのパス | (内蔵) |
| `--include` | - | 分析対象リソースのフィルタ（複数指定可） | (全て) |
| `--exclude` | - | 除外するリソースのフィルタ（複数指定可） | (なし) |

### 終了コード（`--exit-code` 使用時）

| コード | 意味 |
|--------|------|
| 0 | 変更なし、または順序変更のみ |
| 1 | Set型属性の実際の変更あり |
| 2 | リソース再作成（delete + create）あり |
| 3 | エラー |

## 出力フォーマット

### Markdown（デフォルト）

PRコメントやレポート向けの人間可読形式です。

```bash
python analyze_plan.py plan.json --format markdown
```

### JSON

プログラム処理向けの構造化データです。

```bash
python analyze_plan.py plan.json --format json
```

出力例:
```json
{
  "summary": {
    "order_only_count": 3,
    "actual_set_changes_count": 1,
    "replace_count": 0,
    "create_count": 0,
    "delete_count": 0,
    "other_changes_count": 2
  },
  "has_real_changes": true,
  "resources": [...],
  "warnings": []
}
```

### Summary

CI/CD ログ向けの1行サマリーです。

```bash
python analyze_plan.py plan.json --format summary
```

出力例:
```
🟢 3 order-only | 🟡 1 set changes | ℹ️ 2 other
```

## CI/CD パイプラインでの使用

### GitHub Actions

```yaml
name: Terraform Plan Analysis

on:
  pull_request:
    paths:
      - '**.tf'

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        
      - name: Terraform Init & Plan
        run: |
          terraform init
          terraform plan -out=plan.tfplan
          terraform show -json plan.tfplan > plan.json
          
      - name: Analyze Set Diff
        run: |
          python path/to/analyze_plan.py plan.json --format markdown > analysis.md
          
      - name: Comment PR
        uses: marocchino/sticky-pull-request-comment@v2
        with:
          path: analysis.md
```

### GitHub Actions（終了コードでゲート）

```yaml
      - name: Analyze and Gate
        run: |
          python path/to/analyze_plan.py plan.json --exit-code --format summary
        # exit code 2 (resource replacement) で失敗させる場合
        continue-on-error: false
```

### Azure Pipelines

```yaml
- task: TerraformCLI@0
  inputs:
    command: 'plan'
    commandOptions: '-out=plan.tfplan'

- script: |
    terraform show -json plan.tfplan > plan.json
    python scripts/analyze_plan.py plan.json --format markdown > $(Build.ArtifactStagingDirectory)/analysis.md
  displayName: 'Analyze Plan'

- task: PublishBuildArtifacts@1
  inputs:
    pathToPublish: '$(Build.ArtifactStagingDirectory)/analysis.md'
    artifactName: 'plan-analysis'
```

### フィルタリング例

特定のリソースのみ分析:
```bash
python analyze_plan.py plan.json --include application_gateway --include load_balancer
```

特定のリソースを除外:
```bash
python analyze_plan.py plan.json --exclude virtual_network
```

## 判断の解釈

| 分類 | 意味 | 推奨アクション |
|------|------|---------------|
| 🟢 順序変更のみ | 偽差分、実際の変更なし | 無視してOK |
| 🟡 実際の変更 | Set要素の追加/削除/変更 | 内容を確認、通常はin-place更新 |
| 🔴 リソース再作成 | delete + create | ダウンタイム影響を確認 |
| ➕ 新規作成 | 新しいリソース | 意図した追加か確認 |
| ➖ 削除 | リソース削除 | 意図した削除か確認 |
| ℹ️ その他 | 非Set型属性の変更 | 通常のレビュー |

## カスタム属性定義

デフォルトでは `references/azurerm_set_attributes.json` を使用しますが、カスタム定義ファイルを指定できます:

```bash
python analyze_plan.py plan.json --attributes /path/to/custom_attributes.json
```

定義ファイルの形式については `references/azurerm_set_attributes.md` を参照してください。

## 制限事項

- AzureRM リソース（`azurerm_*`）のみが対象です
- 一部のリソース/属性は未対応の場合があります
- `after_unknown`（apply後に判明する値）を含む属性は比較が不完全になる場合があります
- Sensitive 属性はマスクされているため、比較が不完全になる場合があります

## 関連ドキュメント

- [SKILL.md](../SKILL.md) - Copilot CLI Skill としての使用方法
- [azurerm_set_attributes.md](../references/azurerm_set_attributes.md) - 属性定義のリファレンス
