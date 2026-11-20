# Lecciones aprendidas

Los errores reales que encontré al construir Centinela, cómo los diagnostiqué y
qué aprendí de cada uno. Están ordenados de mayor a menor aprendizaje.

## 1. GitHub Actions no podía entrar a AWS

**Síntoma:** el job de plan fallaba después de 2 minutos de reintentos con
`Not authorized to perform sts:AssumeRoleWithWebIdentity`.

**Qué descarté:** el proveedor OIDC existía en la cuenta, el rol existía, su
condición tenía `repo:LFerch0/centinela-aws:pull_request` y el ARN configurado en
GitHub era correcto.

**Cómo lo diagnostiqué:** el mensaje de AWS es genérico a propósito: no dice qué
condición falló. Agregué un paso temporal al workflow que pedía un token OIDC y
decodificaba solo sus claims, sin imprimir el token completo, porque los logs de
un repositorio público son públicos.

**Causa:** GitHub envía el `sub` con los IDs numéricos del dueño y del
repositorio:

```
Esperado: repo:LFerch0/centinela-aws:pull_request
Real:     repo:LFerch0@141163398/centinela-aws@1454419262:pull_request
```

**Solución:** la política de confianza se construye con el nombre y el ID del
dueño y del repositorio. Después quité el paso de diagnóstico.

**Qué aprendí:** ante un error genérico, hay que dejar de suponer y mirar el dato
real. Además, los IDs existen por seguridad: un nombre de usuario o de
repositorio se puede reutilizar si se libera, y con el formato solo de nombres,
otra persona podría asumir mi rol. Un ID no se reutiliza nunca.

## 2. El análisis de seguridad salía en verde con un disco sin cifrar

**Síntoma:** al preparar una prueba para demostrar que el pipeline bloquea
configuraciones inseguras, cambié `encrypted = true` por `false` en el disco del
servidor. checkov respondió `Failed checks: 0`.

**Causa:** checkov evalúa las variables con sus valores por defecto.
`crear_servidor` vale `false`, así que todos los recursos del servidor tienen
`count = 0` y, para checkov, no existen. Cualquier error de seguridad en
`servidor.tf` habría pasado sin aviso.

**Solución:** un archivo `infra/checkov.tfvars` con `crear_servidor = true`, que
solo usa checkov (`--var-file`). Terraform no lo carga porque no se llama
`terraform.tfvars` ni termina en `.auto.tfvars`. Los checks que pasan subieron a
233, y el disco sin cifrar ahora falla con `CKV_AWS_8`.

**Qué aprendí:** un escáner en verde no significa "seguro", significa "no
encontré problemas en lo que revisé". Hay que comprobar que un control detecta lo
que debe detectar, no solo que pasa.

## 3. El gasto de la cuenta no cuadraba

**Síntoma:** el presupuesto mostraba USD 10,40 gastados en unos 9 días, cuando
Centinela con el servidor de prácticas debía costar menos de USD 1.

**Cómo lo diagnostiqué:** revisé la factura del mes desglosada por servicio y
región en la consola de facturación.

**Causa:** USD 9,60 (el 92 %) eran de una base de datos RDS con MySQL 8.0, creada
durante una actividad de créditos al inicio y ajena al proyecto. La instancia
costó solo USD 0,70 por 43,8 horas. Los otros USD 8,76 eran **RDS Extended
Support**: MySQL 8.0 ya terminó su soporte estándar, y RDS cobra un recargo de
USD 0,10 por vCPU y hora. Para una instancia de 2 vCPU, el recargo era 12 veces
el costo de la instancia.

**Solución:** confirmé que la base de datos ya no existía y que no quedaban
instancias, discos, IPs, NAT Gateways ni copias de seguridad en ninguna región.

**Qué aprendí:** al crear una base de datos hay que elegir una versión del motor
con soporte estándar vigente. Y el desglose por servicio es la primera
herramienta ante un gasto inesperado: el problema casi nunca está donde uno
supone.

## 4. Los tiempos de la demo eran todos iguales

**Síntoma:** el simulador de ataques mostraba que las cuatro detecciones se
resolvían en exactamente 15 segundos.

**Causa:** un error de medición. El cronómetro empezaba antes del primer ataque,
crear los cuatro ataques tomaba unos 15 segundos y el script revisaba el estado
cada 15 segundos. Cuando hizo la primera revisión, todo estaba corregido: 15 s
era solo un límite superior.

**Solución:** cada ataque guarda su propio momento de inicio y el script revisa
cada 3 segundos. Para los resultados uso el tiempo que registra cada ticket,
desde el evento de CloudTrail hasta la corrección. Con 7 corridas, las medianas
son 3 s (CloudTrail), 5 s (Security Group) y 7 s (S3).

**Qué aprendí:** antes de publicar un número hay que entender qué mide
exactamente. Los tiempos reales eran mejores que los que mostraba la demo.

## 5. GitHub Actions no arrancaba en un repositorio público

**Síntoma:** el workflow terminaba con *Startup failure* y el mensaje "recent
account payments have failed or your spending limit needs to be increased", aunque
el repositorio era público y no tenía pagos pendientes.

**Causa:** la cuenta de GitHub tenía presupuestos en USD 0 con la opción *Stop
usage when budget limit is reached*, y el bloqueo afectaba también a Actions en
un repositorio público, donde el uso no se cobra.

**Solución:** desmarcar esa opción en el presupuesto de Actions, manteniendo el
monto en USD 0. Sin un método de pago registrado, GitHub no puede cobrar nada.

**Qué aprendí:** un mensaje de error puede describir mal la causa. El texto
hablaba de pagos fallidos; el problema real era una regla de bloqueo.

## 6. Archivos que no debían estar en el repositorio

**Síntoma:** al revisar el commit antes de abrir un pull request, encontré un
ejecutable (`agg`) y la grabación cruda de la demo (`demo.cast`) versionados.

**Causa:** `git add .` agrega todo lo que no esté en `.gitignore`.

**Solución:** `git rm --cached` para dejar de versionarlos sin borrarlos del
disco, y las reglas correspondientes en `.gitignore`. Como el pull request se
fusionó con un merge commit y no con squash, quedaron en la historia de `main`.
No contenían nada sensible, así que no reescribí la historia; desde entonces el
repositorio solo permite squash.

**Qué aprendí:** revisar `git status` y el contenido del commit antes de cada
push, sobre todo en un repositorio público.
