"""Centinela: detección y respuesta automática a incidentes."""
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(logging.INFO)

ETIQUETA_EXCEPCION = "centinela-excepcion"

TITULOS = {
    "SG_ABIERTO": "Security Group abierto a internet",
    "S3_PUBLICO": "Bucket S3 sin bloqueo de acceso público",
    "CLOUDTRAIL_DETENIDO": "CloudTrail detenido",
    "CLOUDTRAIL_ELIMINADO": "CloudTrail eliminado",
    "ROOT_LOGIN": "Inicio de sesión con la cuenta root",
    "LOGIN_FALLIDO": "Inicio de sesión fallido en la consola",
    "ACCESS_KEY_CREADA": "Access key nueva creada",
}
MITRE = {
    "SG_ABIERTO": "T1562.007 Impair Defenses: Disable or Modify Cloud Firewall",
    "S3_PUBLICO": "T1530 Data from Cloud Storage",
    "CLOUDTRAIL_DETENIDO": "T1562.008 Impair Defenses: Disable or Modify Cloud Logs",
    "CLOUDTRAIL_ELIMINADO": "T1562.008 Impair Defenses: Disable or Modify Cloud Logs",
    "ROOT_LOGIN": "T1078.004 Valid Accounts: Cloud Accounts",
    "LOGIN_FALLIDO": "T1110 Brute Force",
    "ACCESS_KEY_CREADA": "T1098.001 Account Manipulation: Additional Cloud Credentials",
}
RUNBOOKS = {
    "SG_ABIERTO": "RB-01-security-group-abierto.md",
    "S3_PUBLICO": "RB-02-bucket-publico.md",
    "CLOUDTRAIL_DETENIDO": "RB-03-cloudtrail.md",
    "CLOUDTRAIL_ELIMINADO": "RB-03-cloudtrail.md",
    "ROOT_LOGIN": "RB-04-login-root.md",
    "LOGIN_FALLIDO": "RB-05-login-fallido.md",
    "ACCESS_KEY_CREADA": "RB-06-access-key-nueva.md",
}
# Fuera del handler: se ejecuta una vez por entorno y se reutiliza
# en las invocaciones siguientes (warm start).
TABLA = boto3.resource("dynamodb").Table(os.environ["TABLA_INCIDENTES"])
SNS = boto3.client("sns")
EC2 = boto3.client("ec2")

S3 = boto3.client("s3")
CLOUDTRAIL = boto3.client("cloudtrail")
CLAVES_BPA = ("BlockPublicAcls", "IgnorePublicAcls", "BlockPublicPolicy", "RestrictPublicBuckets")

TOPICO = os.environ["TOPICO_ALERTAS"]
URL_RUNBOOKS = os.environ.get("URL_RUNBOOKS", "").rstrip("/")
PUERTOS = [int(p) for p in os.environ["PUERTOS_SENSIBLES"].split(",")]
ROL_PROPIO = os.environ["NOMBRE_ROL_REMEDIADOR"]


# ---------------------------------------------------------------- utilidades

def _iso(momento):
    return momento.astimezone(timezone.utc).isoformat(timespec="seconds")


def _fecha(texto):
    try:
        return datetime.fromisoformat(texto.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None


def _codigo(error):
    return error.response.get("Error", {}).get("Code", "Desconocido")


def _tiene_excepcion(etiquetas):
    return any(e.get("Key") == ETIQUETA_EXCEPCION and str(e.get("Value")).lower() == "true"
               for e in etiquetas or [])


def nuevo_ticket(detalle, tipo, severidad, estado, recurso, accion, extra=""):
    ahora = datetime.now(timezone.utc)
    hora_evento = _fecha(detalle.get("eventTime")) or ahora
    ident = detalle.get("userIdentity") or {}
    evento_id = detalle.get("eventID") or uuid.uuid4().hex
    runbook = RUNBOOKS[tipo]
    return {
        # Derivado del eventID: si el evento llega dos veces, se sobrescribe
        # el mismo ticket en lugar de crear otro (idempotencia).
        "id": f"INC-{hora_evento:%Y%m%d}-{evento_id.replace('-', '')[:8].upper()}",
        "tipo": tipo,
        "titulo": TITULOS[tipo],
        "severidad": severidad,
        "estado": estado,
        "remediado_automaticamente": estado == "REMEDIADO",
        "recurso": recurso,
        "accion": accion,
        "detalle": extra,
        "actor": ident.get("arn") or ident.get("userName") or ident.get("type", "desconocido"),
        "ip_origen": detalle.get("sourceIPAddress", ""),
        "evento": detalle.get("eventName", ""),
        "evento_id": evento_id,
        "mitre": MITRE[tipo],
        "runbook": f"{URL_RUNBOOKS}/{runbook}" if URL_RUNBOOKS else runbook,
        "detectado_en": _iso(hora_evento),
        "registrado_en": _iso(ahora),
        "segundos_hasta_respuesta": int(max(0, (ahora - hora_evento).total_seconds())),
    }


# ------------------------------------------------------- detector: Security Group

def reglas_abiertas(grupo):
    """Reglas de entrada que exponen un puerto sensible a todo internet."""
    for permiso in grupo.get("IpPermissions", []):
        protocolo = permiso["IpProtocol"]
        todos = protocolo == "-1"
        desde, hasta = permiso.get("FromPort"), permiso.get("ToPort")
        expone = todos or (desde is not None and any(desde <= p <= hasta for p in PUERTOS))
        if not expone:
            continue
        v4 = any(r.get("CidrIp") == "0.0.0.0/0" for r in permiso.get("IpRanges", []))
        v6 = any(r.get("CidrIpv6") == "::/0" for r in permiso.get("Ipv6Ranges", []))
        if not (v4 or v6):
            continue
        # Se revoca solo el origen público: si la regla también permite 10.0.0.0/8, eso queda.
        regla = {"IpProtocol": protocolo}
        if not todos:
            regla["FromPort"], regla["ToPort"] = desde, hasta
        if v4:
            regla["IpRanges"] = [{"CidrIp": "0.0.0.0/0"}]
        if v6:
            regla["Ipv6Ranges"] = [{"CidrIpv6": "::/0"}]
        yield regla


def describir(regla):
    if regla["IpProtocol"] == "-1":
        puertos = "todos los puertos"
    elif regla["FromPort"] == regla["ToPort"]:
        puertos = f"{regla['IpProtocol']}/{regla['FromPort']}"
    else:
        puertos = f"{regla['IpProtocol']}/{regla['FromPort']}-{regla['ToPort']}"
    origenes = [r["CidrIp"] for r in regla.get("IpRanges", [])] + \
               [r["CidrIpv6"] for r in regla.get("Ipv6Ranges", [])]
    return f"{puertos} desde {' y '.join(origenes)}"


def detectar_security_group(detalle):
    req = detalle.get("requestParameters") or {}
    grupo_id = req.get("groupId") or (req.get("ModifySecurityGroupRulesRequest") or {}).get("GroupId")
    if not grupo_id:
        return nuevo_ticket(detalle, "SG_ABIERTO", "ALTA", "REQUIERE_REVISION",
                            req.get("groupName", "desconocido"),
                            "No se pudo identificar el ID del grupo; revisar manualmente.")
    try:
        # Se consulta el estado REAL del grupo en vez de confiar en la solicitud.
        grupo = EC2.describe_security_groups(GroupIds=[grupo_id])["SecurityGroups"][0]
    except ClientError as error:
        if _codigo(error) == "InvalidGroup.NotFound":
            return None  # Lo borraron antes de que llegáramos.
        raise

    abiertas = list(reglas_abiertas(grupo))
    if not abiertas:
        return None  # Se abrió algo no sensible (por ejemplo, 443): no es incidente.

    recurso = f"{grupo_id} ({grupo.get('GroupName', '')})"
    resumen = "; ".join(describir(r) for r in abiertas)

    if _tiene_excepcion(grupo.get("Tags")):
        return nuevo_ticket(detalle, "SG_ABIERTO", "ALTA", "REQUIERE_REVISION", recurso,
                            f"Tiene la etiqueta {ETIQUETA_EXCEPCION}=true; no se modificó.",
                            f"Reglas expuestas: {resumen}")
    try:
        EC2.revoke_security_group_ingress(GroupId=grupo_id, IpPermissions=abiertas)
    except ClientError as error:
        return nuevo_ticket(detalle, "SG_ABIERTO", "ALTA", "FALLO_REMEDIACION", recurso,
                            f"No se pudieron revocar las reglas ({_codigo(error)}).",
                            f"Reglas expuestas: {resumen}")
    return nuevo_ticket(detalle, "SG_ABIERTO", "ALTA", "REMEDIADO", recurso,
                        f"Se revocaron las reglas: {resumen}")


# Tabla de despacho: (servicio, evento) -> detector. En la Fase 4 agregas filas.
# ------------------------------------------------------------- detector: S3

def detectar_bucket(detalle):
    bucket = (detalle.get("requestParameters") or {}).get("bucketName")
    if not bucket:
        return None
    try:
        conf = S3.get_public_access_block(Bucket=bucket)["PublicAccessBlockConfiguration"]
    except ClientError as error:
        codigo = _codigo(error)
        if codigo == "NoSuchPublicAccessBlockConfiguration":
            conf = {}  # Sin configuración = los 4 ajustes desactivados
        elif codigo == "NoSuchBucket":
            return None
        else:
            raise

    desactivados = [c for c in CLAVES_BPA if not conf.get(c)]
    if not desactivados:
        return None  # Sigue protegido (incluye nuestra propia corrección)

    try:
        etiquetas = S3.get_bucket_tagging(Bucket=bucket).get("TagSet", [])
    except ClientError:
        etiquetas = []  # NoSuchTagSet: el bucket no tiene etiquetas

    resumen = f"Ajustes desactivados: {', '.join(desactivados)}"
    if _tiene_excepcion(etiquetas):
        return nuevo_ticket(detalle, "S3_PUBLICO", "ALTA", "REQUIERE_REVISION", bucket,
                            f"Tiene la etiqueta {ETIQUETA_EXCEPCION}=true; no se modificó.", resumen)
    try:
        S3.put_public_access_block(
            Bucket=bucket,
            PublicAccessBlockConfiguration={c: True for c in CLAVES_BPA},
        )
    except ClientError as error:
        return nuevo_ticket(detalle, "S3_PUBLICO", "ALTA", "FALLO_REMEDIACION", bucket,
                            f"No se pudo reactivar el bloqueo ({_codigo(error)}).", resumen)
    return nuevo_ticket(detalle, "S3_PUBLICO", "ALTA", "REMEDIADO", bucket,
                        "Se reactivaron los 4 ajustes de Block Public Access.", resumen)


# ------------------------------------------------------- detector: CloudTrail

def detectar_trail_detenido(detalle):
    nombre = (detalle.get("requestParameters") or {}).get("name", "desconocido")
    try:
        CLOUDTRAIL.start_logging(Name=nombre)  # Acepta nombre o ARN
    except ClientError as error:
        return nuevo_ticket(detalle, "CLOUDTRAIL_DETENIDO", "CRITICA", "FALLO_REMEDIACION", nombre,
                            f"No se pudo reactivar el registro ({_codigo(error)}).")
    return nuevo_ticket(detalle, "CLOUDTRAIL_DETENIDO", "CRITICA", "REMEDIADO", nombre,
                        "Se reactivó el registro con StartLogging.")


def detectar_trail_eliminado(detalle):
    nombre = (detalle.get("requestParameters") or {}).get("name", "desconocido")
    return nuevo_ticket(detalle, "CLOUDTRAIL_ELIMINADO", "CRITICA", "REQUIERE_REVISION", nombre,
                        "No se recrea automáticamente: ejecutar terraform apply.")


# ------------------------------------------------------- detector: identidad

def detectar_login(detalle):
    resultado = (detalle.get("responseElements") or {}).get("ConsoleLogin")
    ident = detalle.get("userIdentity") or {}
    if resultado == "Failure":
        usuario = ident.get("userName") or ident.get("arn") or "desconocido"
        return nuevo_ticket(detalle, "LOGIN_FALLIDO", "MEDIA", "REQUIERE_REVISION", usuario,
                            "Revisar si hay más intentos desde la misma IP.",
                            f"Motivo: {detalle.get('errorMessage', 'sin detalle')}")
    if ident.get("type") == "Root":
        mfa = (detalle.get("additionalEventData") or {}).get("MFAUsed", "desconocido")
        return nuevo_ticket(detalle, "ROOT_LOGIN", "CRITICA", "REQUIERE_REVISION", "cuenta root",
                            "Confirmar con el dueño de la cuenta que el acceso fue legítimo.",
                            f"MFA usado: {mfa}")
    return None  # Login normal de un usuario IAM


def detectar_access_key(detalle):
    llave = (detalle.get("responseElements") or {}).get("accessKey") or {}
    usuario = llave.get("userName") or (detalle.get("requestParameters") or {}).get("userName", "desconocido")
    return nuevo_ticket(detalle, "ACCESS_KEY_CREADA", "MEDIA", "REQUIERE_REVISION",
                        f"{usuario} ({llave.get('accessKeyId', 'sin id')})",
                        "Confirmar que la llave es necesaria; preferir roles IAM.")
DETECTORES = {
    ("ec2.amazonaws.com", "AuthorizeSecurityGroupIngress"): detectar_security_group,
    ("ec2.amazonaws.com", "ModifySecurityGroupRules"): detectar_security_group,
    ("s3.amazonaws.com", "DeleteBucketPublicAccessBlock"): detectar_bucket,
    ("s3.amazonaws.com", "PutBucketPublicAccessBlock"): detectar_bucket,
    ("s3.amazonaws.com", "PutBucketPolicy"): detectar_bucket,
    ("s3.amazonaws.com", "PutBucketAcl"): detectar_bucket,
    ("cloudtrail.amazonaws.com", "StopLogging"): detectar_trail_detenido,
    ("cloudtrail.amazonaws.com", "DeleteTrail"): detectar_trail_eliminado,
    ("signin.amazonaws.com", "ConsoleLogin"): detectar_login,
    ("iam.amazonaws.com", "CreateAccessKey"): detectar_access_key,
}


# ------------------------------------------------------------ registro y aviso

def notificar(t):
    asunto = f"[Centinela][{t['severidad']}] {t['titulo']} - {t['estado']}"
    cuerpo = "\n".join([
        f"Ticket:       {t['id']}",
        f"Estado:       {t['estado']}",
        f"Recurso:      {t['recurso']}",
        f"Acción:       {t['accion']}",
        f"Detalle:      {t['detalle'] or '-'}",
        "",
        f"Quién:        {t['actor']}",
        f"Desde IP:     {t['ip_origen']}",
        f"Evento:       {t['evento']} ({t['evento_id']})",
        f"Detectado:    {t['detectado_en']}",
        f"Respuesta en: {t['segundos_hasta_respuesta']} s",
        f"MITRE ATT&CK: {t['mitre']}",
        "",
        f"Runbook: {t['runbook']}",
    ])
    SNS.publish(TopicArn=TOPICO, Subject=asunto[:99], Message=cuerpo)


def es_accion_propia(detalle):
    emisor = ((detalle.get("userIdentity") or {}).get("sessionContext") or {}) \
        .get("sessionIssuer", {}).get("userName")
    return emisor == ROL_PROPIO


def handler(event, context):
    detalle = event.get("detail") or {}
    clave = (detalle.get("eventSource", ""), detalle.get("eventName", ""))

    if es_accion_propia(detalle):
        log.info("Ignorado: %s lo hizo el propio Centinela", clave[1])
        return {"resultado": "IGNORADO", "motivo": "acción propia"}

    detector = DETECTORES.get(clave)
    if detector is None:
        log.info("Ignorado: evento no vigilado %s", clave)
        return {"resultado": "IGNORADO", "motivo": "evento no vigilado"}

    ticket = detector(detalle)
    if ticket is None:
        log.info("Sin incidente para %s", clave[1])
        return {"resultado": "IGNORADO", "motivo": "no es incidente"}

    TABLA.put_item(Item=ticket)
    notificar(ticket)
    log.info("Ticket %s: %s %s", ticket["id"], ticket["tipo"], ticket["estado"])

    if ticket["estado"] == "FALLO_REMEDIACION":
        # Se lanza a propósito: Lambda reintenta y la alarma de errores se activa (Fase 7).
        raise RuntimeError(f"Falló la remediación de {ticket['id']}")
    return {"resultado": ticket["estado"], "ticket": ticket["id"]}