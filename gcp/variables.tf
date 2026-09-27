variable "project_id" {
  description = "Project to watch."
  type        = string
}

variable "alert_email" {
  description = "Where the alert lands by email. Leave null to skip email."
  type        = string
  default     = null
}

variable "slack_channel" {
  description = "Slack channel for the alert, e.g. \"#clickops\". Leave null to skip Slack."
  type        = string
  default     = null
}

variable "slack_auth_token" {
  description = "Slack bot token with chat:write. Pass it as TF_VAR_slack_auth_token, never in a file."
  type        = string
  default     = null
  sensitive   = true
}
