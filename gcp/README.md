# clickops-detector for GCP

Alerts you when someone changes a GCP project by hand instead of through your pipeline.

English | [Portuguese](README-pt-br.md)

## What it does

Every write in the Console goes through the API, and the API records it in the Cloud Audit
Log. This module turns those entries into a metric and alerts when the count goes above zero:

```
Console click → API call → Admin Activity log → log-based metric → Slack or email alert
```

The alert includes the principal, service, method, and resource. It reads Admin Activity,
which is enabled by default and has no ingestion cost.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

For Slack, create a Slack app with the `chat:write` scope, install it, invite it to the
channel, and pass its bot token as an environment variable before `terraform apply`:

```bash
export TF_VAR_slack_auth_token="xoxb-..."
```

For email, Google sends a verification email to the notification channel. Confirm it before
testing.

To test, change something in the Console, wait a few minutes, and check Slack or your inbox. The
counter is in Monitoring → Metrics Explorer under
`logging.googleapis.com/user/clickops_count`.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| google | ~> 6.0 |

## Inputs

| Name | Description | Type |
|---|---|---|
| `project_id` | Project to watch | `string` |
| `alert_email` | Where the alert lands by email. Optional | `string` |
| `slack_channel` | Slack channel for the alert, e.g. `#clickops`. Optional | `string` |
| `slack_auth_token` | Slack bot token with `chat:write`. Sensitive, pass as `TF_VAR_slack_auth_token` | `string` |

## Resources

| Resource | Purpose |
|---|---|
| `google_logging_metric.clickops` | Counts human writes in the audit log |
| `google_monitoring_alert_policy.clickops` | Fires when the count is above zero |
| `google_monitoring_notification_channel.email` | Delivers the alert by email, if `alert_email` is set |
| `google_monitoring_notification_channel.slack` | Delivers the alert to Slack, if `slack_channel` is set |

## The filter

| Line | Drops |
|---|---|
| `logName=".../cloudaudit.googleapis.com%2Factivity"` | Everything outside Admin Activity |
| `principalEmail=~".+@.+"` | Principals with no email address |
| `NOT principalEmail=~"gserviceaccount.com$"` | Service accounts: Terraform, CI/CD, controllers |
| `NOT principalEmail=~"^system:"` | Kubernetes and GKE internal principals |
| `NOT serviceName="geminicloudassist.googleapis.com"` | Gemini Cloud Assist investigations, which emit writes without changing anything |
| `NOT methodName="io.k8s.core.v1.services.proxy.create"` | Kubernetes Service proxy connections, logged as creates |
| `NOT request."@type"="...SqlVerifyEligibilityRequest"` | Cloud SQL eligibility checks, logged as `cloudsql.instances.create` |
| `NOT methodName="cloudsql.instances.connect"` | Cloud SQL connections, which only issue an ephemeral certificate |
| `NOT methodName=~".*\.selfsubject[a-z]*\.create$"` | Self subject reviews, which report the caller's own permissions |
| `NOT methodName=~".*\.(get\|list\|watch)$"` | Reads, lowercase k8s convention |
| `NOT methodName=~".*\.(Get\|List\|Watch)[A-Za-z0-9]+$"` | Reads, CamelCase Google API convention |

The Logging query language accepts `--` comments, so `main.tf` documents each exclusion
inline.

Expect to add entries. Every exclusion below the read filters came from a false positive
found in production.

## Notes

- The metric is not retroactive. It counts what arrives after the apply.
- The `%2F` in `logName` is an escaped slash. A literal `/` returns nothing.
- Data Access logs are out of scope: disabled by default, high volume, and not required here.
- `duration = "0s"` with `alignment_period = "900s"` gives the log 15 minutes to arrive while
  still firing on a single event.
- `notification_prompts = ["OPENED"]` stops Cloud Monitoring from sending a second
  notification when the incident closes.
- `evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"` closes the incident once the
  window has no new logs. Without it, the incident stays open for up to seven days, and the
  same principal repeating the same change on the same resource does not alert again.
- The alert goes to Slack or email through Cloud Monitoring. Routing it to Grafana,
  PagerDuty, or another observability tool is out of scope here. Replace the notification channel with the
  one your setup uses.
