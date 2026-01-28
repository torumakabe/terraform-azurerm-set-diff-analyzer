#!/bin/bash
# Integration test script for AzureRM Set Diff Analyzer
# 
# This script:
# 1. Deploys test resources (subnet a, b, c)
# 2. Adds a new element (subnet-d) to trigger Set reordering
# 3. Runs terraform plan and analyzes the output for false-positive diffs
# 4. Optionally cleans up resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANALYZER="$REPO_ROOT/.github/skills/azurerm-set-diff-analyzer/scripts/analyze_plan.py"
MAIN_TF="$SCRIPT_DIR/main.tf"
MAIN_TF_BACKUP="$SCRIPT_DIR/main.tf.backup"

# Function to add a new subnet (subnet-d) to trigger Set reordering
add_subnet_d() {
    echo "    Adding subnet-d to azurerm_virtual_network.test..."
    
    # Insert subnet-d after subnet-c
    awk '
    /^  subnet \{/ { in_subnet = 1 }
    in_subnet && /name.*=.*"subnet-c"/ { found_c = 1 }
    found_c && /^  \}/ {
        print
        print ""
        print "  subnet {"
        print "    name             = \"subnet-d\""
        print "    address_prefixes = [\"10.0.4.0/24\"]"
        print "  }"
        found_c = 0
        in_subnet = 0
        next
    }
    { print }
    ' "$MAIN_TF" > "$MAIN_TF.tmp" && mv "$MAIN_TF.tmp" "$MAIN_TF"
}

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
    echo ">>> Step 1: Deploying initial test resources (subnet a, b, c)..."
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

echo ">>> Adding new Set elements to config..."
add_subnet_d
add_security_rule_rdp

echo ""
echo ">>> Step 4: Running plan after adding new elements..."
echo ">>> This may show false-positive diffs for existing elements due to Set reordering."
terraform plan -out=plan_modified.tfplan
terraform show -json plan_modified.tfplan > plan_modified.json

echo ""
echo "=== Plan Analysis After Adding Elements ==="
echo ">>> Look for '順序変更のみ' (order-only changes) in the output."
echo ">>> These are false positives - existing elements (a,b,c) shown as changed"
echo ">>> even though only new element (d) was added."
echo ""
python3 "$ANALYZER" plan_modified.json

# Step 5: Optionally apply the changes and run another plan
echo ""
read -p ">>> Apply the changes and run another plan? (y/N): " apply_confirm
if [[ "$apply_confirm" =~ ^[Yy]$ ]]; then
    echo ">>> Applying changes..."
    terraform apply -auto-approve
    
    echo ""
    echo ">>> Waiting for Azure API to stabilize..."
    sleep 10
    
    echo ""
    echo ">>> Running plan after apply (should show no changes)..."
    terraform plan -out=plan_final.tfplan
    terraform show -json plan_final.tfplan > plan_final.json
    
    echo ""
    echo "=== Final Plan Analysis (after apply) ==="
    python3 "$ANALYZER" plan_final.json
    
    rm -f plan_final.tfplan plan_final.json
fi

# Step 6: Restore main.tf
echo ""
echo ">>> Restoring original main.tf..."
restore_main_tf
trap - EXIT

# Step 7: Cleanup (if not skipped)
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
rm -f plan_initial.tfplan plan_initial.json plan_modified.tfplan plan_modified.json

echo ""
echo "=== Integration Test Complete ==="
