# Integration Test for AzureRM Set Diff Analyzer

This directory contains Terraform configurations to test the analyzer with real Azure resources.

## Prerequisites

- Azure subscription
- Azure CLI logged in (`az login`)
- Terraform >= 1.14.0

## Resources Created

| Resource | Type | Cost | Set-type Attributes Tested |
|----------|------|------|---------------------------|
| Virtual Network | azurerm_virtual_network | Free | subnet |
| NSG | azurerm_network_security_group | Free | security_rule |
| Application Gateway | azurerm_application_gateway | **~$200/month** | backend_address_pool, frontend_port, http_listener, request_routing_rule, backend_http_settings |

## Usage

### Step 1: Deploy Initial Resources

```bash
cd tests/integration

# Initialize
terraform init

# Deploy
terraform apply
```

### Step 2: Make a Change to Trigger Ordering Diff

Edit `main.tf` and reorder any Set-type attribute blocks. For example, swap the order of `subnet` blocks in the VNet resource.

### Step 3: Generate Plan and Analyze

```bash
# Generate plan
terraform plan -out=plan.tfplan

# Analyze with our tool
terraform show -json plan.tfplan | python3 ../../scripts/analyze_plan.py
```

### Step 4: Clean Up

```bash
terraform destroy
```

## Expected Results

When you reorder Set-type attribute blocks without changing their content:
- `terraform plan` will show changes (false positives)
- Our analyzer will classify these as "🟢 順序変更のみ（影響なし）"

## Cost Warning

⚠️ **Application Gateway incurs significant costs (~$200/month)**

If you only want to test with free resources, comment out the Application Gateway section in `main.tf`:
- `azurerm_subnet.appgw`
- `azurerm_public_ip.appgw`
- `azurerm_application_gateway.test`
