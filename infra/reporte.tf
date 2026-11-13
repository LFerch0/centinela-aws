data "archive_file" "reporte" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/reporte"
  output_path = "${path.module}/.build/reporte.zip"
  excludes    = ["__pycache__"]
}

resource "aws_cloudwatch_log_group" "reporte" {
  name              = "/aws/lambda/${local.nombre}-reporte"
  retention_in_days = var.dias_retencion_logs
}

resource "aws_iam_role" "reporte" {
  name               = "${local.nombre}-reporte"
  description        = "Lee tickets y envía el informe semanal"
  assume_role_policy = data.aws_iam_policy_document.confianza_lambda.json
}

data "aws_iam_policy_document" "reporte" {
  statement {
    sid       = "EscribirLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.reporte.arn}:*"]
  }
  statement {
    sid       = "LeerTickets"
    actions   = ["dynamodb:Scan"]
    resources = [aws_dynamodb_table.incidentes.arn]
  }
  statement {
    sid       = "EnviarInforme"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alertas.arn]
  }
}

resource "aws_iam_role_policy" "reporte" {
  name   = "reporte"
  role   = aws_iam_role.reporte.id
  policy = data.aws_iam_policy_document.reporte.json
}

resource "aws_lambda_function" "reporte" {
  function_name    = "${local.nombre}-reporte"
  description      = "Centinela: informe semanal de incidentes"
  role             = aws_iam_role.reporte.arn
  runtime          = "python3.12"
  handler          = "app.handler"
  filename         = data.archive_file.reporte.output_path
  source_code_hash = data.archive_file.reporte.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      TABLA_INCIDENTES = aws_dynamodb_table.incidentes.name
      TOPICO_ALERTAS   = aws_sns_topic.alertas.arn
      DIAS_REPORTE     = "7"
    }
  }

  depends_on = [aws_cloudwatch_log_group.reporte, aws_iam_role_policy.reporte]
}

data "aws_iam_policy_document" "confianza_scheduler" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.cuenta]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.nombre}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.confianza_scheduler.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.reporte.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "invocar-reporte"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_scheduler_schedule" "reporte_semanal" {
  name                         = "${local.nombre}-reporte-semanal"
  description                  = "Informe de incidentes cada lunes a las 8:00"
  schedule_expression          = "cron(0 8 ? * MON *)"
  schedule_expression_timezone = "America/Bogota"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.reporte.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}