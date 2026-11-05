output "url" {
  description = "URL of each host's HTTP API, from http_bind. A wildcard address gives 127.0.0.1, which works on the host itself."
  value       = "http://${local.client_bind}"
}

output "service" {
  description = "The systemd unit InfluxDB runs as on each host."
  value       = "influxdb3-core.service"
}
