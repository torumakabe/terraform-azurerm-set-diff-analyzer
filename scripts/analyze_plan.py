#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Terraform Plan Analyzer for AzureRM Set-type Attributes

Analyzes terraform plan JSON output to distinguish between:
- Order-only changes (false positives) in Set-type attributes
- Actual additions/deletions/modifications

Usage:
    terraform show -json plan.tfplan | python analyze_plan.py
    python analyze_plan.py plan.json
"""

import json
import sys
from dataclasses import dataclass, field
from typing import Any

# AzureRM resources with Set-type attributes
# Format: resource_type -> {attribute_name: key_attribute}
AZURERM_SET_ATTRIBUTES: dict[str, dict[str, str | None]] = {
    "azurerm_application_gateway": {
        "backend_address_pool": "name",
        "backend_http_settings": "name",
        "frontend_ip_configuration": "name",
        "frontend_port": "name",
        "gateway_ip_configuration": "name",
        "http_listener": "name",
        "probe": "name",
        "redirect_configuration": "name",
        "request_routing_rule": "name",
        "rewrite_rule_set": "name",
        "ssl_certificate": "name",
        "ssl_profile": "name",
        "trusted_client_certificate": "name",
        "trusted_root_certificate": "name",
        "url_path_map": "name",
    },
    "azurerm_lb": {
        "frontend_ip_configuration": "name",
    },
    "azurerm_lb_backend_address_pool": {
        "backend_address": "name",
    },
    "azurerm_firewall": {
        "ip_configuration": "name",
        "management_ip_configuration": "name",
    },
    "azurerm_firewall_policy_rule_collection_group": {
        "application_rule_collection": "name",
        "network_rule_collection": "name",
        "nat_rule_collection": "name",
    },
    "azurerm_frontdoor": {
        "backend_pool": "name",
        "backend_pool_health_probe": "name",
        "backend_pool_load_balancing": "name",
        "frontend_endpoint": "name",
        "routing_rule": "name",
    },
    "azurerm_network_security_group": {
        "security_rule": "name",
    },
    "azurerm_route_table": {
        "route": "name",
    },
    "azurerm_virtual_network": {
        "subnet": "name",
    },
    "azurerm_virtual_network_gateway": {
        "ip_configuration": "name",
    },
    "azurerm_private_endpoint": {
        "private_dns_zone_group": "name",
        "private_service_connection": "name",
    },
    "azurerm_api_management": {
        "additional_location": "location",
    },
    "azurerm_cosmosdb_account": {
        "geo_location": "location",
        "capabilities": "name",
        "virtual_network_rule": "id",
    },
}


@dataclass
class SetAttributeChange:
    """Represents a change in a Set-type attribute."""
    attribute_name: str
    order_only_count: int = 0
    added: list[str] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)
    modified: list[tuple[str, dict[str, Any]]] = field(default_factory=list)


@dataclass
class ResourceChange:
    """Represents changes to a single resource."""
    address: str
    resource_type: str
    actions: list[str]
    set_changes: list[SetAttributeChange] = field(default_factory=list)
    other_changes: list[str] = field(default_factory=list)
    is_replace: bool = False


def get_element_key(element: dict[str, Any], key_attr: str | None) -> str:
    """Extract the key value from a Set element."""
    if key_attr and key_attr in element:
        return str(element[key_attr])
    # Fall back to hash of sorted items for elements without a key attribute
    return str(hash(json.dumps(element, sort_keys=True)))


def normalize_value(val: Any) -> Any:
    """Normalize values for comparison (treat empty string and None as equivalent)."""
    if val == "" or val is None:
        return None
    if isinstance(val, list) and len(val) == 0:
        return None
    return val


def values_equivalent(before_val: Any, after_val: Any) -> bool:
    """Check if two values are effectively equivalent."""
    return normalize_value(before_val) == normalize_value(after_val)


def compare_elements(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    """Compare two elements and return the differences."""
    diffs = {}
    all_keys = set(before.keys()) | set(after.keys())
    
    for key in all_keys:
        before_val = before.get(key)
        after_val = after.get(key)
        if not values_equivalent(before_val, after_val):
            diffs[key] = {"before": before_val, "after": after_val}
    
    return diffs


def analyze_set_attribute(
    before_list: list[dict[str, Any]] | None,
    after_list: list[dict[str, Any]] | None,
    key_attr: str | None,
    attr_name: str,
) -> SetAttributeChange:
    """Analyze changes in a Set-type attribute."""
    change = SetAttributeChange(attribute_name=attr_name)
    
    before_list = before_list or []
    after_list = after_list or []
    
    # Build maps keyed by the key attribute
    before_map = {get_element_key(e, key_attr): e for e in before_list}
    after_map = {get_element_key(e, key_attr): e for e in after_list}
    
    before_keys = set(before_map.keys())
    after_keys = set(after_map.keys())
    
    # Find removed elements
    for key in before_keys - after_keys:
        display_key = key if key_attr else "(element)"
        change.removed.append(display_key)
    
    # Find added elements
    for key in after_keys - before_keys:
        display_key = key if key_attr else "(element)"
        change.added.append(display_key)
    
    # Compare common elements
    for key in before_keys & after_keys:
        before_elem = before_map[key]
        after_elem = after_map[key]
        
        if before_elem == after_elem:
            # Exact match - this is just an order change
            change.order_only_count += 1
        else:
            # Content changed - check if there are meaningful differences
            diffs = compare_elements(before_elem, after_elem)
            if diffs:
                # Has actual differences
                display_key = key if key_attr else "(element)"
                change.modified.append((display_key, diffs))
            else:
                # Only null/empty differences - treat as order change
                change.order_only_count += 1
    
    return change


def analyze_resource_change(resource_change: dict[str, Any]) -> ResourceChange | None:
    """Analyze a single resource change from terraform plan."""
    resource_type = resource_change.get("type", "")
    address = resource_change.get("address", "")
    change = resource_change.get("change", {})
    actions = change.get("actions", [])
    
    # Skip if no change or not an AzureRM resource
    if actions == ["no-op"] or not resource_type.startswith("azurerm_"):
        return None
    
    before = change.get("before") or {}
    after = change.get("after") or {}
    
    result = ResourceChange(
        address=address,
        resource_type=resource_type,
        actions=actions,
        is_replace="delete" in actions and "create" in actions,
    )
    
    # Get Set attributes for this resource type
    set_attrs = AZURERM_SET_ATTRIBUTES.get(resource_type, {})
    
    # Analyze Set-type attributes
    analyzed_attrs = set()
    for attr_name, key_attr in set_attrs.items():
        before_val = before.get(attr_name)
        after_val = after.get(attr_name)
        
        # Skip if attribute is not present or unchanged
        if before_val is None and after_val is None:
            continue
        if before_val == after_val:
            continue
            
        # Only analyze if it's a list (Set in Terraform)
        if not isinstance(before_val, list) and not isinstance(after_val, list):
            continue
        
        set_change = analyze_set_attribute(before_val, after_val, key_attr, attr_name)
        
        # Only include if there are actual findings
        if (set_change.order_only_count > 0 or 
            set_change.added or 
            set_change.removed or 
            set_change.modified):
            result.set_changes.append(set_change)
            analyzed_attrs.add(attr_name)
    
    # Find other (non-Set) changes
    all_keys = set(before.keys()) | set(after.keys())
    for key in all_keys:
        if key in analyzed_attrs:
            continue
        if key.startswith("_"):  # Skip internal attributes
            continue
        before_val = before.get(key)
        after_val = after.get(key)
        if before_val != after_val:
            result.other_changes.append(key)
    
    return result


def format_markdown_output(results: list[ResourceChange]) -> str:
    """Format analysis results as Markdown."""
    lines = ["# Terraform Plan 分析結果", ""]
    lines.append("AzureRM Set型属性の変更を分析し、順序変更のみの「偽差分」を識別します。")
    lines.append("")
    
    # Categorize changes
    order_only_changes: list[tuple[str, SetAttributeChange]] = []
    actual_set_changes: list[tuple[str, SetAttributeChange]] = []
    replace_resources: list[ResourceChange] = []
    other_changes: list[tuple[str, list[str]]] = []
    
    for result in results:
        if result.is_replace:
            replace_resources.append(result)
        
        for set_change in result.set_changes:
            has_actual_change = (
                set_change.added or 
                set_change.removed or 
                set_change.modified
            )
            
            if set_change.order_only_count > 0 and not has_actual_change:
                order_only_changes.append((result.address, set_change))
            elif has_actual_change:
                actual_set_changes.append((result.address, set_change))
        
        if result.other_changes:
            other_changes.append((result.address, result.other_changes))
    
    # Section: Order-only changes (false positives)
    lines.append("## 🟢 順序変更のみ（影響なし）")
    lines.append("")
    if order_only_changes:
        lines.append("以下の変更は、Set型属性の内部的な並び替えのみで、実際のリソース変更はありません。")
        lines.append("")
        for address, change in order_only_changes:
            lines.append(f"- `{address}`: **{change.attribute_name}** ({change.order_only_count}要素)")
    else:
        lines.append("なし")
    lines.append("")
    
    # Section: Actual Set changes
    lines.append("## 🟡 Set型属性の実際の変更")
    lines.append("")
    if actual_set_changes:
        for address, change in actual_set_changes:
            lines.append(f"### `{address}` - {change.attribute_name}")
            lines.append("")
            
            if change.added:
                lines.append("**追加:**")
                for item in change.added:
                    lines.append(f"  - {item}")
            
            if change.removed:
                lines.append("**削除:**")
                for item in change.removed:
                    lines.append(f"  - {item}")
            
            if change.modified:
                lines.append("**変更:**")
                for item_key, diffs in change.modified:
                    lines.append(f"  - {item_key}:")
                    for diff_key, diff_val in diffs.items():
                        before_str = json.dumps(diff_val["before"], ensure_ascii=False)
                        after_str = json.dumps(diff_val["after"], ensure_ascii=False)
                        lines.append(f"    - {diff_key}: {before_str} → {after_str}")
            
            if change.order_only_count > 0:
                lines.append(f"**順序変更のみ:** {change.order_only_count}要素")
            
            lines.append("")
    else:
        lines.append("なし")
    lines.append("")
    
    # Section: Resource replacements
    lines.append("## 🔴 リソース再作成（要注意）")
    lines.append("")
    if replace_resources:
        lines.append("以下のリソースは削除後に再作成されます。ダウンタイムが発生する可能性があります。")
        lines.append("")
        for result in replace_resources:
            lines.append(f"- `{result.address}`")
    else:
        lines.append("なし")
    lines.append("")
    
    # Section: Other changes
    lines.append("## ℹ️ その他の変更（非Set型属性）")
    lines.append("")
    if other_changes:
        for address, attrs in other_changes:
            lines.append(f"- `{address}`: {', '.join(attrs)}")
    else:
        lines.append("なし")
    lines.append("")
    
    return "\n".join(lines)


def main():
    """Main entry point."""
    # Read input
    if len(sys.argv) > 1:
        # Read from file
        try:
            with open(sys.argv[1], "r") as f:
                plan_json = json.load(f)
        except FileNotFoundError:
            print(f"Error: File not found: {sys.argv[1]}", file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        # Read from stdin
        try:
            plan_json = json.load(sys.stdin)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON from stdin: {e}", file=sys.stderr)
            sys.exit(1)
    
    # Extract resource_changes
    resource_changes = plan_json.get("resource_changes", [])
    
    if not resource_changes:
        print("# Terraform Plan 分析結果\n")
        print("リソース変更はありません。")
        sys.exit(0)
    
    # Analyze each resource change
    results = []
    for rc in resource_changes:
        result = analyze_resource_change(rc)
        if result:
            results.append(result)
    
    # Output Markdown
    output = format_markdown_output(results)
    print(output)


if __name__ == "__main__":
    main()
