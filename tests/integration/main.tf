terraform {
  required_version = ">= 1.14.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.58"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "japaneast"
}

variable "prefix" {
  type    = string
  default = "tfsettest"
}

resource "azurerm_resource_group" "test" {
  name     = "rg-${var.prefix}"
  location = var.location
}

# =============================================================================
# Test 1: Virtual Network with inline subnets (Set-type attribute)
# =============================================================================
resource "azurerm_virtual_network" "test" {
  name                = "vnet-${var.prefix}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  address_space       = ["10.0.0.0/16"]

  # These subnets are Set-type attributes - order may change
  subnet {
    name             = "subnet-a"
    address_prefixes = ["10.0.1.0/24"]
  }

  subnet {
    name             = "subnet-b"
    address_prefixes = ["10.0.2.0/24"]
  }

  subnet {
    name             = "subnet-c"
    address_prefixes = ["10.0.3.0/24"]
  }

  tags = {
    environment = "test"
    purpose     = "set-diff-analyzer-test"
  }
}

# =============================================================================
# Test 2: Network Security Group with inline security_rules (Set-type attribute)
# =============================================================================
resource "azurerm_network_security_group" "test" {
  name                = "nsg-${var.prefix}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  # These security_rules are Set-type attributes - order may change
  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.0.0/8"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "test"
    purpose     = "set-diff-analyzer-test"
  }
}

# =============================================================================
# Test 3: Application Gateway (multiple Set-type attributes)
# Note: This resource incurs costs. Comment out if not needed.
# =============================================================================
resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.test.name
  address_prefixes     = ["10.0.10.0/24"]
}

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.prefix}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    environment = "test"
    purpose     = "set-diff-analyzer-test"
  }
}

resource "azurerm_application_gateway" "test" {
  name                = "appgw-${var.prefix}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  # Set-type: frontend_port
  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  frontend_port {
    name = "port-8080"
    port = 8080
  }

  # Set-type: frontend_ip_configuration
  frontend_ip_configuration {
    name                 = "frontend-ip-public"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Set-type: backend_address_pool
  backend_address_pool {
    name  = "pool-app1"
    fqdns = ["app1.example.com"]
  }

  backend_address_pool {
    name  = "pool-app2"
    fqdns = ["app2.example.com"]
  }

  backend_address_pool {
    name  = "pool-app3"
    fqdns = ["app3.example.com"]
  }

  # Set-type: backend_http_settings
  backend_http_settings {
    name                  = "http-settings-default"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  backend_http_settings {
    name                  = "http-settings-api"
    cookie_based_affinity = "Disabled"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 60
  }

  # Set-type: http_listener
  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "frontend-ip-public"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  http_listener {
    name                           = "listener-8080"
    frontend_ip_configuration_name = "frontend-ip-public"
    frontend_port_name             = "port-8080"
    protocol                       = "Http"
  }

  # Set-type: request_routing_rule
  request_routing_rule {
    name                       = "rule-http"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "listener-http"
    backend_address_pool_name  = "pool-app1"
    backend_http_settings_name = "http-settings-default"
  }

  request_routing_rule {
    name                       = "rule-8080"
    priority                   = 200
    rule_type                  = "Basic"
    http_listener_name         = "listener-8080"
    backend_address_pool_name  = "pool-app2"
    backend_http_settings_name = "http-settings-api"
  }

  tags = {
    environment = "test"
    purpose     = "set-diff-analyzer-test"
  }
}

# =============================================================================
# Outputs
# =============================================================================
output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "vnet_name" {
  value = azurerm_virtual_network.test.name
}

output "nsg_name" {
  value = azurerm_network_security_group.test.name
}

output "appgw_name" {
  value = azurerm_application_gateway.test.name
}
