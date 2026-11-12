# RB-02 · Bucket S3 sin bloqueo de acceso público

**Severidad:** ALTA · **MITRE ATT&CK:** T1530

## Qué significa

Se desactivó al menos uno de los 4 ajustes de Block Public Access de un bucket.
El bucket queda a una política o ACL de exponer sus datos.

## Qué hizo Centinela

Reactivó los 4 ajustes, salvo que el bucket tenga `centinela-excepcion=true`.

## Verificar

```bash
aws s3api get-public-access-block --bucket <bucket>
aws s3api get-bucket-policy-status --bucket <bucket>
```

## Investigar

1. ¿Alguien leyó objetos mientras estuvo expuesto? Para saberlo necesitas eventos
   de datos de S3 o server access logs. Este proyecto no los activa, por costo.
2. ¿Qué contiene el bucket? Si hay datos personales o credenciales, escala.
3. ¿El mismo actor cambió también la política del bucket?

## Si era legítimo (por ejemplo, un sitio web estático)

Sirve el sitio con CloudFront y Origin Access Control, sin abrir el bucket. Si de
verdad debe ser público, aplica la etiqueta de excepción con aprobación.
