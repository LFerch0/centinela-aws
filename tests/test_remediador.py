"""Pruebas del remediador contra una cuenta de AWS simulada (moto)."""
import boto3
import pytest

from conftest import REGION, evento


def _un_ticket(aws):
    items = aws["tabla"].scan()["Items"]
    assert len(items) == 1, items
    return items[0]


def _grupo_abierto(puerto=22, cidr="0.0.0.0/0"):
    ec2 = boto3.client("ec2", region_name=REGION)
    vpc = ec2.create_vpc(CidrBlock="10.0.0.0/16")["Vpc"]["VpcId"]
    grupo = ec2.create_security_group(GroupName="prueba", Description="prueba", VpcId=vpc)["GroupId"]
    ec2.authorize_security_group_ingress(
        GroupId=grupo,
        IpPermissions=[{"IpProtocol": "tcp", "FromPort": puerto, "ToPort": puerto,
                        "IpRanges": [{"CidrIp": cidr}]}],
    )
    return ec2, grupo


def _reglas(ec2, grupo):
    return ec2.describe_security_groups(GroupIds=[grupo])["SecurityGroups"][0]["IpPermissions"]


# --- Security Groups ---------------------------------------------------------------

def test_cierra_ssh_abierto_a_internet(aws, remediador):
    ec2, grupo = _grupo_abierto(22)
    resultado = remediador.handler(evento("ec2.amazonaws.com", "AuthorizeSecurityGroupIngress",
                                          request={"groupId": grupo}), None)
    assert resultado["resultado"] == "REMEDIADO"
    assert _reglas(ec2, grupo) == []
    ticket = _un_ticket(aws)
    assert ticket["tipo"] == "SG_ABIERTO"
    assert ticket["remediado_automaticamente"] is True
    assert ticket["runbook"].endswith("RB-01-security-group-abierto.md")


def test_no_toca_https_abierto(aws, remediador):
    ec2, grupo = _grupo_abierto(443)
    resultado = remediador.handler(evento("ec2.amazonaws.com", "AuthorizeSecurityGroupIngress",
                                          request={"groupId": grupo}), None)
    assert resultado["resultado"] == "IGNORADO"
    assert len(_reglas(ec2, grupo)) == 1
    assert aws["tabla"].scan()["Items"] == []


def test_no_toca_ssh_desde_red_privada(aws, remediador):
    ec2, grupo = _grupo_abierto(22, cidr="10.0.0.0/8")
    resultado = remediador.handler(evento("ec2.amazonaws.com", "AuthorizeSecurityGroupIngress",
                                          request={"groupId": grupo}), None)
    assert resultado["resultado"] == "IGNORADO"
    assert len(_reglas(ec2, grupo)) == 1


def test_respeta_la_etiqueta_de_excepcion(aws, remediador):
    ec2, grupo = _grupo_abierto(3389)
    ec2.create_tags(Resources=[grupo], Tags=[{"Key": "centinela-excepcion", "Value": "true"}])
    resultado = remediador.handler(evento("ec2.amazonaws.com", "AuthorizeSecurityGroupIngress",
                                          request={"groupId": grupo}), None)
    assert resultado["resultado"] == "REQUIERE_REVISION"
    assert len(_reglas(ec2, grupo)) == 1


def test_ignora_sus_propias_acciones(aws, remediador):
    _, grupo = _grupo_abierto(22)
    identidad = {"type": "AssumedRole",
                 "sessionContext": {"sessionIssuer": {"userName": "centinela-remediador"}}}
    resultado = remediador.handler(evento("ec2.amazonaws.com", "AuthorizeSecurityGroupIngress",
                                          request={"groupId": grupo}, identidad=identidad), None)
    assert resultado["resultado"] == "IGNORADO"


def test_evento_repetido_no_duplica_el_ticket(aws, remediador):
    _, grupo = _grupo_abierto(22)
    ev = evento("ec2.amazonaws.com", "AuthorizeSecurityGroupIngress", request={"groupId": grupo})
    remediador.handler(ev, None)
    remediador.handler(ev, None)  # EventBridge entrega "al menos una vez"
    assert len(aws["tabla"].scan()["Items"]) == 1


# --- S3 ----------------------------------------------------------------------------

def test_reactiva_el_bloqueo_publico(aws, remediador):
    s3 = boto3.client("s3", region_name=REGION)
    s3.create_bucket(Bucket="bucket-prueba")
    resultado = remediador.handler(evento("s3.amazonaws.com", "DeleteBucketPublicAccessBlock",
                                          request={"bucketName": "bucket-prueba"}), None)
    assert resultado["resultado"] == "REMEDIADO"
    conf = s3.get_public_access_block(Bucket="bucket-prueba")["PublicAccessBlockConfiguration"]
    assert all(conf.values())


def test_bucket_protegido_no_es_incidente(aws, remediador):
    s3 = boto3.client("s3", region_name=REGION)
    s3.create_bucket(Bucket="bucket-prueba")
    s3.put_public_access_block(Bucket="bucket-prueba", PublicAccessBlockConfiguration={
        "BlockPublicAcls": True, "IgnorePublicAcls": True,
        "BlockPublicPolicy": True, "RestrictPublicBuckets": True})
    resultado = remediador.handler(evento("s3.amazonaws.com", "PutBucketPublicAccessBlock",
                                          request={"bucketName": "bucket-prueba"}), None)
    assert resultado["resultado"] == "IGNORADO"


# --- CloudTrail --------------------------------------------------------------------

def test_reactiva_cloudtrail(aws, remediador):
    boto3.client("s3", region_name=REGION).create_bucket(Bucket="trail-prueba")
    cloudtrail = boto3.client("cloudtrail", region_name=REGION)
    cloudtrail.create_trail(Name="centinela-trail", S3BucketName="trail-prueba")
    cloudtrail.start_logging(Name="centinela-trail")
    cloudtrail.stop_logging(Name="centinela-trail")

    resultado = remediador.handler(evento("cloudtrail.amazonaws.com", "StopLogging",
                                          request={"name": "centinela-trail"}), None)
    assert resultado["resultado"] == "REMEDIADO"
    assert cloudtrail.get_trail_status(Name="centinela-trail")["IsLogging"] is True
    assert _un_ticket(aws)["severidad"] == "CRITICA"


def test_fallo_de_remediacion_deja_ticket_y_lanza_error(aws, remediador):
    with pytest.raises(RuntimeError):
        remediador.handler(evento("cloudtrail.amazonaws.com", "StopLogging",
                                  request={"name": "trail-que-no-existe"}), None)
    assert _un_ticket(aws)["estado"] == "FALLO_REMEDIACION"


# --- Identidad ---------------------------------------------------------------------

def test_login_root_es_critico(aws, remediador):
    resultado = remediador.handler(evento(
        "signin.amazonaws.com", "ConsoleLogin",
        response={"ConsoleLogin": "Success"},
        identidad={"type": "Root", "arn": "arn:aws:iam::123456789012:root"},
        additionalEventData={"MFAUsed": "No"}), None)
    assert resultado["resultado"] == "REQUIERE_REVISION"
    ticket = _un_ticket(aws)
    assert ticket["tipo"] == "ROOT_LOGIN"
    assert "No" in ticket["detalle"]


def test_login_normal_no_es_incidente(aws, remediador):
    resultado = remediador.handler(evento("signin.amazonaws.com", "ConsoleLogin",
                                          response={"ConsoleLogin": "Success"}), None)
    assert resultado["resultado"] == "IGNORADO"


def test_login_fallido(aws, remediador):
    remediador.handler(evento("signin.amazonaws.com", "ConsoleLogin",
                              response={"ConsoleLogin": "Failure"},
                              errorMessage="Failed authentication"), None)
    assert _un_ticket(aws)["tipo"] == "LOGIN_FALLIDO"


def test_access_key_nueva(aws, remediador):
    remediador.handler(evento(
        "iam.amazonaws.com", "CreateAccessKey", request={"userName": "bot"},
        response={"accessKey": {"userName": "bot", "accessKeyId": "AKIAEJEMPLO"}}), None)
    assert "AKIAEJEMPLO" in _un_ticket(aws)["recurso"]


def test_evento_no_vigilado(aws, remediador):
    resultado = remediador.handler(evento("ec2.amazonaws.com", "RunInstances"), None)
    assert resultado["motivo"] == "evento no vigilado"  