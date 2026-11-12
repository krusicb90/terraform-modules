# A content management system that can no longer be upgraded.
#
# The editor area requires a login, two endpoints the site does not need are
# blocked for everyone, and the login page is rate limited. Nothing changes on
# the server itself.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

# Credentials come from CLOUDFLARE_API_TOKEN.
provider "cloudflare" {}

module "shield" {
  source = "../../"

  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  name       = "legacy-cms"
  hostname   = var.hostname

  protected_paths = ["/admin", "/cms/editor"]
  allowed_emails  = var.editor_emails

  blocked_paths = [
    "/reports/export.ashx",
    "/upload/handler.axd",
  ]

  rate_limit = {
    paths               = ["/login"]
    requests_per_period = 20
  }
}
