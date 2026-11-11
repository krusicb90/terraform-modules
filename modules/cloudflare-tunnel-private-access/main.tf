locals {
  # Sorted so that the ingress rules keep a stable order between plans.
  service_keys = sort(keys(var.services))
  ssh_services = [for key in local.service_keys : var.services[key] if var.services[key].type == "ssh"]
}

# The tunnel is configured remotely. The machine holds a token and nothing
# else: no config file to keep in sync, no credentials file to protect.
resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.account_id
  name       = var.name
  config_src = "cloudflare"
}

# --- Who may connect -----------------------------------------------------------

resource "cloudflare_zero_trust_access_policy" "allow" {
  account_id       = var.account_id
  name             = "${var.name}-allow"
  decision         = "allow"
  session_duration = var.session_duration

  include = concat(
    [for email in var.allowed_emails : { email = { email = email } }],
    [for domain in var.allowed_email_domains : { email_domain = { domain = domain } }],
  )

  lifecycle {
    precondition {
      condition     = length(var.allowed_emails) + length(var.allowed_email_domains) > 0
      error_message = "Set allowed_emails or allowed_email_domains. A policy without identities would lock everyone out."
    }
  }
}

resource "cloudflare_zero_trust_access_application" "this" {
  for_each = var.services

  account_id       = var.account_id
  name             = "${var.name}-${each.key}"
  type             = each.value.type
  domain           = each.value.hostname
  session_duration = var.session_duration

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow.id
    precedence = 1
  }]
}

# --- Where the traffic goes -------------------------------------------------------

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = concat(
      [for key in local.service_keys : {
        hostname = var.services[key].hostname
        service  = var.services[key].service

        # Second lock. cloudflared checks the Access token itself, so a request
        # that reaches the tunnel without passing Access is rejected at the
        # origin, whatever the dashboard says.
        origin_request = var.services[key].verify_access_at_origin ? {
          access = {
            required  = true
            team_name = var.team_name
            aud_tag   = [cloudflare_zero_trust_access_application.this[key].aud]
          }
        } : null
      }],
      # Anything that matches no hostname gets a 404 instead of reaching the machine.
      [{ service = "http_status:404" }],
    )
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = var.services

  zone_id = var.zone_id
  name    = each.value.hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Tunnel ${var.name}, managed by Terraform"

  # A hostname must not resolve before Access protects it.
  depends_on = [cloudflare_zero_trust_access_application.this]
}

# --- What the machine needs ---------------------------------------------------------

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}
