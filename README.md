# clickops-detector

Alerts you when someone changes cloud infrastructure by hand instead of through your pipeline.

[Português](README-pt-br.md)

Manual changes in a cloud console never reach your state file. The console is an API client,
though, and every write it makes lands in the audit log. This turns those entries into a
metric and alerts on them, with the name of the person and the resource they touched.

## Providers

| Provider | Status |
|---|---|
| [GCP](gcp/) | Available |

## Scope

Detection, not prevention. It reports manual changes so you can decide whether each one
becomes code or a documented exception.
