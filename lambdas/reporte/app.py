"""Centinela: informe semanal de incidentes, enviado por SNS."""
import os
from collections import Counter
from datetime import datetime, timedelta, timezone

import boto3

PENDIENTES = ("REQUIERE_REVISION", "FALLO_REMEDIACION")


def _escanear(tabla):
    """Scan paginado: DynamoDB devuelve como máximo 1 MB por llamada."""
    items, kwargs = [], {}
    while True:
        respuesta = tabla.scan(**kwargs)
        items.extend(respuesta.get("Items", []))
        if "LastEvaluatedKey" not in respuesta:
            return items
        kwargs["ExclusiveStartKey"] = respuesta["LastEvaluatedKey"]


def _conteo(titulo, conteo):
    lineas = [titulo]
    if not conteo:
        return lineas + ["  (ninguno)"]
    for clave, cantidad in conteo.most_common():
        lineas.append(f"  {clave:<40} {cantidad:>4}")
    return lineas


def construir_informe(recientes, pendientes, dias):
    ahora = datetime.now(timezone.utc)
    automaticos = [int(i.get("segundos_hasta_respuesta", 0))
                   for i in recientes if i.get("remediado_automaticamente")]
    mttr = f"{sum(automaticos) / len(automaticos):.0f} s" if automaticos else "sin datos"
    tasa = f"{100 * len(automaticos) / len(recientes):.0f} %" if recientes else "sin datos"

    lineas = [
        f"Informe de Centinela: últimos {dias} días (generado {ahora:%Y-%m-%d %H:%M} UTC)",
        "",
        f"Incidentes detectados:            {len(recientes)}",
        f"Remediados automáticamente:       {len(automaticos)} ({tasa})",
        f"Tiempo medio de respuesta (MTTR): {mttr}",
        f"Tickets pendientes (total):       {len(pendientes)}",
        "",
    ]
    lineas += _conteo("Por severidad:", Counter(i.get("severidad", "?") for i in recientes))
    lineas.append("")
    lineas += _conteo("Por tipo:", Counter(i.get("titulo", i.get("tipo", "?")) for i in recientes))
    lineas += ["", "Pendientes de revisión humana:"]
    if not pendientes:
        lineas.append("  (ninguno)")
    for i in sorted(pendientes, key=lambda x: x.get("registrado_en", ""), reverse=True):
        lineas.append(f"  {i.get('id')}  [{i.get('severidad')}]  {i.get('titulo', i.get('tipo'))}  -  {i.get('recurso')}")

    asunto = f"[Centinela] Informe semanal: {len(recientes)} incidentes, {len(pendientes)} pendientes"
    return asunto, "\n".join(lineas)


def handler(event, context):
    dias = int(os.environ.get("DIAS_REPORTE", "7"))
    tabla = boto3.resource("dynamodb").Table(os.environ["TABLA_INCIDENTES"])
    desde = (datetime.now(timezone.utc) - timedelta(days=dias)).isoformat(timespec="seconds")

    items = _escanear(tabla)
    recientes = [i for i in items if i.get("registrado_en", "") >= desde]
    pendientes = [i for i in items if i.get("estado") in PENDIENTES]

    asunto, cuerpo = construir_informe(recientes, pendientes, dias)
    boto3.client("sns").publish(TopicArn=os.environ["TOPICO_ALERTAS"], Subject=asunto[:99], Message=cuerpo)
    return {"incidentes": len(recientes), "pendientes": len(pendientes)}