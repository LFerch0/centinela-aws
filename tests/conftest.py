"""Fixtures compartidas: una cuenta de AWS simulada en memoria con moto."""
import importlib.util
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

RAIZ = Path(__file__).resolve().parent.parent
REGION = "us-east-1"
TABLA = "centinela-incidentes"


def _importar(nombre, ruta):
    """Importa un app.py desde cero. Las Lambdas leen variables de entorno y crean
    clientes de boto3 al importarse, así que cada prueba necesita su propia copia,
    creada DENTRO de la cuenta simulada."""
    spec = importlib.util.spec_from_file_location(nombre, ruta)
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


@pytest.fixture
def aws(monkeypatch):
    # Credenciales falsas: si moto fallara, boto3 nunca podría tocar una cuenta real.
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", REGION)

    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name=REGION)
        dynamodb.create_table(
            TableName=TABLA,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        topico = boto3.client("sns", region_name=REGION).create_topic(Name="centinela-alertas")["TopicArn"]

        monkeypatch.setenv("TABLA_INCIDENTES", TABLA)
        monkeypatch.setenv("TOPICO_ALERTAS", topico)
        monkeypatch.setenv("URL_RUNBOOKS", "https://github.com/usuario/centinela-aws/blob/main/runbooks")
        monkeypatch.setenv("PUERTOS_SENSIBLES", "22,3389,3306")
        monkeypatch.setenv("NOMBRE_ROL_REMEDIADOR", "centinela-remediador")

        yield {"tabla": dynamodb.Table(TABLA)}


@pytest.fixture
def remediador(aws):
    return _importar("remediador", RAIZ / "lambdas" / "remediador" / "app.py")


@pytest.fixture
def reporte(aws):
    return _importar("reporte", RAIZ / "lambdas" / "reporte" / "app.py")


def evento(fuente, nombre, request=None, response=None, identidad=None, **extra):
    """Arma un evento con la misma forma que entrega EventBridge."""
    detalle = {
        "eventTime": "2026-11-13T15:00:00Z",
        "eventSource": fuente,
        "eventName": nombre,
        "awsRegion": REGION,
        "sourceIPAddress": "203.0.113.10",
        "eventID": "a1b2c3d4-0000-1111-2222-333344445555",
        "userIdentity": identidad or {
            "type": "IAMUser",
            "arn": "arn:aws:iam::123456789012:user/ana",
            "userName": "ana",
        },
        "requestParameters": request,
        "responseElements": response,
    }
    detalle.update(extra)
    return {"detail-type": "AWS API Call via CloudTrail", "detail": detalle}