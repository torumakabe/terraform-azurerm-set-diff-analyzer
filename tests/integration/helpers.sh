#!/bin/bash
# Helper functions for integration tests
# These functions manipulate main.tf for testing Set-type attribute changes

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MAIN_TF="${MAIN_TF:-$SCRIPT_DIR/main.tf}"

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
