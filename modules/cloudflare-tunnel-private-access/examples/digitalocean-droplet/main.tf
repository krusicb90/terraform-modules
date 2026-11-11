# A DigitalOcean droplet with no inbound firewall rules at all.
#
# A web application and SSH are reachable only through a Cloudflare Tunnel, and
# only after a login that matches the allow-list. The droplet opens outbound
# connections to Cloudflare and accepts none from the internet.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.0.0, < 6.0.0"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = ">= 2.40.0"
    }
  }
}

# Credentials come from CLOUDFLARE_API_TOKEN and DIGITALOCEAN_TOKEN.
provider "cloudflare" {}

provider "digitalocean" {}

module "private_access" {
  source = "../../"

  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  team_name  = var.cloudflare_team_name
  name       = "app-server"

  services = {
    web = {
      hostname = "app.${var.domain}"
      service  = "http://localhost:8080"
    }
    ssh = {
      hostname = "ssh.${var.domain}"
      service  = "ssh://localhost:22"
      type     = "ssh"
    }
  }

  allowed_emails = var.allowed_emails
}

resource "digitalocean_droplet" "app" {
  # checkov:skip=CKV_DIO_2: SSH keys are passed in through var.ssh_key_fingerprints, which a static scan cannot resolve.
  name      = "app-server"
  region    = var.region
  size      = "s-1vcpu-1gb"
  image     = "ubuntu-24-04-x64"
  ssh_keys  = var.ssh_key_fingerprints
  user_data = module.private_access.cloud_init
}

resource "digitalocean_firewall" "app" {
  name        = "app-server-no-inbound"
  droplet_ids = [digitalocean_droplet.app.id]

  # There is no inbound_rule block. Nothing on the internet can open a
  # connection to this droplet, including to port 22.

  # cloudflared connects to the Cloudflare edge on 7844 (QUIC, with HTTP/2 as
  # the fallback).
  outbound_rule {
    protocol              = "udp"
    port_range            = "7844"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "7844"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Package installation and the Cloudflare API.
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
