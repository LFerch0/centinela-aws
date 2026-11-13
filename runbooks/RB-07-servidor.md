# RB-07 · Problemas en el servidor

**Acceso:** solo Session Manager. Nunca se abre el puerto 22.

## Diagnóstico inicial (siempre primero)

```bash
aws ssm send-command --instance-ids <id> --document-name Centinela-Diagnostico
```

## Disco lleno (alarma: centinela-servidor-disco-lleno)

1. Ejecuta el diagnóstico y revisa "Carpetas más pesadas".
2. Si el espacio está en caché, logs o temporales:
   `--document-name Centinela-LiberarDisco --parameters DiasAntiguedad=7`
3. Si son datos de la aplicación, no los borres: escala para ampliar el volumen.

## Servicio caído

1. Revisa en el diagnóstico la sección "Servicios con fallas".
2. `--document-name Centinela-ReiniciarServicio --parameters Servicio=<nombre>`
3. Si vuelve a caerse, entra con Session Manager y revisa `journalctl -u <servicio> -n 100`.

## CPU alta (alarma: centinela-servidor-cpu-alta)

1. Entra con Session Manager y ejecuta `top -o %CPU`.
2. Un proceso desconocido consumiendo CPU puede ser minería de criptomonedas:
   trátalo como un incidente de seguridad y no lo detengas sin preservar evidencia.

## La instancia no aparece en Systems Manager

- ¿Está encendida? `aws ec2 describe-instance-status --instance-ids <id>`
- ¿Tiene el instance profile con AmazonSSMManagedInstanceCore?
- ¿El Security Group permite la salida por 443?
