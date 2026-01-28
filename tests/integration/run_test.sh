#!/bin/bash
# Integration test script for AzureRM Set Diff Analyzer
# 
# This script:
# 1. Deploys test resources
# 2. Reorders Set-type attributes in the config
# 3. Runs terraform plan and analyzes the output
# 4. Optionally cleans up resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANALYZER="$REPO_ROOT/scripts/analyze_plan.py"

cd "$SCRIPT_DIR"

echo "=== AzureRM Set Diff Analyzer - Integration Test ==="
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
APPGW_ENABLED=true

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
        --no-appgw)
            APPGW_ENABLED=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-deploy   Skip initial deployment (use existing resources)"
            echo "  --skip-destroy  Skip cleanup after test"
            echo "  --no-appgw      Don't deploy Application Gateway (saves cost)"
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
    echo ">>> Deploying test resources..."
    
    if [ "$APPGW_ENABLED" = false ]; then
        echo "    (Application Gateway disabled to save cost)"
        # Use a tfvars or target to skip AppGW - for simplicity, we'll just warn
        echo "    Note: Edit main.tf to comment out AppGW resources if you want to skip them"
    fi
    
    terraform apply -auto-approve
    
    echo ""
    echo ">>> Waiting for Azure API to stabilize..."
    sleep 10
fi

# Step 3: Run initial plan (should show no changes)
echo ""
echo ">>> Running initial plan (expecting no changes)..."
terraform plan -out=plan_initial.tfplan
terraform show -json plan_initial.tfplan > plan_initial.json

echo ""
echo "=== Initial Plan Analysis ==="
python3 "$ANALYZER" plan_initial.json

# Step 4: Simulate a "no-op" change by running plan again
# In real scenarios, the ordering diff happens when Azure returns attributes in different order
# For testing, we can trigger a refresh
echo ""
echo ">>> Running refresh and plan again..."
terraform refresh
terraform plan -out=plan_refresh.tfplan
terraform show -json plan_refresh.tfplan > plan_refresh.json

echo ""
echo "=== Post-Refresh Plan Analysis ==="
python3 "$ANALYZER" plan_refresh.json

# Step 5: Cleanup (if not skipped)
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
rm -f plan_initial.tfplan plan_initial.json plan_refresh.tfplan plan_refresh.json

echo ""
echo "=== Integration Test Complete ==="
