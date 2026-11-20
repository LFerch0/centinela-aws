# Decisiones de diseño

Cada decisión de este proyecto tuvo una alternativa. Este documento registra cuál
se eligió, cuál se descartó y por qué, para que cualquier persona que revise el
código pueda entender el criterio y discutirlo.

## Qué se corrige automáticamente

Una corrección automática solo se aplica si cumple tres condiciones: es
**reversible**, el cambio que corrige **rara vez es legítimo** y la corrección
**no puede romper un uso válido**.

| Incidente | ¿Automático? | Por qué |
|---|---|---|
| Security Group abierto a internet | Sí | Revocar una regla se deshace en segundos. Los casos legítimos usan la etiqueta `centinela-excepcion=true`. |
| Bucket sin bloqueo de acceso público | Sí | Reactivar el bloqueo es reversible. Un sitio estático debe servirse con CloudFront, no con un bucket público. |
| CloudTrail detenido | Sí | Detener el registro de auditoría nunca es una operación normal, y reactivarlo no rompe nada. |
| CloudTrail eliminado | No | Recrearlo desde la Lambda chocaría con Terraform, que es dueño del recurso. Se recrea con `terraform apply`. |
| Inicio de sesión con root | No | Un inicio de sesión no se puede deshacer, y puede ser el dueño legítimo. |
| Access key nueva | No | Desactivarla puede romper una automatización legítima. Lo decide una persona. |
| Inicio de sesión fallido | No | Un error de contraseña es normal. Bloquear al usuario podría dejar fuera al administrador. |

## Detección y respuesta

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| EventBridge sobre los eventos de CloudTrail | AWS Config o GuardDuty | Config cobra por cada cambio registrado y GuardDuty es de pago después de 30 días. Los eventos de CloudTrail en el bus por defecto de EventBridge son gratis. |
| La Lambda consulta el estado real del recurso | Interpretar `requestParameters` del evento | El formato de la solicitud cambia según cómo se llamó a la API. El estado real es la fuente fiable, y permite ignorar cambios no sensibles (por ejemplo, abrir el 443). |
| Se revoca solo el origen público de una regla | Borrar la regla completa | Si la regla también permite una red privada, ese acceso legítimo se conserva. |
| ID del ticket derivado del `eventID` de CloudTrail | UUID aleatorio | EventBridge entrega los eventos "al menos una vez". Con un ID determinista, un evento repetido sobrescribe el mismo ticket en vez de duplicarlo. |
| La Lambda ignora los eventos que genera su propio rol | Confiar solo en que el recurso ya esté corregido | Las correcciones de S3 generan eventos que coinciden con la regla. Hay dos barreras independientes contra el bucle: la identidad del autor y el estado del recurso. |
| Una sola Lambda con tabla de despacho | Una Lambda por detección | Un solo punto de registro, aviso y métricas. Agregar una detección es escribir una función y una fila. |
| El remediador lanza un error si la corrección falla | Registrar el fallo y terminar bien | El error activa los reintentos de Lambda, la alarma de errores y, al final, la cola de eventos fallidos. |
| Todo en `us-east-1` con un trail multirregión | Desplegar reglas en cada región | Los eventos de IAM y de inicio de sesión llegan a `us-east-1`. El trail registra todas las regiones, aunque la respuesta automática solo cubre esa (ver limitaciones en el README). |

## Datos, alertas y observabilidad

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| DynamoDB con capacidad aprovisionada (2 RCU / 2 WCU) | On-demand | La capacidad aprovisionada entra en la capa siempre gratuita; on-demand cobra por solicitud. El volumen de tickets es bajo. |
| `Scan` para el informe y las consultas | Índice secundario por estado | Con pocos tickets, un `Scan` es suficiente. Con millones, se agregaría un GSI. |
| Fechas en ISO 8601 y UTC | Fechas locales o timestamps numéricos | Se ordenan bien como texto, lo que permite filtrar por rango sin convertirlas. |
| Tópico SNS sin clave KMS propia | Cifrado con `aws/sns` o con una clave propia | Las alarmas de CloudWatch no pueden publicar en un tópico cifrado con `aws/sns`, y una clave propia cuesta USD 1 al mes. Los mensajes no contienen secretos. |
| Cola SQS para los dos caminos de fallo | Solo el DLQ del target de EventBridge | El DLQ de EventBridge solo recibe fallos de entrega. Los errores del código llegan por el destino `on_failure` de la invocación asíncrona. Se configuraron los dos. |
| Métricas con una sola dimensión (`Severidad`) | Dimensiones por recurso o por IP | Cada combinación de dimensiones es una métrica facturable. Los valores de alta cardinalidad van en el ticket, no en las métricas. |
| `treat_missing_data` según la métrica | El mismo valor para todas | Sin datos en `Errors` significa que no hubo invocaciones (sano). Sin datos en el disco significa que el agente dejó de reportar (no se asume sano). |
| Presupuesto sin restar créditos | Valor por defecto | Restando créditos, el gasto siempre se ve en USD 0 y el presupuesto nunca avisa. |
| Logs de las Lambdas con 14 días de retención | 1 año | Suficiente para investigar un incidente reciente sin acumular costo. |

## Servidor administrado

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| Session Manager | SSH con llave | Sin puertos de entrada, autenticación con IAM y MFA, y cada sesión registrada en CloudTrail y CloudWatch Logs. |
| IP pública sin reglas de entrada | NAT Gateway o VPC endpoints | NAT cuesta unos USD 32 al mes y cada endpoint unos USD 7. Sin reglas de entrada, la IP no expone ningún servicio. En producción se usaría una subred privada con endpoints. |
| IMDSv2 obligatorio con `hop_limit = 1` | IMDSv1 | Bloquea el robo de credenciales del rol por SSRF y desde contenedores. |
| Parámetros de los runbooks con `allowedPattern` | Parámetros libres | Los parámetros se sustituyen como texto en el script. La expresión regular impide la inyección de comandos antes de ejecutar nada. |
| Patch Manager en modo `Scan` | `Install` | `Install` puede reiniciar el servidor. En producción se programaría en una ventana de mantenimiento. |
| El servidor es opcional (`crear_servidor`) | Siempre encendido | Cuesta unos USD 12 al mes. Se enciende para practicar y se destruye al terminar. |

## Despliegue

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| Estado de Terraform en S3 con `use_lockfile` | Estado local, o S3 con tabla DynamoDB para el bloqueo | El estado debe ser compartido, duradero y bloqueable. El bloqueo nativo de S3 evita una tabla adicional. |
| GitHub Actions con OIDC | Access keys guardadas como secretos | No existe ninguna credencial de larga duración: cada job obtiene credenciales temporales de 1 hora. |
| Condición `sub` con los IDs numéricos del dueño y del repositorio | Condición solo con nombres, o `StringLike` con comodines | GitHub incluye los IDs inmutables en el token. Un nombre se puede reutilizar si se borra el repositorio; un ID no. |
| Dos roles: plan (solo lectura) y apply | Un solo rol | Si se compromete un pull request, el atacante solo puede leer. |
| Plan con `-lock=false` | Plan con bloqueo | El plan no escribe el estado, así que su rol solo necesita lectura. |
| `AdministratorAccess` en el rol de apply | Política de mínimo privilegio | Terraform crea roles y servicios muy variados. Riesgo aceptado, mitigado con OIDC, el environment `produccion` con aprobación humana y sesiones de 1 hora. |
| El plan del PR no se guarda como artefacto | Aplicar exactamente el plan del PR | El archivo del plan contiene valores sensibles en texto plano, y los artefactos de un repositorio público los puede descargar cualquier usuario de GitHub. |
| Solo el pipeline aplica cambios en `infra/` | Aplicar también desde la PC | Dos vías de despliegue con variables distintas se deshacen mutuamente. `bootstrap/` es la excepción, porque crea los roles que usa el pipeline. |
| Acciones fijadas por versión mayor, actualizadas con Dependabot agrupado | Fijar el hash del commit | Equilibrio entre seguridad de la cadena de suministro y mantenimiento. Cada actualización pasa por los mismos checks. |

## Análisis de seguridad (checkov)

checkov revisa el Terraform en cada pull request, incluidos los recursos
opcionales del servidor (con `--var-file infra/checkov.tfvars`, porque con
`count = 0` checkov no los evaluaba).

Se corrigieron 3 hallazgos: el versionado del bucket de CloudTrail y la limpieza
de versiones antiguas y subidas incompletas en los dos buckets. Las 26
excepciones restantes están justificadas una por una en `.checkov.yaml`:

| Categoría | Cantidad | Ejemplo |
|---|---|---|
| Requieren una clave KMS propia (USD 1/mes cada una) | 9 | Cifrado con CMK de DynamoDB, CloudTrail y los log groups |
| Costo desproporcionado para una sola cuenta | 9 | Replicación entre regiones de S3, retención de logs de 1 año |
| No aplican o son falsos positivos | 7 | Lambda en VPC; las t3 ya son *EBS optimized* |
| Riesgo aceptado y mitigado | 1 | `AdministratorAccess` en el rol de apply |
