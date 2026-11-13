# -----------------------------------------------------------------------------
# Alarmas y dashboard. La capa gratuita incluye 10 alarmas y 3 dashboards.
# Todas avisan al mismo tópico SNS que los incidentes.
# -----------------------------------------------------------------------------

locals {
  avisar = [aws_sns_topic.alertas.arn]
}

# --- Salud de Centinela ---------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "remediador_errores" {
  alarm_name          = "${local.nombre}-remediador-errores"
  alarm_description   = "El remediador falló: puede haber un incidente sin corregir. Revisa los logs y la cola de fallidos."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.remediador.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.avisar
  ok_actions          = local.avisar
}

resource "aws_cloudwatch_metric_alarm" "reporte_errores" {
  alarm_name          = "${local.nombre}-reporte-errores"
  alarm_description   = "El informe semanal no se pudo generar."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.reporte.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.avisar
}

resource "aws_cloudwatch_metric_alarm" "eventos_fallidos" {
  alarm_name          = "${local.nombre}-eventos-fallidos"
  alarm_description   = "Hay eventos de seguridad sin procesar en la cola de fallidos."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.fallidos.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.avisar
  ok_actions          = local.avisar
}

resource "aws_cloudwatch_metric_alarm" "incidente_critico" {
  alarm_name          = "${local.nombre}-incidente-critico"
  alarm_description   = "Se registró al menos un incidente CRÍTICO en los últimos 5 minutos."
  namespace           = "Centinela"
  metric_name         = "Incidentes"
  dimensions          = { Severidad = "CRITICA" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.avisar
  ok_actions          = local.avisar
}

# --- Salud del servidor (solo si existe) -----------------------------------------

resource "aws_cloudwatch_metric_alarm" "servidor_estado" {
  count               = local.servidor
  alarm_name          = "${local.nombre}-servidor-status-check"
  alarm_description   = "La instancia o el hardware que la aloja fallan el chequeo de estado. Ver RB-07."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.servidor[0].id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.avisar
  ok_actions          = local.avisar
}

resource "aws_cloudwatch_metric_alarm" "servidor_cpu" {
  count               = local.servidor
  alarm_name          = "${local.nombre}-servidor-cpu-alta"
  alarm_description   = "CPU sobre 80 % durante 10 minutos. Ver RB-07."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.servidor[0].id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.avisar
  ok_actions          = local.avisar
}

resource "aws_cloudwatch_metric_alarm" "servidor_disco" {
  count               = local.servidor
  alarm_name          = "${local.nombre}-servidor-disco-lleno"
  alarm_description   = "Disco raíz sobre 80 %. Ejecutar Centinela-LiberarDisco. Ver RB-07."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = aws_instance.servidor[0].id, path = "/", fstype = "xfs" }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.avisar
  ok_actions          = local.avisar
}

# --- Dashboard ----------------------------------------------------------------------

locals {
  widgets_base = [
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 12
      height = 6
      properties = {
        title   = "Incidentes por severidad"
        region  = local.region
        view    = "timeSeries"
        stacked = true
        stat    = "Sum"
        period  = 3600
        metrics = [
          ["Centinela", "Incidentes", "Severidad", "CRITICA"],
          ["Centinela", "Incidentes", "Severidad", "ALTA"],
          ["Centinela", "Incidentes", "Severidad", "MEDIA"],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 0
      width  = 12
      height = 6
      properties = {
        title   = "Tiempo de remediación (segundos)"
        region  = local.region
        view    = "timeSeries"
        stat    = "Average"
        period  = 3600
        metrics = [["Centinela", "TiempoRemediacionSegundos"]]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 12
      height = 6
      properties = {
        title  = "Remediador: invocaciones y errores"
        region = local.region
        view   = "timeSeries"
        stat   = "Sum"
        period = 300
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.remediador.function_name],
          ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.remediador.function_name],
        ]
      }
    },
    {
      type   = "alarm"
      x      = 12
      y      = 6
      width  = 12
      height = 6
      properties = {
        title = "Estado de las alarmas"
        alarms = concat(
          [
            aws_cloudwatch_metric_alarm.remediador_errores.arn,
            aws_cloudwatch_metric_alarm.reporte_errores.arn,
            aws_cloudwatch_metric_alarm.eventos_fallidos.arn,
            aws_cloudwatch_metric_alarm.incidente_critico.arn,
          ],
          aws_cloudwatch_metric_alarm.servidor_estado[*].arn,
          aws_cloudwatch_metric_alarm.servidor_cpu[*].arn,
          aws_cloudwatch_metric_alarm.servidor_disco[*].arn,
        )
      }
    },
  ]

  widgets_servidor = [
    for id in aws_instance.servidor[*].id : {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 24
      height = 6
      properties = {
        title  = "Servidor: CPU, disco y memoria (%)"
        region = local.region
        view   = "timeSeries"
        stat   = "Average"
        period = 300
        metrics = [
          ["AWS/EC2", "CPUUtilization", "InstanceId", id],
          ["CWAgent", "disk_used_percent", "InstanceId", id, "path", "/", "fstype", "xfs"],
          ["CWAgent", "mem_used_percent", "InstanceId", id],
        ]
      }
    }
  ]
}

resource "aws_cloudwatch_dashboard" "principal" {
  dashboard_name = local.nombre
  dashboard_body = jsonencode({ widgets = concat(local.widgets_base, local.widgets_servidor) })
}