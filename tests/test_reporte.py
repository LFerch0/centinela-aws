"""Pruebas del informe semanal."""
from datetime import datetime, timedelta, timezone


def test_informe_cuenta_solo_la_ultima_semana(aws, reporte):
    ahora = datetime.now(timezone.utc)
    hace_un_dia = (ahora - timedelta(days=1)).isoformat(timespec="seconds")
    hace_un_mes = (ahora - timedelta(days=30)).isoformat(timespec="seconds")
    for item in [
        {"id": "INC-1", "severidad": "ALTA", "estado": "REMEDIADO", "remediado_automaticamente": True,
         "segundos_hasta_respuesta": 40, "registrado_en": hace_un_dia},
        {"id": "INC-2", "severidad": "CRITICA", "estado": "REQUIERE_REVISION",
         "remediado_automaticamente": False, "segundos_hasta_respuesta": 20, "registrado_en": hace_un_dia},
        {"id": "INC-0", "severidad": "ALTA", "estado": "CERRADO", "remediado_automaticamente": False,
         "segundos_hasta_respuesta": 10, "registrado_en": hace_un_mes},
    ]:
        aws["tabla"].put_item(Item=item)

    assert reporte.handler({}, None) == {"incidentes": 2, "pendientes": 1}


def test_informe_vacio(reporte):
    asunto, cuerpo = reporte.construir_informe([], [], 7)
    assert "0 incidentes" in asunto
    assert "sin datos" in cuerpo