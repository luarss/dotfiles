resource "tailscale_acl" "owner_only" {
  overwrite_existing_content = true

  acl = jsonencode({
    grants = [
      {
        src = [var.owner_email]
        dst = ["autogroup:self"]
        ip  = var.allowed_ports
      }
    ]
  })
}

resource "tailscale_tailnet_settings" "hardening" {
  devices_approval_on                         = true
  devices_auto_updates_on                     = true
  devices_key_duration_days                   = var.key_expiry_days
  users_role_allowed_to_join_external_tailnet = "none"
}
