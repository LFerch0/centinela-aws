# RB-03 · CloudTrail detenido o eliminado

**Severidad:** CRÍTICA · **MITRE ATT&CK:** T1562.008

## Qué significa

Alguien intentó dejar la cuenta sin registro de auditoría. Suele ser el paso
previo a otras acciones que el atacante no quiere que queden registradas.

## Qué hizo Centinela

- StopLogging: reactivó el registro con StartLogging.
- DeleteTrail: nada automático. Recréalo con `terraform apply` en `infra/`.

## Verificar

```bash
aws cloudtrail get-trail-status --name centinela-trail --query IsLogging
```

## Investigar

1. Calcula la ventana ciega: desde `detectado_en` hasta la reactivación.
2. Revisa en el Event history de CloudTrail lo que hizo el mismo actor en las horas previas.
3. Trata las credenciales del actor como comprometidas hasta que se demuestre lo contrario.

## Escalar siempre

Detener CloudTrail no es una operación normal en ningún caso.
