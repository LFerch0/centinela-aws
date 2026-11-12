# RB-06 · Access key nueva creada

**Severidad:** MEDIA · **MITRE ATT&CK:** T1098.001

## Qué significa

Se creó una credencial que no vence. Es una técnica común de persistencia tras
un acceso inicial.

## Investigar

1. ¿Quién la creó (`actor`) y para qué usuario (`recurso`)? ¿Lo pidió alguien?
2. ¿Se puede usar un rol IAM en su lugar? Para EC2, Lambda y GitHub Actions, siempre.
3. ¿Ya se usó? `aws iam get-access-key-last-used --access-key-id <id>`

## Si no está justificada

```bash
aws iam update-access-key --user-name <usuario> --access-key-id <id> --status Inactive
```

Desactívala primero en vez de borrarla: si algo deja de funcionar, la reactivas.
Bórrala cuando confirmes que nadie la necesita.
