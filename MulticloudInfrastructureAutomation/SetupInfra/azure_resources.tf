resource "azurerm_resource_group" "rg" {
  name     = "mcia-resources"
  location = "east us"

}

resource "azurerm_postgresql_server" "psqlserver" {
  name                = "mcia-postgresql-server"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  administrator_login          = "${var.postgresdb_user}"
  administrator_login_password = "${var.postgresdb_password}"

  sku_name   = "B_Gen5_2"
  version    = "11"
  storage_mb = 102400

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = false

  public_network_access_enabled    = true
  ssl_enforcement_enabled          = true
  ssl_minimal_tls_version_enforced = "TLS1_2"

}

resource "azurerm_postgresql_firewall_rule" "example" {
  name                = "mcia_firewall_rule-${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_postgresql_server.psqlserver.name
  start_ip_address    = "${aws_eip.myeip-natgw[count.index].public_ip}"
  end_ip_address      = "${aws_eip.myeip-natgw[count.index].public_ip}"
  count=1
}