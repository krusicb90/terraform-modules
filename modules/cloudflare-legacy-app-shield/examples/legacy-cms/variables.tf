variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "ID of the Cloudflare zone that serves the site."
  type        = string
}

variable "hostname" {
  description = "Public hostname of the site, for example www.example.com."
  type        = string
}

variable "editor_emails" {
  description = "Email addresses of the people who may reach the editor area."
  type        = list(string)
}
