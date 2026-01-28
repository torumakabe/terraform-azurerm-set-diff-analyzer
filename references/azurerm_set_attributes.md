# AzureRM Provider Set型属性リファレンス

このドキュメントは、AzureRM ProviderでSet型として扱われる属性の一覧です。
これらの属性は順序が保証されず、要素の追加・削除時に「偽の差分」が発生する可能性があります。

## 属性定義

各リソースのSet型属性と、要素を識別するためのキー属性を定義しています。

| リソースタイプ | Set属性 | キー属性 |
|---------------|---------|---------|
| azurerm_application_gateway | backend_address_pool | name |
| azurerm_application_gateway | backend_http_settings | name |
| azurerm_application_gateway | frontend_ip_configuration | name |
| azurerm_application_gateway | frontend_port | name |
| azurerm_application_gateway | gateway_ip_configuration | name |
| azurerm_application_gateway | http_listener | name |
| azurerm_application_gateway | probe | name |
| azurerm_application_gateway | redirect_configuration | name |
| azurerm_application_gateway | request_routing_rule | name |
| azurerm_application_gateway | rewrite_rule_set | name |
| azurerm_application_gateway | ssl_certificate | name |
| azurerm_application_gateway | ssl_profile | name |
| azurerm_application_gateway | trusted_client_certificate | name |
| azurerm_application_gateway | trusted_root_certificate | name |
| azurerm_application_gateway | url_path_map | name |
| azurerm_lb | frontend_ip_configuration | name |
| azurerm_lb_backend_address_pool | backend_address | name |
| azurerm_lb_rule | backend_address_pool_ids | - |
| azurerm_firewall | ip_configuration | name |
| azurerm_firewall | management_ip_configuration | name |
| azurerm_firewall | virtual_hub | - |
| azurerm_firewall_policy_rule_collection_group | application_rule_collection | name |
| azurerm_firewall_policy_rule_collection_group | network_rule_collection | name |
| azurerm_firewall_policy_rule_collection_group | nat_rule_collection | name |
| azurerm_frontdoor | backend_pool | name |
| azurerm_frontdoor | backend_pool_health_probe | name |
| azurerm_frontdoor | backend_pool_load_balancing | name |
| azurerm_frontdoor | frontend_endpoint | name |
| azurerm_frontdoor | routing_rule | name |
| azurerm_cdn_frontdoor_origin_group | health_probe | - |
| azurerm_cdn_frontdoor_origin_group | load_balancing | - |
| azurerm_network_security_group | security_rule | name |
| azurerm_route_table | route | name |
| azurerm_virtual_network | subnet | name |
| azurerm_virtual_network_gateway | ip_configuration | name |
| azurerm_virtual_network_gateway | vpn_client_configuration | - |
| azurerm_virtual_network_gateway_connection | ipsec_policy | - |
| azurerm_nat_gateway | public_ip_address_ids | - |
| azurerm_nat_gateway | public_ip_prefix_ids | - |
| azurerm_private_endpoint | private_dns_zone_group | name |
| azurerm_private_endpoint | private_service_connection | name |
| azurerm_api_management | additional_location | location |
| azurerm_api_management | certificate | encoded_certificate |
| azurerm_api_management | hostname_configuration | - |
| azurerm_storage_account | network_rules | - |
| azurerm_storage_account | blob_properties | - |
| azurerm_key_vault | network_acls | - |
| azurerm_cosmosdb_account | geo_location | location |
| azurerm_cosmosdb_account | capabilities | name |
| azurerm_cosmosdb_account | virtual_network_rule | id |
| azurerm_kubernetes_cluster | default_node_pool | - |
| azurerm_kubernetes_cluster_node_pool | node_labels | - |
| azurerm_kubernetes_cluster_node_pool | node_taints | - |

## ネストしたSet属性

一部の属性は、さらにネストしたSet型属性を持ちます。

### azurerm_application_gateway

```
url_path_map
└── path_rule (Set, key: name)
    └── paths (Set, key: -)

rewrite_rule_set
└── rewrite_rule (Set, key: name)
    ├── condition (Set, key: variable)
    └── request_header_configuration (Set, key: header_name)
    └── response_header_configuration (Set, key: header_name)
```

### azurerm_firewall_policy_rule_collection_group

```
application_rule_collection
└── rule (Set, key: name)
    ├── protocols (Set, key: -)
    └── destination_fqdns (Set, key: -)

network_rule_collection
└── rule (Set, key: name)
    ├── destination_addresses (Set, key: -)
    └── destination_ports (Set, key: -)
```

## 注意事項

- キー属性が `-` の場合、要素全体の内容で比較する必要があります
- 一部の属性はProvider/APIバージョンによって動作が異なる場合があります
- このリストは主要なリソースを対象としており、網羅的ではありません
