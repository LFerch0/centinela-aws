# RB-01 · Security Group abierto a internet

**Severidad:** ALTA · **MITRE ATT&CK:** T1562.007

## Qué significa

Una regla de entrada permitió un puerto sensible (SSH, RDP o una base de datos)
desde 0.0.0.0/0 o ::/0. Cualquier escáner de internet lo encuentra en minutos.

## Qué hizo Centinela

Revocó solo el origen público de la regla. Los orígenes privados se mantienen.
Si el grupo tiene la etiqueta `centinela-excepcion=true`, no lo tocó.

## Verificar

```bash
aws ec2 describe-security-groups --group-ids <sg-id> --query "SecurityGroups[0].IpPermissions"
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventId,AttributeValue=<evento_id>
```

## Investigar

1. ¿Quién fue (`actor`) y desde qué IP (`ip_origen`)? ¿Es una persona o un rol conocido?
2. ¿El grupo está asociado a instancias? `aws ec2 describe-network-interfaces --filters Name=group-id,Values=<sg-id>`
3. ¿El mismo actor hizo otros cambios en la última hora? Búscalo en CloudTrail por `Username`.

## Si el acceso era legítimo

- Para administrar servidores, usa Session Manager (Fase 6) en lugar de abrir el 22.
- Si de verdad se necesita, restringe a una IP concreta (`/32`), nunca a 0.0.0.0/0.
- Si debe quedar abierto, solicita la etiqueta de excepción con aprobación y regístrala.

## Escalar si

El actor es desconocido, la IP de origen no es de tu organización o hubo otros
cambios sospechosos del mismo actor.
