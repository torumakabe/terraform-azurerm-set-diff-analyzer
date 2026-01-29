#!/bin/bash
# Test individual functions from run_test.sh

SCRIPT_DIR="$(pwd)"
MAIN_TF="$SCRIPT_DIR/main.tf"
MAIN_TF_BACKUP="$SCRIPT_DIR/main.tf.backup"

# Define test functions
add_security_rule_rdp() {
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

modify_security_rule_ssh() {
    sed -i.bak 's/source_address_prefix      = "10\.0\.0\.0\/8"/source_address_prefix      = "192.168.0.0\/16"/' "$MAIN_TF"
    rm -f "$MAIN_TF.bak"
}

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

echo ""
echo "=== Function tests complete ==="
