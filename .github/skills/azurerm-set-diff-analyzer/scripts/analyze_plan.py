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
    python analyze_plan.py plan.json --attributes path/to/attributes.json
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

# Default path to the external attributes JSON file (relative to this script)
DEFAULT_ATTRIBUTES_PATH = Path(__file__).parent.parent / "references" / "azurerm_set_attributes.json"


def load_set_attributes(path: Optional[Path] = None) -> Dict[str, Dict[str, Optional[str]]]:
    """Load Set-type attributes from external JSON file."""
    attributes_path = path or DEFAULT_ATTRIBUTES_PATH

    try:
        with open(attributes_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data.get("resources", {})
    except FileNotFoundError:
        print(f"Warning: Attributes file not found: {attributes_path}", file=sys.stderr)
        print("Using empty attributes. No Set-type analysis will be performed.", file=sys.stderr)
        return {}
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in attributes file: {e}", file=sys.stderr)
        sys.exit(1)


# Global variable to hold loaded attributes (initialized in main)
AZURERM_SET_ATTRIBUTES: Dict[str, Any] = {}


def get_attr_config(attr_def: Any) -> tuple:
    """
    Parse attribute definition and return (key_attr, nested_attrs).

    Attribute definition can be:
    - str: simple key attribute (e.g., "name")
    - None/null: no key attribute
    - dict: nested structure with "_key" and nested attributes
    """
    if attr_def is None:
        return (None, {})
    if isinstance(attr_def, str):
        return (attr_def, {})
    if isinstance(attr_def, dict):
        key_attr = attr_def.get("_key")
        nested_attrs = {k: v for k, v in attr_def.items() if k != "_key"}
        return (key_attr, nested_attrs)
    return (None, {})


@dataclass
class SetAttributeChange:
    """Represents a change in a Set-type attribute."""
    attribute_name: str
    path: str = ""  # Full path for nested attributes (e.g., "rewrite_rule_set.rewrite_rule")
    order_only_count: int = 0
    added: "List[str]" = field(default_factory=list)
    removed: "List[str]" = field(default_factory=list)
    modified: "List[tuple]" = field(default_factory=list)
    nested_changes: "List[SetAttributeChange]" = field(default_factory=list)


@dataclass
class ResourceChange:
    """Represents changes to a single resource."""
    address: str
    resource_type: str
    actions: "List[str]" = field(default_factory=list)
    set_changes: "List[SetAttributeChange]" = field(default_factory=list)
    other_changes: "List[str]" = field(default_factory=list)
    is_replace: bool = False


def get_element_key(element: Dict[str, Any], key_attr: Optional[str]) -> str:
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


def compare_elements(
    before: Dict[str, Any],
    after: Dict[str, Any],
    nested_attrs: Dict[str, Any] = None
) -> tuple:
    """
    Compare two elements and return (simple_diffs, nested_set_attrs).

    simple_diffs: differences in non-Set attributes
    nested_set_attrs: list of (attr_name, before_val, after_val, attr_def) for nested Sets
    """
    nested_attrs = nested_attrs or {}
    simple_diffs = {}
    nested_set_attrs = []

    all_keys = set(before.keys()) | set(after.keys())

    for key in all_keys:
        before_val = before.get(key)
        after_val = after.get(key)

        # Check if this is a nested Set attribute
        if key in nested_attrs:
            if before_val != after_val:
                nested_set_attrs.append((key, before_val, after_val, nested_attrs[key]))
        elif not values_equivalent(before_val, after_val):
            simple_diffs[key] = {"before": before_val, "after": after_val}

    return (simple_diffs, nested_set_attrs)


def analyze_set_attribute(
    before_list: Optional[List[Dict[str, Any]]],
    after_list: Optional[List[Dict[str, Any]]],
    key_attr: Optional[str],
    attr_name: str,
    nested_attrs: Dict[str, Any] = None,
    path: str = "",
) -> SetAttributeChange:
    """Analyze changes in a Set-type attribute, including nested Sets."""
    full_path = f"{path}.{attr_name}" if path else attr_name
    change = SetAttributeChange(attribute_name=attr_name, path=full_path)
    nested_attrs = nested_attrs or {}

    before_list = before_list or []
    after_list = after_list or []

    # Handle non-list values (single element)
    if not isinstance(before_list, list):
        before_list = [before_list] if before_list else []
    if not isinstance(after_list, list):
        after_list = [after_list] if after_list else []

    # Build maps keyed by the key attribute
    before_map = {get_element_key(e, key_attr): e for e in before_list if isinstance(e, dict)}
    after_map = {get_element_key(e, key_attr): e for e in after_list if isinstance(e, dict)}

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
            # Content changed - check for meaningful differences
            simple_diffs, nested_set_list = compare_elements(before_elem, after_elem, nested_attrs)

            # Process nested Set attributes recursively
            for nested_name, nested_before, nested_after, nested_def in nested_set_list:
                nested_key, sub_nested = get_attr_config(nested_def)
                nested_change = analyze_set_attribute(
                    nested_before, nested_after, nested_key, nested_name,
                    sub_nested, full_path
                )
                if (nested_change.order_only_count > 0 or
                    nested_change.added or
                    nested_change.removed or
                    nested_change.modified or
                    nested_change.nested_changes):
                    change.nested_changes.append(nested_change)

            if simple_diffs:
                # Has actual differences in non-nested attributes
                display_key = key if key_attr else "(element)"
                change.modified.append((display_key, simple_diffs))
            elif not nested_set_list:
                # Only null/empty differences - treat as order change
                change.order_only_count += 1

    return change


def analyze_resource_change(resource_change: Dict[str, Any]) -> Optional[ResourceChange]:
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
    for attr_name, attr_def in set_attrs.items():
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

        # Parse attribute definition for key and nested attrs
        key_attr, nested_attrs = get_attr_config(attr_def)

        set_change = analyze_set_attribute(
            before_val, after_val, key_attr, attr_name, nested_attrs
        )

        # Only include if there are actual findings
        if (set_change.order_only_count > 0 or
            set_change.added or
            set_change.removed or
            set_change.modified or
            set_change.nested_changes):
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


def collect_all_changes(set_change: SetAttributeChange, prefix: str = "") -> tuple:
    """
    Recursively collect order-only and actual changes from nested structure.
    Returns (order_only_list, actual_change_list)
    """
    order_only = []
    actual = []

    display_name = f"{prefix}{set_change.attribute_name}" if prefix else set_change.attribute_name

    has_actual_change = (
        set_change.added or
        set_change.removed or
        set_change.modified
    )

    if set_change.order_only_count > 0 and not has_actual_change:
        order_only.append((display_name, set_change))
    elif has_actual_change:
        actual.append((display_name, set_change))

    # Process nested changes
    for nested in set_change.nested_changes:
        nested_order, nested_actual = collect_all_changes(nested, f"{display_name}.")
        order_only.extend(nested_order)
        actual.extend(nested_actual)

    return (order_only, actual)


def format_set_change(change: SetAttributeChange, indent: int = 0) -> List[str]:
    """Format a single SetAttributeChange for output."""
    lines = []
    prefix = "  " * indent

    if change.added:
        lines.append(f"{prefix}**追加:**")
        for item in change.added:
            lines.append(f"{prefix}  - {item}")

    if change.removed:
        lines.append(f"{prefix}**削除:**")
        for item in change.removed:
            lines.append(f"{prefix}  - {item}")

    if change.modified:
        lines.append(f"{prefix}**変更:**")
        for item_key, diffs in change.modified:
            lines.append(f"{prefix}  - {item_key}:")
            for diff_key, diff_val in diffs.items():
                before_str = json.dumps(diff_val["before"], ensure_ascii=False)
                after_str = json.dumps(diff_val["after"], ensure_ascii=False)
                lines.append(f"{prefix}    - {diff_key}: {before_str} → {after_str}")

    if change.order_only_count > 0:
        lines.append(f"{prefix}**順序変更のみ:** {change.order_only_count}要素")

    # Format nested changes
    for nested in change.nested_changes:
        if nested.added or nested.removed or nested.modified or nested.nested_changes:
            lines.append(f"{prefix}**ネスト属性 `{nested.attribute_name}`:**")
            lines.extend(format_set_change(nested, indent + 1))

    return lines


def format_markdown_output(results: List[ResourceChange]) -> str:
    """Format analysis results as Markdown."""
    lines = ["# Terraform Plan 分析結果", ""]
    lines.append("AzureRM Set型属性の変更を分析し、順序変更のみの「偽差分」を識別します。")
    lines.append("")

    # Categorize changes (including nested)
    order_only_changes: List[tuple] = []
    actual_set_changes: List[tuple] = []
    replace_resources: List[ResourceChange] = []
    other_changes: List[tuple] = []

    for result in results:
        if result.is_replace:
            replace_resources.append(result)

        for set_change in result.set_changes:
            order_only, actual = collect_all_changes(set_change)
            for name, change in order_only:
                order_only_changes.append((result.address, name, change))
            for name, change in actual:
                actual_set_changes.append((result.address, name, change))

        if result.other_changes:
            other_changes.append((result.address, result.other_changes))

    # Section: Order-only changes (false positives)
    lines.append("## 🟢 順序変更のみ（影響なし）")
    lines.append("")
    if order_only_changes:
        lines.append("以下の変更は、Set型属性の内部的な並び替えのみで、実際のリソース変更はありません。")
        lines.append("")
        for address, name, change in order_only_changes:
            lines.append(f"- `{address}`: **{name}** ({change.order_only_count}要素)")
    else:
        lines.append("なし")
    lines.append("")

    # Section: Actual Set changes
    lines.append("## 🟡 Set型属性の実際の変更")
    lines.append("")
    if actual_set_changes:
        for address, name, change in actual_set_changes:
            lines.append(f"### `{address}` - {name}")
            lines.append("")
            lines.extend(format_set_change(change))
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
    global AZURERM_SET_ATTRIBUTES

    # Parse arguments
    plan_file = None
    attributes_file = None

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--attributes" and i + 1 < len(args):
            attributes_file = Path(args[i + 1])
            i += 2
        elif not args[i].startswith("-"):
            plan_file = args[i]
            i += 1
        else:
            i += 1

    # Load Set attributes from external JSON
    AZURERM_SET_ATTRIBUTES = load_set_attributes(attributes_file)

    # Read plan input
    if plan_file:
        # Read from file
        try:
            with open(plan_file, "r") as f:
                plan_json = json.load(f)
        except FileNotFoundError:
            print(f"Error: File not found: {plan_file}", file=sys.stderr)
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
