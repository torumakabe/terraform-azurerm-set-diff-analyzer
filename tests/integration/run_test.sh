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

# Function to add Application Gateway with nested Set structures
add_application_gateway() {
    echo "    Adding Application Gateway with nested Set structures..."

    # Append Application Gateway resource to main.tf
    cat >> "$MAIN_TF" << 'EOF'

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-test"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "test" {
  name                = "appgw-test"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.gateway.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = "pool-web"
    fqdns = ["web1.example.com", "web2.example.com"]
  }

  backend_address_pool {
    name = "pool-api"
    fqdns = ["api.example.com"]
  }

  backend_http_settings {
    name                  = "http-settings-web"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule-http"
    rule_type                  = "Basic"
    http_listener_name         = "listener-http"
    backend_address_pool_name  = "pool-web"
    backend_http_settings_name = "http-settings-web"
    priority                   = 100
  }

  rewrite_rule_set {
    name = "rewrite-set-1"

    rewrite_rule {
      name          = "add-x-forwarded-for"
      rule_sequence = 100

      condition {
        variable    = "http_req_Host"
        pattern     = ".*"
        ignore_case = true
      }

      request_header_configuration {
        header_name  = "X-Forwarded-For"
        header_value = "{var_client_ip}"
      }
    }

    rewrite_rule {
      name          = "add-custom-header"
      rule_sequence = 200

      request_header_configuration {
        header_name  = "X-Custom-Header"
        header_value = "custom-value"
      }
    }
  }
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.test.name
  address_prefixes     = ["10.0.255.0/24"]
}
EOF
}

# Function to add a rewrite rule to existing Application Gateway (nested Set modification)
add_appgw_rewrite_rule() {
    echo "    Adding new rewrite rule to Application Gateway..."

    # Find the last rewrite_rule closing brace and insert new rule before rewrite_rule_set closing
    awk '
    /^  rewrite_rule_set \{/ { in_set = 1 }
    in_set && /^    rewrite_rule \{/ { in_rule = 1 }
    in_rule && /^    \}/ {
        in_rule = 0
        last_rule_line = NR
    }
    in_set && /^  \}/ && last_rule_line > 0 {
        print ""
        print "    rewrite_rule {"
        print "      name          = \"add-security-header\""
        print "      rule_sequence = 300"
        print ""
        print "      response_header_configuration {"
        print "        header_name  = \"X-Content-Type-Options\""
        print "        header_value = \"nosniff\""
        print "      }"
        print "    }"
        last_rule_line = 0
        in_set = 0
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

# Step 8: Test nested Set structures (Application Gateway)
echo ""
echo ">>> Step 6: Adding Application Gateway with nested Set structures..."
add_application_gateway

echo ""
echo ">>> Running plan after adding Application Gateway..."
terraform plan -out=plan_add_appgw.tfplan
terraform show -json plan_add_appgw.tfplan > plan_add_appgw.json

echo ""
echo "=== Plan Analysis After Adding Application Gateway ==="
echo ">>> Observing nested Set structures: backend_address_pool, rewrite_rule_set.rewrite_rule, etc."
echo ""
python3 "$ANALYZER" plan_add_appgw.json

# Step 9: Apply Application Gateway
echo ""
read -p ">>> Apply Application Gateway? (This may take 10-15 minutes) (y/N): " apply_appgw
if [[ "$apply_appgw" =~ ^[Yy]$ ]]; then
    echo ">>> Applying Application Gateway (this will take several minutes)..."
    terraform apply -auto-approve

    echo ""
    echo ">>> Waiting for Azure API to stabilize..."
    sleep 15

    # Step 10: Modify nested Set (add rewrite rule)
    echo ""
    echo ">>> Step 7: Adding new rewrite rule to nested Set..."
    add_appgw_rewrite_rule

    echo ""
    echo ">>> Running plan after modifying nested Set..."
    terraform plan -out=plan_modify_nested.tfplan
    terraform show -json plan_modify_nested.tfplan > plan_modify_nested.json

    echo ""
    echo "=== Plan Analysis After Nested Set Modification ==="
    echo ">>> Look for order-only changes in existing rewrite rules."
    echo ""
    python3 "$ANALYZER" plan_modify_nested.json

    # Step 11: Apply nested modification
    echo ""
    read -p ">>> Apply nested Set modification? (y/N): " apply_nested
    if [[ "$apply_nested" =~ ^[Yy]$ ]]; then
        echo ">>> Applying nested modification..."
        terraform apply -auto-approve

        echo ""
        echo ">>> Waiting for Azure API to stabilize..."
        sleep 10
    fi
fi

# Step 12: Final plan check
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
rm -f plan_initial.tfplan plan_initial.json
rm -f plan_add_elements.tfplan plan_add_elements.json
rm -f plan_modify_element.tfplan plan_modify_element.json
rm -f plan_add_appgw.tfplan plan_add_appgw.json
rm -f plan_modify_nested.tfplan plan_modify_nested.json

echo ""
echo "=== Integration Test Complete ==="
echo ""
echo "Test Coverage Summary:"
echo "  ✅ Order-only changes (security_rule)"
echo "  ✅ Element addition (allow-rdp)"
echo "  ✅ Element modification (allow-ssh source_address_prefix change)"
echo "  ✅ Nested Set structures (Application Gateway)"
echo "  ✅ Nested Set modification (rewrite_rule addition)"
echo ""
echo "Note: Subnets use standalone resources to avoid inline/standalone conflicts."
