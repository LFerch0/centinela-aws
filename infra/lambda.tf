# Solo el servicio Lambda, y solo para esta cuenta, puede asumir el rol
data "aws_iam_policy_document" "confianza_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.cuenta]
    }
  }
}

# Empaqueta la carpeta en un zip. Si cambias el código, cambia el hash
# y Terraform vuelve a subir la función.
data "archive_file" "remediador" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/remediador"
  output_path = "${path.module}/.build/remediador.zip"
  excludes    = ["__pycache__"]
}

resource "aws_cloudwatch_log_group" "remediador" {
  name              = "/aws/lambda/${local.nombre}-remediador"
  retention_in_days = var.dias_retencion_logs
}

resource "aws_iam_role" "remediador" {
  name               = "${local.nombre}-remediador"
  description        = "Permisos mínimos para detectar, corregir y registrar incidentes"
  assume_role_policy = data.aws_iam_policy_document.confianza_lambda.json
}

data "aws_iam_policy_document" "remediador" {
  statement {
    sid       = "EscribirLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.remediador.arn}:*"]
  }
  statement {
    sid       = "RegistrarTickets"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.incidentes.arn]
  }
  statement {
    sid       = "EnviarAlertas"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alertas.arn]
  }
  statement {
    sid       = "LeerSecurityGroups"
    actions   = ["ec2:DescribeSecurityGroups"]
    resources = ["*"] # Las acciones Describe de EC2 no admiten restricción por recurso
  }
  statement {
    sid       = "CerrarSecurityGroups"
    actions   = ["ec2:RevokeSecurityGroupIngress"]
    resources = ["arn:${local.particion}:ec2:*:${local.cuenta}:security-group/*"]
  }
}

resource "aws_iam_role_policy" "remediador" {
  name   = "remediador"
  role   = aws_iam_role.remediador.id
  policy = data.aws_iam_policy_document.remediador.json
}

resource "aws_lambda_function" "remediador" {
  function_name    = "${local.nombre}-remediador"
  description      = "Centinela: detección y respuesta automática a incidentes"
  role             = aws_iam_role.remediador.arn
  runtime          = "python3.12"
  handler          = "app.handler" # archivo app.py, función handler
  filename         = data.archive_file.remediador.output_path
  source_code_hash = data.archive_file.remediador.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      TABLA_INCIDENTES      = aws_dynamodb_table.incidentes.name
      TOPICO_ALERTAS        = aws_sns_topic.alertas.arn
      URL_RUNBOOKS          = var.url_repositorio == "" ? "" : "${trimsuffix(var.url_repositorio, "/")}/blob/main/runbooks"
      PUERTOS_SENSIBLES     = join(",", var.puertos_sensibles)
      NOMBRE_ROL_REMEDIADOR = aws_iam_role.remediador.name
    }
  }

  # El grupo de logs y los permisos deben existir antes de la primera ejecución
  depends_on = [aws_cloudwatch_log_group.remediador, aws_iam_role_policy.remediador]
}