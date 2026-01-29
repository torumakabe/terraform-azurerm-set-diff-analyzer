#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Unit tests for AzureRM Set Diff Analyzer

Run with: python -m pytest tests/test_analyze_plan.py -v
Or simply: python tests/test_analyze_plan.py
"""

import json
import sys
from pathlib import Path

# Add scripts directory to path
SCRIPTS_DIR = Path(__file__).parent.parent / ".github" / "skills" / "terraform-azurerm-set-diff-analyzer" / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import analyze_plan as ap
from analyze_plan import (
    analyze_plan,
    normalize_value,
    normalize_for_comparison,
    values_equivalent,
    get_element_key,
    analyze_primitive_set,
    analyze_set_attribute,
    get_attr_config,
    determine_exit_code,
    load_set_attributes,
    CONFIG,
    EXIT_NO_CHANGES,
    EXIT_SET_CHANGES,
    EXIT_RESOURCE_REPLACE,
)

# Test data directory
TESTS_DIR = Path(__file__).parent


def setup_module():
    """Setup for all tests - load attributes."""
    ap.AZURERM_SET_ATTRIBUTES = load_set_attributes()
    CONFIG.ignore_case = False
    CONFIG.quiet = False
    CONFIG.verbose = False
    CONFIG.warnings = []


def load_test_plan(filename: str) -> dict:
    """Load a test plan JSON file."""
    with open(TESTS_DIR / filename, "r") as f:
        return json.load(f)


class TestNormalizeValue:
    """Tests for normalize_value function."""
    
    def test_none_returns_none(self):
        assert normalize_value(None) is None
    
    def test_empty_string_returns_none(self):
        assert normalize_value("") is None
    
    def test_empty_list_returns_none(self):
        assert normalize_value([]) is None
    
    def test_non_empty_string_unchanged(self):
        assert normalize_value("test") == "test"
    
    def test_non_empty_list_unchanged(self):
        assert normalize_value([1, 2, 3]) == [1, 2, 3]
    
    def test_float_integer_normalized(self):
        assert normalize_value(443.0) == 443
    
    def test_float_non_integer_unchanged(self):
        assert normalize_value(443.5) == 443.5


class TestValuesEquivalent:
    """Tests for values_equivalent function."""
    
    def test_none_and_empty_string_equivalent(self):
        assert values_equivalent(None, "") is True
    
    def test_none_and_empty_list_equivalent(self):
        assert values_equivalent(None, []) is True
    
    def test_same_values_equivalent(self):
        assert values_equivalent("test", "test") is True
    
    def test_different_values_not_equivalent(self):
        assert values_equivalent("test", "other") is False
    
    def test_integer_and_float_equivalent(self):
        assert values_equivalent(443, 443.0) is True


class TestGetAttrConfig:
    """Tests for get_attr_config function."""
    
    def test_string_returns_key_attr(self):
        key_attr, nested = get_attr_config("name")
        assert key_attr == "name"
        assert nested == {}
    
    def test_none_returns_none_key(self):
        key_attr, nested = get_attr_config(None)
        assert key_attr is None
        assert nested == {}
    
    def test_dict_with_key_returns_key_and_nested(self):
        attr_def = {
            "_key": "name",
            "rule": {"_key": "rule_name"}
        }
        key_attr, nested = get_attr_config(attr_def)
        assert key_attr == "name"
        assert "rule" in nested


class TestAnalyzePrimitiveSet:
    """Tests for analyze_primitive_set function."""
    
    def test_added_elements(self):
        before = ["a", "b"]
        after = ["a", "b", "c"]
        change = analyze_primitive_set(before, after, "test_attr")
        assert "c" in change.primitive_added
        assert len(change.primitive_removed) == 0
    
    def test_removed_elements(self):
        before = ["a", "b", "c"]
        after = ["a", "b"]
        change = analyze_primitive_set(before, after, "test_attr")
        assert "c" in change.primitive_removed
        assert len(change.primitive_added) == 0
    
    def test_order_only_change(self):
        before = ["a", "b", "c"]
        after = ["c", "b", "a"]
        change = analyze_primitive_set(before, after, "test_attr")
        assert change.order_only_count == 3
        assert len(change.primitive_added) == 0
        assert len(change.primitive_removed) == 0


class TestAnalyzeSetAttribute:
    """Tests for analyze_set_attribute function."""
    
    def test_order_only_changes(self):
        before = [
            {"name": "pool-a", "fqdns": ["a.com"]},
            {"name": "pool-b", "fqdns": ["b.com"]},
        ]
        after = [
            {"name": "pool-b", "fqdns": ["b.com"]},
            {"name": "pool-a", "fqdns": ["a.com"]},
        ]
        change = analyze_set_attribute(before, after, "name", "backend_pool")
        assert change.order_only_count == 2
        assert len(change.added) == 0
        assert len(change.removed) == 0
    
    def test_added_element(self):
        before = [{"name": "pool-a"}]
        after = [{"name": "pool-a"}, {"name": "pool-b"}]
        change = analyze_set_attribute(before, after, "name", "backend_pool")
        assert "pool-b" in change.added
    
    def test_removed_element(self):
        before = [{"name": "pool-a"}, {"name": "pool-b"}]
        after = [{"name": "pool-a"}]
        change = analyze_set_attribute(before, after, "name", "backend_pool")
        assert "pool-b" in change.removed
    
    def test_modified_element(self):
        before = [{"name": "pool-a", "port": 80}]
        after = [{"name": "pool-a", "port": 443}]
        change = analyze_set_attribute(before, after, "name", "backend_pool")
        assert len(change.modified) == 1
        assert change.modified[0][0] == "pool-a"


class TestAnalyzePlan:
    """Integration tests for analyze_plan function."""
    
    def test_order_only_change(self):
        plan = load_test_plan("order_only_change.json")
        result = analyze_plan(plan)
        assert result.order_only_count > 0
        assert result.actual_set_changes_count == 0
        assert result.replace_count == 0
    
    def test_mixed_changes(self):
        plan = load_test_plan("mixed_changes.json")
        result = analyze_plan(plan)
        assert result.order_only_count > 0
        assert result.actual_set_changes_count > 0
    
    def test_nested_changes(self):
        plan = load_test_plan("nested_changes.json")
        result = analyze_plan(plan)
        # Should detect nested Set changes
        assert result.order_only_count > 0 or result.actual_set_changes_count > 0
    
    def test_primitive_set(self):
        plan = load_test_plan("primitive_set.json")
        result = analyze_plan(plan)
        assert result.actual_set_changes_count > 0
    
    def test_case_sensitivity(self):
        plan = load_test_plan("case_sensitivity.json")
        
        # Without ignore_case
        CONFIG.ignore_case = False
        result = analyze_plan(plan)
        assert result.actual_set_changes_count > 0
        
        # With ignore_case
        CONFIG.ignore_case = True
        result = analyze_plan(plan)
        assert result.order_only_count > 0
        assert result.actual_set_changes_count == 0
        
        # Reset
        CONFIG.ignore_case = False


class TestDetermineExitCode:
    """Tests for determine_exit_code function."""
    
    def test_no_changes_returns_zero(self):
        plan = load_test_plan("order_only_change.json")
        result = analyze_plan(plan)
        assert determine_exit_code(result) == EXIT_NO_CHANGES
    
    def test_actual_changes_returns_one(self):
        plan = load_test_plan("mixed_changes.json")
        result = analyze_plan(plan)
        assert determine_exit_code(result) == EXIT_SET_CHANGES


class TestFiltering:
    """Tests for include/exclude filtering."""
    
    def test_include_filter(self):
        plan = load_test_plan("mixed_changes.json")
        result = analyze_plan(plan, include_filter=["application_gateway"])
        # Should only have application_gateway resources
        for res in result.resources:
            assert "application_gateway" in res.resource_type
    
    def test_exclude_filter(self):
        plan = load_test_plan("mixed_changes.json")
        result = analyze_plan(plan, exclude_filter=["network_security_group"])
        # Should not have NSG resources
        for res in result.resources:
            assert "network_security_group" not in res.resource_type


def run_tests():
    """Run all tests and report results."""
    import traceback
    
    # Setup - load attributes
    setup_module()
    
    test_classes = [
        TestNormalizeValue,
        TestValuesEquivalent,
        TestGetAttrConfig,
        TestAnalyzePrimitiveSet,
        TestAnalyzeSetAttribute,
        TestAnalyzePlan,
        TestDetermineExitCode,
        TestFiltering,
    ]
    
    total = 0
    passed = 0
    failed = 0
    errors = []
    
    for test_class in test_classes:
        print(f"\n{test_class.__name__}:")
        instance = test_class()
        
        for method_name in dir(instance):
            if method_name.startswith("test_"):
                total += 1
                # Reset config before each test
                CONFIG.ignore_case = False
                CONFIG.warnings = []
                try:
                    getattr(instance, method_name)()
                    print(f"  ✓ {method_name}")
                    passed += 1
                except AssertionError as e:
                    print(f"  ✗ {method_name}: {e}")
                    failed += 1
                    errors.append((f"{test_class.__name__}.{method_name}", str(e)))
                except Exception as e:
                    print(f"  ✗ {method_name}: {type(e).__name__}: {e}")
                    failed += 1
                    errors.append((f"{test_class.__name__}.{method_name}", traceback.format_exc()))
    
    print(f"\n{'='*50}")
    print(f"Results: {passed}/{total} passed, {failed} failed")
    
    if errors:
        print(f"\nFailed tests:")
        for name, error in errors:
            print(f"  - {name}")
    
    return failed == 0


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
