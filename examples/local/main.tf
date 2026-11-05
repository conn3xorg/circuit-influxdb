variable "port" {
  type    = number
  default = 2222
}

# Pass it in TF_VAR_admin_token. See the README for one way to make one.
variable "admin_token" {
  type      = string
  ephemeral = true
}

# CI applies an older release first, then this one, to test the upgrade.
variable "influxdb_version" {
  type    = string
  default = "3.12.2"
}

module "influxdb" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  influxdb_version = var.influxdb_version
  admin_token      = var.admin_token

  settings = {
    gen1-duration = "1m"
  }
}
