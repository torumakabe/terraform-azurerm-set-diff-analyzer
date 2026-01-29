#!/bin/bash
# Integration test script for AzureRM Set Diff Analyzer
#
# This script tests Set-type attribute false-positive detection using:
# - NSG security_rule (inline Set-type attribute)
# - Application Gateway (multiple inline Set-type attributes)
#
# Note: Subnets use standalone resources to avoid inline/standalone conflicts.
# See: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANALYZER="$REPO_ROOT/.github/skills/azurerm-set-diff-analyzer/scripts/analyze_plan.py"
MAIN_TF="$SCRIPT_DIR/main.tf"
MAIN_TF_BACKUP="$SCRIPT_DIR/main.tf.backup"

# Function to add a new security rule to trigger Set reordering
add_security_rule_rdp() {
    echo "    Adding allow-rdp rule to azurerm_network_security_group.test..."

    # Insert rdp rule after ssh rule
    awk '
    /^  security_rule \{/ { in_rule = 1 }
    in_rule && /name.*=.*"allow-ssh"/ { found_ssh = 1 }
    found_ssh && /^  \}/ {
        print
        print ""
        print "  security_rule {"
        print "    name                       = \"allow-rdp\""
        print "    priority                   = 400"
        print "    direction                  = \"Inbound\""
        print "    access                     = \"Allow\""
        print "    protocol                   = \"Tcp\""
        print "    source_port_range          = \"*\""
        print "    destination_port_range     = \"3389\""
        print "    source_address_prefix      = \"10.0.0.0/8\""
        print "    destination_address_prefix = \"*\""
        print "  }"
        found_ssh = 0
        in_rule = 0
        next
    }
    { print }
    ' "$MAIN_TF" > "$MAIN_TF.tmp" && mv "$MAIN_TF.tmp" "$MAIN_TF"
}

# Function to modify security rule (actual change, not just reordering)
modify_security_rule_ssh() {
    echo "    Modifying allow-ssh source_address_prefix (10.0.0.0/8 -> 192.168.0.0/16)..."

    sed -i.bak 's/source_address_prefix      = "10\.0\.0\.0\/8"/source_address_prefix      = "192.168.0.0\/16"/' "$MAIN_TF"
    rm -f "$MAIN_TF.bak"
}

# Function to add a new backend_address_pool to Application Gateway (nested Set addition)
add_appgw_backend_pool() {
    echo "    Adding pool-app4 to azurerm_application_gateway.test..."

    # Insert new backend_address_pool after pool-app3
    awk '
    /backend_address_pool \{/ { in_pool = 1 }
    in_pool && /name.*=.*"pool-app3"/ { found_app3 = 1 }
    found_app3 && /^  \}/ {
        print
        print ""
        print "  backend_address_pool {"
        print "    name  = \"pool-app4\""
        print "    fqdns = [\"app4.example.com\"]"
        print "  }"
        found_app3 = 0
        in_pool = 0
        next
    }
    { print }
    ' "$MAIN_TF" > "$MAIN_TF.tmp" && mv "$MAIN_TF.tmp" "$MAIN_TF"
}

# Function to modify backend_http_settings (nested Set actual change)
modify_appgw_http_settings() {
    echo "    Modifying http-settings-api request_timeout (60 -> 120)..."

    sed -i.bak 's/request_timeout       = 60/request_timeout       = 120/' "$MAIN_TF"
    rm -f "$MAIN_TF.bak"
}

# Function to restore main.tf from backup
restore_main_tf() {
    if [ -f "$MAIN_TF_BACKUP" ]; then
        echo ">>> Restoring main.tf from backup..."
        mv "$MAIN_TF_BACKUP" "$MAIN_TF"
    fi
}

cd "$SCRIPT_DIR"

echo "=== AzureRM Set Diff Analyzer - Integration Test ==="
echo ""
echo "This test adds new Set elements to observe false-positive diffs"
echo "caused by Azure API returning elements in different order."
echo ""

# Check prerequisites
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform is not installed"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is not installed"
    exit 1
fi

# Parse arguments
SKIP_DEPLOY=false
SKIP_DESTROY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        --skip-destroy)
            SKIP_DESTROY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-deploy   Skip initial deployment (use existing resources)"
            echo "  --skip-destroy  Skip cleanup after test"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Step 1: Initialize Terraform
echo ">>> Initializing Terraform..."
terraform init -upgrade

# Step 2: Deploy initial resources (if not skipped)
if [ "$SKIP_DEPLOY" = false ]; then
    echo ""
    echo ">>> Step 1: Deploying initial test resources..."
    terraform apply -auto-approve

    echo ""
    echo ">>> Waiting for Azure API to stabilize..."
    sleep 10
fi

# Step 3: Run initial plan (should show no changes or minimal changes)
echo ""
echo ">>> Step 2: Running initial plan after deploy..."
terraform plan -out=plan_initial.tfplan
terraform show -json plan_initial.tfplan > plan_initial.json

echo ""
echo "=== Initial Plan Analysis (after deploy) ==="
python3 "$ANALYZER" plan_initial.json

# Step 4: Backup and modify config to add new elements
echo ""
echo ">>> Step 3: Creating backup of main.tf..."
cp "$MAIN_TF" "$MAIN_TF_BACKUP"

# Set up trap to restore main.tf on exit
trap restore_main_tf EXIT

echo ">>> Adding new Set elements to config (security_rule)..."
add_security_rule_rdp

echo ""
echo ">>> Step 4: Running plan after adding new security rule..."
echo ">>> This may show false-positive diffs for existing rules due to Set reordering."
terraform plan -out=plan_add_elements.tfplan
terraform show -json plan_add_elements.tfplan > plan_add_elements.json

echo ""
echo "=== Plan Analysis After Adding Elements ==="
echo ">>> Look for '順序変更のみ' (order-only changes) in the output."
echo ">>> These are false positives - existing rules shown as changed"
echo ">>> even though only new rule (rdp) was added."
echo ""
python3 "$ANALYZER" plan_add_elements.json

# Step 5: Apply the element additions
echo ""
read -p ">>> Apply element additions? (y/N): " apply_add
if [[ "$apply_add" =~ ^[Yy]$ ]]; then
    echo ">>> Applying element additions..."
    terraform apply -auto-approve

    echo ""
    echo ">>> Waiting for Azure API to stabilize..."
    sleep 10
fi

# Step 6: Test element modification
echo ""
echo ">>> Step 5: Modifying existing element (allow-ssh source_address_prefix)..."
modify_security_rule_ssh

echo ""
echo ">>> Running plan after element modification..."
terraform plan -out=plan_modify_element.tfplan
terraform show -json plan_modify_element.tfplan > plan_modify_element.json

echo ""
echo "=== Plan Analysis After Element Modification ==="
echo ">>> Look for allow-ssh actual change + potential order-only changes for other rules."
echo ""
python3 "$ANALYZER" plan_modify_element.json

# Step 7: Apply the modification
echo ""
read -p ">>> Apply element modification? (y/N): " apply_modify
if [[ "$apply_modify" =~ ^[Yy]$ ]]; then
    echo ">>> Applying element modification..."
    terraform apply -auto-approve

    echo ""
    echo ">>> Waiting for Azure API to stabilize..."
    sleep 10
fi

# Step 8: Test nested Set element addition (Application Gateway backend_address_pool)
echo ""
echo ">>> Step 6: Adding new backend_address_pool to Application Gateway..."
add_appgw_backend_pool

echo ""
echo ">>> Running plan after adding backend_address_pool..."
terraform plan -out=plan_add_pool.tfplan
terraform show -json plan_add_pool.tfplan > plan_add_pool.json

echo ""
echo "=== Plan Analysis After Adding Backend Pool ==="
echo ">>> Look for pool-app4 as actual addition + potential order-only changes for pool-app1/2/3."
echo ""
python3 "$ANALYZER" plan_add_pool.json

# Step 9: Apply backend pool addition
echo ""
read -p ">>> Apply backend pool addition? (y/N): " apply_pool
if [[ "$apply_pool" =~ ^[Yy]$ ]]; then
    echo ">>> Applying backend pool addition..."
    terraform apply -auto-approve

    echo ""
    echo ">>> Waiting for Azure API to stabilize..."
    sleep 15
fi

# Step 10: Test nested Set element modification (Application Gateway backend_http_settings)
echo ""
echo ">>> Step 7: Modifying backend_http_settings request_timeout..."
modify_appgw_http_settings

echo ""
echo ">>> Running plan after modifying backend_http_settings..."
terraform plan -out=plan_modify_settings.tfplan
terraform show -json plan_modify_settings.tfplan > plan_modify_settings.json

echo ""
echo "=== Plan Analysis After Modifying HTTP Settings ==="
echo ">>> Look for http-settings-api as actual change + potential order-only changes for http-settings-default."
echo ""
python3 "$ANALYZER" plan_modify_settings.json

# Step 11: Apply http settings modification
echo ""
read -p ">>> Apply http settings modification? (y/N): " apply_settings
if [[ "$apply_settings" =~ ^[Yy]$ ]]; then
    echo ">>> Applying http settings modification..."
    terraform apply -auto-approve

    echo ""
    echo ">>> Waiting for Azure API to stabilize..."
    sleep 15
fi

# Step 12: Final plan check
echo ""
read -p ">>> Run final plan to verify no changes? (y/N): " run_final
if [[ "$run_final" =~ ^[Yy]$ ]]; then
    echo ">>> Running final plan (should show no changes)..."
    terraform plan -out=plan_final.tfplan
    terraform show -json plan_final.tfplan > plan_final.json

    echo ""
    echo "=== Final Plan Analysis ==="
    python3 "$ANALYZER" plan_final.json

    rm -f plan_final.tfplan plan_final.json
fi

# Step 13: Restore main.tf
echo ""
echo ">>> Restoring original main.tf..."
restore_main_tf
trap - EXIT

# Step 14: Cleanup (if not skipped)
if [ "$SKIP_DESTROY" = false ]; then
    echo ""
    read -p ">>> Destroy test resources? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo ">>> Destroying resources..."
        terraform destroy -auto-approve
    else
        echo ">>> Skipping destroy. Run 'terraform destroy' manually to clean up."
    fi
fi

# Cleanup temporary files
rm -f plan_initial.tfplan plan_initial.json
rm -f plan_add_elements.tfplan plan_add_elements.json
rm -f plan_modify_element.tfplan plan_modify_element.json
rm -f plan_add_pool.tfplan plan_add_pool.json
rm -f plan_modify_settings.tfplan plan_modify_settings.json

echo ""
echo "=== Integration Test Complete ==="
echo ""
echo "Test Coverage Summary:"
echo "  ✅ NSG: Element addition (allow-rdp)"
echo "  ✅ NSG: Element modification (allow-ssh source_address_prefix change)"
echo "  ✅ App Gateway: Nested Set addition (backend_address_pool)"
echo "  ✅ App Gateway: Nested Set modification (backend_http_settings timeout)"
echo ""
echo "Note: Subnets use standalone resources to avoid inline/standalone conflicts."
