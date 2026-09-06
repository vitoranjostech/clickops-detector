# clickops-detector

Avisa quando alguém altera infraestrutura na mão em vez de pelo pipeline.

[Inglês](README.md) | Português

Alteração manual no console nunca chega ao seu state file. Mas o console é um cliente da API,
e toda escrita que ele faz cai no audit log. Isso transforma essas entradas em métrica e
alerta em cima delas, com o nome da pessoa e o recurso que ela mexeu.

Reporta as alterações manuais para você decidir se cada uma vira código ou exceção
documentada. Bloquear é tarefa de Org Policy, IAM e deny policies.

## Providers

| Provider | Status |
|---|---|
| [GCP](gcp/) | Disponível |
