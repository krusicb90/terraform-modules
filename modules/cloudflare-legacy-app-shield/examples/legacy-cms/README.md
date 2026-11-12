# Example: shielding a legacy CMS

Puts the editor area of a content management system behind a login, blocks two
endpoints the public site does not need, and rate limits the login page. The
site must already be proxied through Cloudflare.

```sh
export CLOUDFLARE_API_TOKEN=...
terraform init
terraform apply -var-file=example.tfvars
```
