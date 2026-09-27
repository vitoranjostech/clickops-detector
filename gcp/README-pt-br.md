# clickops-detector para GCP

Avisa quando alguém altera um projeto GCP na mão em vez de pelo pipeline.

[English](README.md) | Português

## O que faz

Toda escrita no Console passa pela API, e a API registra isso no Cloud Audit Log. Este
módulo transforma essas entradas em métrica e alerta quando a contagem passa de zero:

```
clique no Console → chamada de API → Admin Activity log → log-based metric → alerta no Slack ou por e-mail
```

O alerta traz o principal, o serviço, o método e o recurso. Usa o Admin Activity, que vem
habilitado por padrão e não tem custo de ingestão.

## Como usar

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Para o Slack, crie um app do Slack com o escopo `chat:write`, instale, convide o app no canal
e passe o bot token por variável de ambiente antes do `terraform apply`:

```bash
export TF_VAR_slack_auth_token="xoxb-..."
```

Para e-mail, o Google manda um e-mail de verificação para o canal de notificação. Confirme
antes de testar.

Para testar, altere algo no Console, espere alguns minutos e veja o Slack ou sua caixa de entrada. O
contador fica em Monitoring → Metrics Explorer, em
`logging.googleapis.com/user/clickops_count`.

## Requisitos

| Nome | Versão |
|---|---|
| terraform | >= 1.5 |
| google | ~> 6.0 |

## Inputs

| Nome | Descrição | Tipo |
|---|---|---|
| `project_id` | Projeto a monitorar | `string` |
| `alert_email` | Onde o alerta chega por e-mail. Opcional | `string` |
| `slack_channel` | Canal do Slack para o alerta, ex.: `#clickops`. Opcional | `string` |
| `slack_auth_token` | Bot token do Slack com `chat:write`. Sensível, passe como `TF_VAR_slack_auth_token` | `string` |

## Recursos

| Recurso | Função |
|---|---|
| `google_logging_metric.clickops` | Conta escritas humanas no audit log |
| `google_monitoring_alert_policy.clickops` | Dispara quando a contagem passa de zero |
| `google_monitoring_notification_channel.email` | Entrega o alerta por e-mail, se `alert_email` estiver definido |
| `google_monitoring_notification_channel.slack` | Entrega o alerta no Slack, se `slack_channel` estiver definido |

## O filtro

| Linha | Remove |
|---|---|
| `logName=".../cloudaudit.googleapis.com%2Factivity"` | Tudo que não é Admin Activity |
| `principalEmail=~".+@.+"` | Principals sem endereço de e-mail |
| `NOT principalEmail=~"gserviceaccount.com$"` | Service accounts: Terraform, CI/CD, controllers |
| `NOT principalEmail=~"^system:"` | Principals internos do Kubernetes e do GKE |
| `NOT serviceName="geminicloudassist.googleapis.com"` | Investigações do Gemini Cloud Assist, que emitem escrita sem alterar nada |
| `NOT methodName="io.k8s.core.v1.services.proxy.create"` | Conexões de proxy de Service do Kubernetes, logadas como create |
| `NOT request."@type"="...SqlVerifyEligibilityRequest"` | Checagens de elegibilidade do Cloud SQL, logadas como `cloudsql.instances.create` |
| `NOT methodName="cloudsql.instances.connect"` | Conexões ao Cloud SQL, que só emitem um certificado efêmero |
| `NOT methodName=~".*\.selfsubject[a-z]*\.create$"` | Self subject reviews, que reportam as permissões do próprio chamador |
| `NOT methodName=~".*\.(get\|list\|watch)$"` | Leituras, convenção k8s em minúsculo |
| `NOT methodName=~".*\.(Get\|List\|Watch)[A-Za-z0-9]+$"` | Leituras, convenção CamelCase das APIs Google |

A query language do Logging aceita comentários com `--`, então o `main.tf` documenta cada
exclusão inline.

Espere adicionar entradas. Toda exclusão abaixo dos filtros de leitura veio de um falso
positivo encontrado em produção.

## Notas

- A métrica não retroage. Ela conta o que chegar depois do apply.
- O `%2F` no `logName` é a barra escapada. Uma `/` literal não devolve nada.
- Data Access fica fora do escopo: desligado por padrão, volume alto e não necessário aqui.
- `duration = "0s"` com `alignment_period = "900s"` dá 15 minutos para o log chegar sem
  deixar de disparar num evento único.
- `notification_prompts = ["OPENED"]` impede o Cloud Monitoring de mandar uma segunda
  notificação quando o incidente fecha.
- `evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"` fecha o incidente quando a
  janela fica sem log novo. Sem isso, o incidente fica aberto por até sete dias, e a mesma
  pessoa repetindo a mesma mudança no mesmo recurso não gera alerta de novo.
- O alerta vai para o Slack ou por e-mail via Cloud Monitoring. Encaminhar para Grafana,
  PagerDuty ou outra ferramenta de observabilidade está fora do escopo aqui. Troque o canal de notificação pelo
  que o seu setup usa.
