terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

# Counts every write a human makes in the audit log.
resource "google_logging_metric" "clickops" {
  name        = "clickops_count"
  description = "Changes made by human principals outside the IaC pipeline."

  filter = <<-EOT
    logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
    protoPayload.authenticationInfo.principalEmail=~".+@.+"
    NOT protoPayload.authenticationInfo.principalEmail=~"gserviceaccount.com$"
    NOT protoPayload.authenticationInfo.principalEmail=~"^system:"
    -- False positives
    -- Gemini Cloud Assist investigations emit write events without production changes.
    NOT protoPayload.serviceName="geminicloudassist.googleapis.com"
    -- Kubernetes Service proxy connections are logged as create actions without resource changes.
    NOT protoPayload.methodName="io.k8s.core.v1.services.proxy.create"
    -- Cloud SQL eligibility checks are logged as cloudsql.instances.create without creating an instance.
    NOT protoPayload.request."@type"="type.googleapis.com/google.cloud.sql.v1.SqlVerifyEligibilityRequest"
    -- Cloud SQL connection events only issue ephemeral certificates and do not change instance configuration.
    NOT protoPayload.methodName="cloudsql.instances.connect"
    -- Self subject reviews report the caller's own permissions and change nothing.
    NOT protoPayload.methodName=~".*\.selfsubject[a-z]*\.create$"
    -- Reads
    NOT protoPayload.methodName=~".*\.(get|list|watch)$"
    NOT protoPayload.methodName=~".*\.(Get|List|Watch)[A-Za-z0-9]+$"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key        = "principal"
      value_type = "STRING"
    }
    labels {
      key        = "service"
      value_type = "STRING"
    }
    labels {
      key        = "method"
      value_type = "STRING"
    }
    labels {
      key        = "resource"
      value_type = "STRING"
    }
  }

  label_extractors = {
    principal = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
    service   = "EXTRACT(protoPayload.serviceName)"
    method    = "EXTRACT(protoPayload.methodName)"
    resource  = "EXTRACT(protoPayload.resourceName)"
  }
}

# Fires when that count goes above zero.
resource "google_monitoring_alert_policy" "clickops" {
  display_name = "ClickOps detected"
  combiner     = "OR"

  conditions {
    display_name = "Manual change in ${var.project_id}"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.clickops.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      # Closes the incident once the window has no new logs, so the next identical change
      # opens a new one. The default keeps it open for up to seven days and stays silent.
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"

      aggregations {
        alignment_period     = "900s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "resource.label.project_id",
          "metric.label.principal",
          "metric.label.service",
          "metric.label.method",
          "metric.label.resource",
        ]
      }
    }
  }

  notification_channels = concat(
    google_monitoring_notification_channel.email[*].id,
    google_monitoring_notification_channel.slack[*].id,
  )

  alert_strategy {
    # Notify only when the incident opens.
    notification_prompts = ["OPENED"]
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      Someone changed this project by hand, outside the pipeline.

      Principal: $${metric.label.principal}
      Service:   $${metric.label.service}
      Method:    $${metric.label.method}
      Resource:  $${metric.label.resource}
    EOT
  }
}

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email == null ? 0 : 1
  display_name = "ClickOps alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_notification_channel" "slack" {
  count        = var.slack_channel == null ? 0 : 1
  display_name = "ClickOps alerts (Slack)"
  type         = "slack"

  labels = {
    channel_name = var.slack_channel
  }

  sensitive_labels {
    auth_token = var.slack_auth_token
  }
}

# The email channel used to be a single resource. Keeps existing installs from recreating it.
moved {
  from = google_monitoring_notification_channel.email
  to   = google_monitoring_notification_channel.email[0]
}
