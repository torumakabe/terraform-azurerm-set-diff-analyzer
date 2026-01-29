# AzureRM Set Diff Analyzer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A GitHub Copilot CLI Skill that analyzes Terraform plan JSON output for AzureRM Provider to distinguish between false-positive diffs (order-only changes in Set-type attributes) and actual resource changes.

## The Problem

When working with Azure resources that use Set-type attributes (like Application Gateway, Load Balancer, NSG, etc.), `terraform plan` often shows all elements as "changed" even when you only added or removed a single element. This is because Terraform's Set type compares by position rather than by key.

These "false-positive diffs" don't actually affect the resources, but they make reviewing terraform plan output difficult and can cause confusion in CI/CD pipelines.

## The Solution

This analyzer identifies and categorizes changes in Set-type attributes:

| Category | Meaning | Action |
|----------|---------|--------|
| 🟢 Order-only | False-positive diff, no actual change | Safe to ignore |
| 🟡 Actual change | Set element added/removed/modified | Review the content |
| 🔴 Resource replacement | delete + create | Check for downtime impact |

## Installation

### As a Copilot CLI Skill

Copy the skill folder to your repository:

```bash
cp -r .github/skills/azurerm-set-diff-analyzer <your-repo>/.github/skills/
```

### As a Standalone Tool

```bash
# Clone this repository
git clone https://github.com/torumakabe/terraform-azurerm-set-diff-analyzer.git

# Run the analyzer
python3 .github/skills/azurerm-set-diff-analyzer/scripts/analyze_plan.py plan.json
```

## Quick Start

```bash
# 1. Generate plan JSON output
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json

# 2. Analyze
python3 .github/skills/azurerm-set-diff-analyzer/scripts/analyze_plan.py plan.json
```

## Documentation

- **[SKILL.md](.github/skills/azurerm-set-diff-analyzer/SKILL.md)** - Copilot CLI Skill overview
- **[scripts/README.md](.github/skills/azurerm-set-diff-analyzer/scripts/README.md)** - Full options, output formats, exit codes, CI/CD examples
- **[references/azurerm_set_attributes.md](.github/skills/azurerm-set-diff-analyzer/references/azurerm_set_attributes.md)** - Supported resources and attributes

## Supported Resources

Key AzureRM resources with Set-type attributes:

- `azurerm_application_gateway` - Backend pools, listeners, rules, etc.
- `azurerm_firewall_policy_rule_collection_group` - Rule collections
- `azurerm_frontdoor` - Backend pools, routing
- `azurerm_network_security_group` - Security rules
- `azurerm_virtual_network_gateway` - IP configuration, VPN client configuration
- And more... (see [azurerm_set_attributes.json](.github/skills/azurerm-set-diff-analyzer/references/azurerm_set_attributes.json))

## Testing

This repository includes comprehensive tests:

```bash
# Run unit tests
python3 tests/test_analyze_plan.py

# Run integration test helper function tests (no Azure required)
cd tests/integration && ./test_helper_functions.sh

# Run full integration tests (requires Azure subscription)
cd tests/integration && ./run_integration_test.sh
```

See [tests/integration/README.md](tests/integration/README.md) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
