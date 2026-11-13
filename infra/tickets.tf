resource "aws_dynamodb_table" "incidentes" {
  name = "${local.nombre}-incidentes"

  billing_mode   = "PROVISIONED"
  read_capacity  = 2
  write_capacity = 2

  hash_key = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_sns_topic" "alertas" {
  name = "${local.nombre}-alertas"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.email_alertas
}
resource "aws_sqs_queue" "fallidos" {
  name                      = "${local.nombre}-eventos-fallidos"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

data "aws_iam_policy_document" "fallidos" {
  statement {
    sid       = "EventBridgeEnviaFallidos"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.fallidos.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.particion}:events:${local.region}:${local.cuenta}:rule/${local.nombre}-*"]
    }
  }
}

resource "aws_sqs_queue_policy" "fallidos" {
  queue_url = aws_sqs_queue.fallidos.id
  policy    = data.aws_iam_policy_document.fallidos.json
}