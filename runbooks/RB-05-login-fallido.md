# RB-05 · Inicio de sesión fallido en la consola

**Severidad:** MEDIA · **MITRE ATT&CK:** T1110

## Qué significa

Un intento de entrar a la consola falló. Un fallo aislado suele ser un error de
contraseña. Muchos desde la misma IP sugieren fuerza bruta.

## Investigar

1. ¿Cuántos intentos hubo desde `ip_origen` en la última hora?
   `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=ConsoleLogin`
2. Si el usuario aparece como HIDDEN_DUE_TO_SECURITY_REASONS, se probó un nombre que no existe.
3. ¿Hubo después un login exitoso desde la misma IP? Eso es mucho más grave: escala.

## Cerrar

Si el usuario confirma que se equivocó de contraseña, cierra el ticket con esa nota.
