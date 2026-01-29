---
name: azurerm-set-diff-analyzer
description: Analyze Terraform plan JSON output for AzureRM Provider to distinguish between false-positive diffs (order-only changes in Set-type attributes) and actual resource changes. Use when reviewing terraform plan output for Azure resources like Application Gateway, Load Balancer, Firewall, Front Door, NSG, and other resources with Set-type attributes that cause spurious diffs due to internal ordering changes.
license: Complete terms in LICENSE
---

# AzureRM Set Diff Analyzer

AzureRM ProviderのSet型属性による「偽差分」を識別し、実際の変更と区別するためのスキルです。

## いつ使うか

- `terraform plan` で大量の変更が表示されるが、実際には1つの要素を追加/削除しただけ
- Application Gateway、Load Balancer、NSG等で「全要素が変更」と表示される
- CI/CDで偽差分を自動的にフィルタリングしたい

## 背景

TerraformのSet型はキーではなく位置で比較するため、要素の追加・削除時に全要素が「変更」として表示される問題があります。これはTerraform全般の課題ですが、Application Gateway、Load Balancer、NSG等のSet型属性を多用するAzureRMリソースで特に顕著です。

この「偽差分」は実際にはリソースに影響を与えませんが、terraform planの確認を困難にします。

## 基本的な使い方

```bash
# 1. planのJSON出力を生成
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json

# 2. 分析
python scripts/analyze_plan.py plan.json
```

## 出力の見方

| 分類 | 意味 | アクション |
|------|------|-----------|
| 🟢 順序変更のみ | 偽差分、実際の変更なし | 無視してOK |
| 🟡 実際の変更 | Set要素の追加/削除/変更 | 内容を確認 |
| 🔴 リソース再作成 | delete + create | ダウンタイム影響を確認 |
| ➕ 新規作成 | 新しいリソース | 意図した追加か確認 |
| ➖ 削除 | リソース削除 | 意図した削除か確認 |
| ℹ️ その他 | 非Set型属性の変更 | 通常のレビュー |

## 終了コード（`--exit-code` 使用時）

| コード | 意味 |
|--------|------|
| 0 | 変更なし、または順序変更のみ |
| 1 | Set型属性の実際の変更あり |
| 2 | リソース再作成あり |
| 3 | エラー |

## 詳細ドキュメント

- [scripts/README.md](scripts/README.md) - 全オプション、出力形式、CI/CD例
- [references/azurerm_set_attributes.md](references/azurerm_set_attributes.md) - 対象リソース・属性一覧
