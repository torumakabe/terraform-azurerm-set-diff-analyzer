# Integration Test for AzureRM Set Diff Analyzer

This directory contains Terraform configurations to test the analyzer with real Azure resources.

## Prerequisites

- Azure subscription
- Azure CLI logged in (`az login`)
- Terraform >= 1.14.0

## Resources Created

| Resource | Type | Cost | Set-type Attributes Tested |
|----------|------|------|---------------------------|
| Virtual Network | azurerm_virtual_network | Free | (none - subnets use standalone resources) |
| Subnets | azurerm_subnet | Free | (standalone resources avoid Set issues) |
| NSG | azurerm_network_security_group | Free | security_rule |
| Application Gateway | azurerm_application_gateway | **~$200/month** | backend_address_pool, frontend_port, http_listener, request_routing_rule, backend_http_settings |

> **Note:** Subnets are defined as standalone `azurerm_subnet` resources instead of inline blocks.
> Per [AzureRM provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet),
> mixing inline and standalone subnet definitions causes conflicts.

## Usage

### Step 1: Deploy Initial Resources

```bash
cd tests/integration

# Initialize
terraform init

# Deploy (requires ARM_SUBSCRIPTION_ID environment variable)
ARM_SUBSCRIPTION_ID=<your-subscription-id> terraform apply
```

### Step 2: Make a Change to Trigger Ordering Diff

Edit `main.tf` and add/reorder Set-type attribute blocks. For example:
- Add a new `security_rule` to the NSG
- Add a new `backend_address_pool` to the Application Gateway

### Step 3: Generate Plan and Analyze

```bash
# Generate plan
ARM_SUBSCRIPTION_ID=<your-subscription-id> terraform plan -out=plan.tfplan

# Export as JSON
terraform show -json plan.tfplan > plan.json

# Analyze with our tool
python3 ../../.github/skills/azurerm-set-diff-analyzer/scripts/analyze_plan.py plan.json
```

### Step 4: Clean Up

```bash
ARM_SUBSCRIPTION_ID=<your-subscription-id> terraform destroy
```

## Expected Results

When you add/reorder Set-type attribute blocks:
- `terraform plan` may show changes to existing elements (false positives)
- Our analyzer will classify these as "🟢 順序変更のみ（影響なし）"

## Cost Warning

⚠️ **Application Gateway incurs significant costs (~$200/month)**

If you only want to test with free resources, comment out the Application Gateway section in `main.tf`:
- `azurerm_subnet.appgw`
- `azurerm_public_ip.appgw`
- `azurerm_application_gateway.test`
