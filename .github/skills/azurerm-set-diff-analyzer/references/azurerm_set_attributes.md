# AzureRM Set型属性リファレンス

このドキュメントは、`azurerm_set_attributes.json` の概要とメンテナンス方法を説明します。

> **最終更新**: 2026年1月28日

## 概要

`azurerm_set_attributes.json` は、AzureRM ProviderでSet型として扱われる属性の定義ファイルです。
`analyze_plan.py` スクリプトがこのJSONを読み込み、Terraform planの「偽差分」を識別します。

### Set型属性とは

Terraform の Set 型は**順序が保証されない**コレクションです。
そのため、要素の追加・削除時に、変更のない要素も「変更」として表示されることがあります。
これが「偽差分（false positive diff）」です。

## JSONファイルの構造

### 基本形式

```json
{
  "resources": {
    "azurerm_resource_type": {
      "属性名": "キー属性"
    }
  }
}
```

- **キー属性**: Set要素を一意に識別する属性（例: `name`, `id`）
- **null**: キー属性がない場合（要素全体で比較）

### ネスト形式

Set属性の中にさらにSet属性がある場合：

```json
{
  "rewrite_rule_set": {
    "_key": "name",
    "rewrite_rule": {
      "_key": "name",
      "condition": "variable",
      "request_header_configuration": "header_name"
    }
  }
}
```

- **`_key`**: その階層のSet要素のキー属性
- **その他のキー**: ネストしたSet属性の定義

### 例: azurerm_application_gateway

```json
"azurerm_application_gateway": {
  "backend_address_pool": "name",           // 単純なSet（keyはname）
  "rewrite_rule_set": {                     // ネストしたSet
    "_key": "name",
    "rewrite_rule": {
      "_key": "name",
      "condition": "variable"
    }
  }
}
```

## メンテナンス方法

### 新しい属性を追加する

1. **公式ドキュメントで確認**
   - [Terraform Registry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) でリソースを検索
   - 属性が「Set of ...」と記載されているか確認
   - `azurerm_application_gateway` のように Note に Set 属性が明記されている場合もある

2. **ソースコードで確認（より確実）**
   - [AzureRM Provider GitHub](https://github.com/hashicorp/terraform-provider-azurerm) でリソースを検索
   - スキーマ定義で `Type: pluginsdk.TypeSet` を確認
   - `Set` の `Schema` 内の属性で `_key` となりうる属性を特定

3. **JSONに追加**
   ```json
   "azurerm_new_resource": {
     "set_attribute": "key_attribute"
   }
   ```

4. **テスト**
   ```bash
   # 実際のplanで動作確認
   python3 scripts/analyze_plan.py your_plan.json
   ```

### キー属性の特定方法

| 一般的なキー属性 | 用途 |
|----------------|------|
| `name` | 名前付きブロック（最も一般的） |
| `id` | リソースID参照 |
| `location` | 地理的ロケーション |
| `address` | ネットワークアドレス |
| `host_name` | ホスト名 |
| `null` | キーがない場合（要素全体で比較） |

## 関連ツール

### analyze_plan.py

Terraform plan JSON を分析し、偽差分を識別します。

```bash
# 基本的な使い方
terraform show -json plan.tfplan | python3 scripts/analyze_plan.py

# ファイルから読み込み
python3 scripts/analyze_plan.py plan.json

# カスタム属性ファイルを使用
python3 scripts/analyze_plan.py plan.json --attributes /path/to/custom.json
```

## 対応リソース一覧

現在対応しているリソースは `azurerm_set_attributes.json` を直接参照してください：

```bash
# リソース一覧を表示
jq '.resources | keys' azurerm_set_attributes.json
```

主要なリソース：
- `azurerm_application_gateway` - バックエンドプール、リスナー、ルールなど
- `azurerm_firewall_policy_rule_collection_group` - ルールコレクション
- `azurerm_frontdoor` - バックエンドプール、ルーティング
- `azurerm_network_security_group` - セキュリティルール
- `azurerm_virtual_network_gateway` - IP構成、VPNクライアント構成

## 注意事項

- Provider/APIバージョンによって属性の動作が異なる場合があります
- 新しいリソースや属性は随時追加が必要です
- ネスト構造が深い場合、すべての階層を定義することで精度が向上します
