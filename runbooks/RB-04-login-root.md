# RB-04 · Inicio de sesión con la cuenta root

**Severidad:** CRÍTICA · **MITRE ATT&CK:** T1078.004

## Qué significa

Alguien entró con root, la identidad que no tiene restricciones de IAM.

## Investigar

1. Confirma con el dueño de la cuenta que fue él, y por qué usó root.
2. Revisa `MFA usado` en el ticket. Un "No" exige activar MFA de inmediato.
3. Revisa en CloudTrail lo que se hizo durante esa sesión (`userIdentity.type = Root`).

## Si NO fue el dueño

1. Cambia la contraseña de root y vuelve a registrar el MFA.
2. Revisa los usuarios IAM, las access keys y la facturación por si hubo cambios.
3. Abre un caso con AWS Support.

## Tareas que sí requieren root

Cambiar el plan de soporte, cerrar la cuenta y algunos ajustes de facturación.
Para todo lo demás se usa un usuario IAM.
