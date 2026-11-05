variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts or os."

  validation {
    condition     = alltrue([for h in var.hosts : contains(["debian", "ubuntu", "rocky", "almalinux", "rhel", "fedora"], try(h.os, "debian"))])
    error_message = "A host object's os must be one of debian, ubuntu, rocky, almalinux, rhel or fedora. CentOS Linux reached end of life on 30 June 2024: use Rocky Linux."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "influxdb_version" {
  type        = string
  default     = "3.12.2"
  description = "InfluxDB 3 Core release to install from InfluxData's repository, such as \"3.12.2\"."

  validation {
    condition     = can(regex("^3\\.[0-9]+\\.[0-9]+$", var.influxdb_version))
    error_message = "influxdb_version is an InfluxDB 3 release number such as \"3.12.2\"."
  }
}

variable "http_bind" {
  type        = string
  default     = "127.0.0.1:8181"
  description = "Address and port the HTTP API listens on. Loopback by default. Set the host's own address, or 0.0.0.0:8181, to reach it from other machines."

  validation {
    condition     = can(regex("^([0-9.]+|\\[[0-9a-fA-F:]+\\]):[0-9]{1,5}$", var.http_bind)) && tonumber(regex(":([0-9]+)$", var.http_bind)[0]) <= 65535
    error_message = "http_bind is an IP address and port, such as \"127.0.0.1:8181\" or \"[::1]:8181\"."
  }
}

variable "node_id" {
  type        = string
  default     = "primary-node"
  description = "Node ID, the prefix InfluxDB puts on every path in its data directory. The package's default. Changing it on a server with data starts an empty one beside the old data."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", var.node_id))
    error_message = "node_id must be letters, digits, _ and -, such as \"primary-node\"."
  }
}

variable "telemetry" {
  type        = bool
  default     = false
  description = "Send InfluxData the usage telemetry InfluxDB uploads by default. Off unless you turn it on."
}

variable "set_admin_token" {
  type        = bool
  default     = true
  description = "Give the server admin_token as its first admin token. When false, the circuit writes no token, and you create one on the host with influxdb3 create token --admin."
}

variable "admin_token" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Admin token the server starts with, apiv3_ followed by at least 32 letters, digits, _ or -. Used only while the server has no tokens. Required when set_admin_token is true."

  validation {
    condition     = !var.set_admin_token || can(regex("^apiv3_[A-Za-z0-9_-]{32,}$", var.admin_token))
    error_message = "Set admin_token to apiv3_ followed by at least 32 letters, digits, _ or -, or set set_admin_token = false."
  }
}

variable "settings" {
  type        = map(string)
  default     = {}
  description = "More server options for /etc/influxdb3/influxdb3-core.conf, by their command-line name without the dashes, such as { gen1-duration = \"10m\" }. The circuit sets http-bind, node-id, object-store, data-dir, plugin-dir, admin-token-file and disable-telemetry-upload itself."

  validation {
    condition     = alltrue([for k, v in var.settings : can(regex("^[a-z0-9][a-z0-9-]*$", k)) && !contains(["http-bind", "node-id", "object-store", "data-dir", "plugin-dir", "admin-token-file", "disable-telemetry-upload"], k)])
    error_message = "Each key in settings is an option name such as \"gen1-duration\", and can't be one the circuit sets itself."
  }
}
