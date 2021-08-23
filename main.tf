######################################
# Set up Apache with terraform

provider "azurerm" {
  subscription_id = "7b43e0e1-2620-4cf4-94e1-d19236fe4acf"
  features {
  }
}

#Create azure resource group
resource "azurerm_resource_group" "apache_terraform_rg" {
  name     = var.resource_group_name
  location = var.location

  lifecycle {
    prevent_destroy = false
  }
}

#Create azure storage account
resource "azurerm_storage_account" "apache_terraform_sa" {
  name                     = "${var.prefix}sa"
  resource_group_name      = azurerm_resource_group.apache_terraform_rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}
#Create virtual network for the VM
resource "azurerm_virtual_network" "apache_terraform_vnet" {
  name                = var.virtual_network_name
  location            = var.location
  address_space       = var.address_space
  resource_group_name = azurerm_resource_group.apache_terraform_rg.name
}

#Create subnet to the virtual network
resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}_subnet"
  virtual_network_name = azurerm_virtual_network.apache_terraform_vnet.name
  resource_group_name  = azurerm_resource_group.apache_terraform_rg.name
  address_prefixes     = var.subnet_prefix
}

#Create public ip
resource "azurerm_public_ip" "apache_terraform_pip" {
  name                = "${var.prefix}-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.apache_terraform_rg.name
  allocation_method   = "Dynamic"
  domain_name_label   = var.hostname
}

#Create Network security group
resource "azurerm_network_security_group" "apache_terraform_sg" {
  name                = "${var.prefix}-sg"
  location            = var.location
  resource_group_name = azurerm_resource_group.apache_terraform_rg.name

  security_rule {
    name                       = "HTTP"
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
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

#Create Network interface
resource "azurerm_network_interface" "apache_terraform_nic" {
  name                = "${var.prefix}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.apache_terraform_rg.name

  ip_configuration {
    name                          = "${var.prefix}-ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.apache_terraform_pip.id
  }
}

#Create VM

resource "azurerm_virtual_machine" "apache_terraform_site" {
  name                = "${var.hostname}-site"
  location            = var.location
  resource_group_name = azurerm_resource_group.apache_terraform_rg.name
  vm_size             = var.vm_size

  network_interface_ids         = ["${azurerm_network_interface.apache_terraform_nic.id}"]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  storage_os_disk {
    name              = "${var.hostname}_osdisk"
    managed_disk_type = "Standard_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = var.hostname
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = file("~/.ssh/id_rsa.pub")
    }
  }

  # This is to ensure SSH comes up before we run the local exec.
  provisioner "remote-exec" {
    inline = [
      "sudo yum -y install httpd && sudo systemctl start httpd",
      "echo '<h1><center>My first website using terraform provisioner</center></h1>' > index.html",
      "echo '<h1><center>Jorge Gongora</center></h1>' >> index.html",
      "sudo mv index.html /var/www/html/"
    ]
    connection {
      type        = "ssh"
      host        = azurerm_public_ip.apache_terraform_pip.fqdn
      user        = var.admin_username
      private_key = file("~/.ssh/id_rsa")
    }
  }
}
