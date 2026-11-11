output "hostnames" {
  description = "Public hostname of each service."
  value       = module.private_access.hostnames
}

output "ssh_config" {
  description = "Entry to add to ~/.ssh/config, then connect with: ssh root@<ssh hostname>."
  value       = module.private_access.ssh_config
}

output "droplet_public_ip" {
  description = "Public IP of the droplet. It accepts no inbound connections."
  value       = digitalocean_droplet.app.ipv4_address
}
