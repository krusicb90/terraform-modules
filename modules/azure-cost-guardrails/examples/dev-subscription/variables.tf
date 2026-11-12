variable "subscription_id" {
  description = "ID of the development subscription, as a GUID."
  type        = string
}

variable "monitoring_resource_group_name" {
  description = "Existing resource group for the action group."
  type        = string
}

variable "contact_emails" {
  description = "Email addresses that receive the notifications."
  type        = list(string)
}

variable "team_a_resource_group_id" {
  description = "Resource ID of the resource group that gets its own budget."
  type        = string
}

variable "sandbox_resource_group_id" {
  description = "Resource ID of the resource group in which VM sizes are limited."
  type        = string
}

variable "build_agent_vm_id" {
  description = "Resource ID of the virtual machine to shut down every evening."
  type        = string
}

variable "location" {
  description = "Region of the virtual machine."
  type        = string
  default     = "westeurope"
}
