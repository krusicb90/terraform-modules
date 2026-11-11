output "tunnel_id" {
  description = "ID of the tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_token" {
  description = "Token that cloudflared uses to connect the machine to the tunnel. Treat it as a secret."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  sensitive   = true
}

output "cloud_init" {
  description = "cloud-config user data that installs cloudflared on a Debian or Ubuntu machine and connects it to the tunnel. It contains the tunnel token."
  value       = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", { token = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token })
  sensitive   = true
}

output "hostnames" {
  description = "Public hostname of each service, by service key."
  value       = { for key, service in var.services : key => service.hostname }
}

output "access_application_ids" {
  description = "ID of the Access application of each service, by service key."
  value       = { for key, application in cloudflare_zero_trust_access_application.this : key => application.id }
}

output "access_policy_id" {
  description = "ID of the Access policy shared by every service."
  value       = cloudflare_zero_trust_access_policy.allow.id
}

output "ssh_config" {
  description = "Entries for ~/.ssh/config that route SSH to the ssh-type services through cloudflared. Empty when there are none."
  value       = join("\n\n", [for service in local.ssh_services : "Host ${service.hostname}\n  ProxyCommand cloudflared access ssh --hostname %h"])
}
