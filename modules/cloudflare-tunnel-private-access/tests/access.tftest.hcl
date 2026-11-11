# Tests against a mocked Cloudflare provider. They need no Cloudflare account
# and create nothing, so they run on every push.

mock_provider "cloudflare" {}

variables {
  account_id            = "0123456789abcdef0123456789abcdef"
  zone_id               = "fedcba9876543210fedcba9876543210"
  team_name             = "acme"
  name                  = "app-server"
  allowed_email_domains = ["example.com"]
  services = {
    web = {
      hostname = "app.example.com"
      service  = "http://localhost:8080"
    }
    ssh = {
      hostname = "ssh.example.com"
      service  = "ssh://localhost:22"
      type     = "ssh"
    }
  }
}

run "every_service_is_behind_access" {
  command = plan

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared.this.config_src == "cloudflare"
    error_message = "The tunnel must be remotely managed, so the machine needs only a token."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_application.this) == length(var.services)
    error_message = "Every service needs its own Access application."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this["ssh"].type == "ssh" && cloudflare_zero_trust_access_application.this["web"].type == "self_hosted"
    error_message = "The Access application type must follow the service type."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this["web"].domain == "app.example.com"
    error_message = "The Access application must protect the hostname of its service."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_policy.allow.include) == 1
    error_message = "The policy must contain exactly the identities that were passed in."
  }

  assert {
    condition     = cloudflare_zero_trust_access_policy.allow.decision == "allow"
    error_message = "The shared policy is an allow-list."
  }
}

run "ingress_is_ordered_and_ends_with_a_catch_all" {
  command = plan

  assert {
    condition     = length(cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress) == 3
    error_message = "There must be one ingress rule per service, plus the catch-all."
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].hostname == "ssh.example.com"
    error_message = "Ingress rules must be sorted by service key, so their order is stable."
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[2].service == "http_status:404"
    error_message = "The last ingress rule must answer 404 for anything that matches no hostname."
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[2].hostname == null
    error_message = "The catch-all must not have a hostname."
  }
}

run "origin_verifies_access_by_default" {
  command = plan

  assert {
    condition = alltrue([
      for rule in slice(cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress, 0, 2) :
      rule.origin_request.access.required == true && rule.origin_request.access.team_name == "acme"
    ])
    error_message = "cloudflared must verify the Access token for every service unless a service opts out."
  }
}

run "a_service_can_opt_out_of_origin_verification" {
  command = plan

  variables {
    services = {
      web = {
        hostname                = "app.example.com"
        service                 = "http://localhost:8080"
        verify_access_at_origin = false
      }
    }
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].origin_request == null
    error_message = "Opting out must remove the origin check for that service only."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_application.this) == 1
    error_message = "Opting out of the origin check must not remove the Access application."
  }
}

run "dns_points_at_the_tunnel" {
  command = plan

  assert {
    condition     = alltrue([for record in cloudflare_dns_record.this : record.type == "CNAME" && record.proxied == true])
    error_message = "Every hostname must be a proxied CNAME."
  }

  assert {
    condition     = cloudflare_dns_record.this["web"].name == "app.example.com"
    error_message = "The DNS record must use the hostname of its service."
  }
}

# The mocked provider can apply for free. That makes the values Cloudflare
# generates available, so the wiring between resources can be checked.
run "resources_are_wired_together" {
  command = apply

  assert {
    condition     = cloudflare_dns_record.this["web"].content == "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
    error_message = "The DNS record must point at this tunnel."
  }

  assert {
    condition     = length(cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[1].origin_request.access.aud_tag) == 1 && cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[1].origin_request.access.aud_tag[0] == cloudflare_zero_trust_access_application.this["web"].aud
    error_message = "cloudflared must accept tokens issued for the Access application of the same service, and no other."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this["web"].policies[0].id == cloudflare_zero_trust_access_policy.allow.id
    error_message = "Every Access application must use the shared allow policy."
  }

  assert {
    condition     = strcontains(output.cloud_init, data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token)
    error_message = "The cloud-init output must contain the tunnel token."
  }

  assert {
    condition     = startswith(output.cloud_init, "#cloud-config\n")
    error_message = "The user data must start with the cloud-config header, or cloud-init ignores it."
  }

  assert {
    condition     = output.ssh_config == "Host ssh.example.com\n  ProxyCommand cloudflared access ssh --hostname %h"
    error_message = "ssh_config must contain an entry for the ssh-type service only."
  }
}

run "rejects_a_policy_without_identities" {
  command = plan

  variables {
    allowed_email_domains = []
  }

  expect_failures = [
    cloudflare_zero_trust_access_policy.allow,
  ]
}

run "rejects_no_services" {
  command = plan

  variables {
    services = {}
  }

  expect_failures = [
    var.services,
  ]
}

run "rejects_a_hostname_with_a_scheme" {
  command = plan

  variables {
    services = {
      web = {
        hostname = "https://app.example.com"
        service  = "http://localhost:8080"
      }
    }
  }

  expect_failures = [
    var.services,
  ]
}

run "rejects_two_services_on_one_hostname" {
  command = plan

  variables {
    services = {
      web = {
        hostname = "app.example.com"
        service  = "http://localhost:8080"
      }
      admin = {
        hostname = "app.example.com"
        service  = "http://localhost:9000"
      }
    }
  }

  expect_failures = [
    var.services,
  ]
}

run "rejects_an_unsupported_service_scheme" {
  command = plan

  variables {
    services = {
      web = {
        hostname = "app.example.com"
        service  = "localhost:8080"
      }
    }
  }

  expect_failures = [
    var.services,
  ]
}

run "rejects_a_team_url_instead_of_a_team_name" {
  command = plan

  variables {
    team_name = "acme.cloudflareaccess.com"
  }

  expect_failures = [
    var.team_name,
  ]
}
