# Facts give each host's distribution, which picks InfluxData's apt or rpm
# repository.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = contains(["debian", "ubuntu", "rocky", "almalinux", "rhel", "fedora"], self.os_id)
      error_message = "Host ${each.key} runs ${self.os_id}. This circuit supports Debian, Ubuntu, Rocky Linux, AlmaLinux, RHEL and Fedora. CentOS Linux reached end of life on 30 June 2024: use Rocky Linux."
    }
    postcondition {
      condition     = try(each.value.os, self.os_id) == self.os_id
      error_message = "Host ${each.key} is ${self.os_id}, not the ${try(each.value.os, "")} its os says."
    }
  }
}

locals {
  # A host object's os stands in for the facts of a host created in the
  # same plan, which can't be read until it exists.
  os  = { for name, h in var.hosts : name => try(h.os, data.conn3x_host.facts[name].os_id) }
  deb = { for name, o in local.os : name => contains(["debian", "ubuntu"], o) }

  config_file = "/etc/influxdb3/influxdb3-core.conf"
  token_file  = "/etc/influxdb3/admin-token.json"

  # The address the host itself reaches the API on. A wildcard isn't one it
  # can dial.
  bind_host   = regex("^(.*):[0-9]+$", var.http_bind)[0]
  bind_port   = regex(":([0-9]+)$", var.http_bind)[0]
  client_bind = contains(["0.0.0.0", "[::]"], local.bind_host) ? "127.0.0.1:${local.bind_port}" : var.http_bind

  # The package's systemd unit starts InfluxDB through a launcher that reads
  # this flat TOML file and turns each key into an INFLUXDB3_* variable.
  # jsonencode quotes strings the way TOML does.
  options = merge(var.settings, {
    node-id                  = var.node_id
    object-store             = "file"
    data-dir                 = "/var/lib/influxdb3/data"
    plugin-dir               = "/var/lib/influxdb3/plugins"
    http-bind                = var.http_bind
    disable-telemetry-upload = !var.telemetry
  }, var.set_admin_token ? { admin-token-file = local.token_file } : {})
  config = "# Written by Conn3x. Changes here are overwritten on the next apply.\n${join("", [for k in sort(keys(local.options)) : "${k} = ${jsonencode(local.options[k])}\n"])}"

  # The launcher's own reader checks the new file, so a file it would refuse
  # at start never replaces the old one.
  config_test = "/usr/lib/influxdb3/python/bin/python3 -I -c 'import importlib.machinery as m, importlib.util as u, sys; l = m.SourceFileLoader(\"launcher\", \"/usr/lib/influxdb3/influxdb3-launcher\"); s = u.spec_from_loader(\"launcher\", l); mod = u.module_from_spec(s); l.exec_module(mod); mod.read_config_toml(sys.argv[1], \"core\")' %s"

  health = "curl -s -o /dev/null -w '%%{http_code}' http://${local.client_bind}/health | grep -qv '^000$'"
}

circuit "influxdb" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # The ready check below asks the API over HTTP.
  step "tools" {
    package {
      name = "curl"
    }
  }

  # InfluxData signs both repositories with the key in files, fingerprint
  # 24C9 75CB A61A 024E E1B6 3178 7C3D 5715 9FC2 F927. Its current signing
  # subkey expires on 17 January 2029.
  step "repo" {
    repository {
      name       = "influxdata"
      url        = local.deb[each.key] ? "https://repos.influxdata.com/debian" : "https://repos.influxdata.com/stable/$basearch/main"
      key        = file("${path.module}/files/influxdata-archive.asc")
      suites     = local.deb[each.key] ? ["stable"] : null
      components = ["main"]
    }
  }

  # The package brings the influxdb3 user, a sandboxed systemd unit and its
  # own Python for the processing engine. apt only installs a version given
  # in full, with the package release InfluxData builds every version at.
  step "package" {
    package {
      name    = "influxdb3-core"
      version = local.deb[each.key] ? "${var.influxdb_version}-1" : var.influxdb_version
    }
  }

  # InfluxDB reads this file at start only while it has no tokens, and
  # stores a hash of the token it holds. Setting set_admin_token to false
  # removes the step, and with it the file.
  step "admin_token" {
    for_each = var.set_admin_token ? toset(["token"]) : toset([])
    file {
      path       = local.token_file
      content_wo = jsonencode({ token = var.admin_token, name = "_admin" })
      owner      = "root"
      group      = "influxdb3"
      mode       = "0640"
      on_remove  = "delete"
    }
  }

  step "config" {
    file {
      path     = local.config_file
      content  = local.config
      validate = local.config_test
    }
  }

  # InfluxDB can't reload its options, so a new file or a new release means
  # a restart. This is a step rather than a handler because handlers run
  # after every step, and the ready check has to see the new server.
  step "restart" {
    service_action {
      name     = "influxdb3-core"
      triggers = { config = conn3x_file.influxdb__config[each.key].revision, version = var.influxdb_version }
    }
  }

  step "running" {
    service {
      name    = "influxdb3-core"
      state   = "started"
      enabled = true
    }
  }

  # Any HTTP answer will do, a 401 included: the server is up and serving.
  # unless is checked at plan time, before a restart, so the restart's
  # triggers make the apply wait again.
  step "ready" {
    command {
      command  = "for _ in $(seq 60); do ${local.health} && exit 0; sleep 1; done; echo 'InfluxDB is not answering on ${var.http_bind}. See journalctl -u influxdb3-core.' >&2; exit 1"
      unless   = local.health
      triggers = { config = conn3x_file.influxdb__config[each.key].revision, version = var.influxdb_version }
    }
  }
}
