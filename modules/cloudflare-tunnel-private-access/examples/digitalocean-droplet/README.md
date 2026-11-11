# Example: a DigitalOcean droplet with no inbound firewall rules

Creates a droplet whose firewall has no inbound rules, and publishes a web
application and SSH on it through a Cloudflare Tunnel. Both require a login
that matches the allow-list.

```sh
export CLOUDFLARE_API_TOKEN=...
export DIGITALOCEAN_TOKEN=...
terraform init
terraform apply -var-file=example.tfvars
```

Then add the `ssh_config` output to `~/.ssh/config` and connect:

```sh
ssh root@ssh.example.com
```

The example expects an application listening on `localhost:8080` on the
droplet. Until one runs there, the web hostname answers with a 502 after login.
