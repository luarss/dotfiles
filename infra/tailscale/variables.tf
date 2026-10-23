variable "owner_email" {
  type        = string
  description = "Login email of the only user allowed to reach the work machine."
}

variable "allowed_ports" {
  type        = list(string)
  description = "Ports the owner may reach on their own devices."
  default     = ["tcp:5900"]
}

variable "key_expiry_days" {
  type        = number
  description = "Days before a device key expires and re-authentication is required."
  default     = 90
}
