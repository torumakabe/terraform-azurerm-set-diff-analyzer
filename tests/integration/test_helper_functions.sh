#!/bin/bash
# Test helper functions from helpers.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_TF="$SCRIPT_DIR/main.tf"
MAIN_TF_BACKUP="$SCRIPT_DIR/main.tf.backup"

# Load helper functions
source "$SCRIPT_DIR/helpers.sh"

# Test add_security_rule_rdp function
echo "=== Testing add_security_rule_rdp function ==="
cp "$MAIN_TF" "$MAIN_TF_BACKUP"
add_security_rule_rdp

if grep -q "allow-rdp" "$MAIN_TF"; then
    echo "✅ add_security_rule_rdp: PASS"
else
    echo "❌ add_security_rule_rdp: FAIL"
fi
mv "$MAIN_TF_BACKUP" "$MAIN_TF"

# Test modify_security_rule_ssh function
echo ""
echo "=== Testing modify_security_rule_ssh function ==="
cp "$MAIN_TF" "$MAIN_TF_BACKUP"
modify_security_rule_ssh

if grep -q "192.168.0.0/16" "$MAIN_TF"; then
    echo "✅ modify_security_rule_ssh: PASS"
else
    echo "❌ modify_security_rule_ssh: FAIL"
fi
mv "$MAIN_TF_BACKUP" "$MAIN_TF"

# Test add_appgw_backend_pool function
echo ""
echo "=== Testing add_appgw_backend_pool function ==="
cp "$MAIN_TF" "$MAIN_TF_BACKUP"
add_appgw_backend_pool

if grep -q "pool-app4" "$MAIN_TF"; then
    echo "✅ add_appgw_backend_pool: PASS"
else
    echo "❌ add_appgw_backend_pool: FAIL"
fi
mv "$MAIN_TF_BACKUP" "$MAIN_TF"

# Test modify_appgw_http_settings function
echo ""
echo "=== Testing modify_appgw_http_settings function ==="
cp "$MAIN_TF" "$MAIN_TF_BACKUP"
modify_appgw_http_settings

if grep -q "request_timeout       = 120" "$MAIN_TF"; then
    echo "✅ modify_appgw_http_settings: PASS"
else
    echo "❌ modify_appgw_http_settings: FAIL"
fi
mv "$MAIN_TF_BACKUP" "$MAIN_TF"

echo ""
echo "=== All helper function tests complete ==="
