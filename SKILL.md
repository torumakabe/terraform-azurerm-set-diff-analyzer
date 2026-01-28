---
name: azurerm-set-diff-analyzer
description: Analyze Terraform plan JSON output for AzureRM Provider to distinguish between false-positive diffs (order-only changes in Set-type attributes) and actual resource changes. Use when reviewing terraform plan output for Azure resources like Application Gateway, Load Balancer, Firewall, Front Door, NSG, and other resources with Set-type attributes that cause spurious diffs due to internal ordering changes.
license: Complete terms in LICENSE
---

# AzureRM Set Diff Analyzer

AzureRM ProviderのSet型属性による「偽差分」を識別し、実際の変更と区別するためのスキルです。

## 背景

Azure Application Gateway、Load Balancer、Firewall等のリソースには、内部的にSet型で管理される属性があります。
これらの属性は順序が保証されないため、要素の追加・削除時に全要素が「変更」として表示される問題があります。

この「偽差分」は実際にはリソースに影響を与えませんが、terraform planの出力を確認する際に混乱を招きます。

## 使用方法

### 1. Terraform planのJSON出力を生成

```bash
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
```

### 2. 分析スクリプトを実行

```bash
# ファイルから読み込み
python scripts/analyze_plan.py plan.json

# または標準入力から読み込み
terraform show -json plan.tfplan | python scripts/analyze_plan.py
```

### 3. 出力を確認

スクリプトはMarkdown形式で以下のセクションを出力します：

- **🟢 順序変更のみ（影響なし）** - Set型属性の並び替えのみで、実際の変更なし
- **🟡 Set型属性の実際の変更** - 要素の追加・削除・変更
- **🔴 リソース再作成（要注意）** - delete + createアクションのリソース
- **ℹ️ その他の変更** - 非Set型属性の変更

## 出力例

```markdown
# Terraform Plan 分析結果

## 🟢 順序変更のみ（影響なし）

以下の変更は、Set型属性の内部的な並び替えのみで、実際のリソース変更はありません。

- `azurerm_application_gateway.main`: **backend_address_pool** (5要素)
- `azurerm_application_gateway.main`: **http_listener** (3要素)

## 🟡 Set型属性の実際の変更

### `azurerm_application_gateway.main` - request_routing_rule

**追加:**
  - new-rule

**順序変更のみ:** 2要素

## 🔴 リソース再作成（要注意）

なし

## ℹ️ その他の変更（非Set型属性）

- `azurerm_application_gateway.main`: sku, tags
```

## 対象リソース

分析対象のAzureRMリソースとSet型属性の一覧は [references/azurerm_set_attributes.md](references/azurerm_set_attributes.md) を参照してください。

主要な対象リソース：
- `azurerm_application_gateway` - backend_address_pool, http_listener, request_routing_rule など
- `azurerm_lb` - frontend_ip_configuration
- `azurerm_firewall` - ip_configuration
- `azurerm_frontdoor` - backend_pool, routing_rule など
- `azurerm_network_security_group` - security_rule
- その他多数

## 判断の解釈

| 分類 | 意味 | 推奨アクション |
|------|------|---------------|
| 🟢 順序変更のみ | 偽差分、実際の変更なし | 無視してOK |
| 🟡 実際の変更 | Set要素の追加/削除/変更 | 内容を確認、通常はin-place更新 |
| 🔴 リソース再作成 | リソース全体の再作成 | ダウンタイム影響を確認 |
| ℹ️ その他 | 非Set型属性の変更 | 通常のレビュー |

## 制限事項

- AzureRMリソースのみが対象です
- 一部のリソース/属性は未対応の場合があります
- ネストしたSet属性の一部は簡略化して表示されます
