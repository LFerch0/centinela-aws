resource "aws_dynamodb_table" "incidentes" {
  name = "${local.nombre}-incidentes"

  # Capacidad baja: entra en la capa siempre gratuita (25 RCU / 25 WCU)
  billing_mode   = "PROVISIONED"
  read_capacity  = 2
  write_capacity = 2

  # Solo se declara la clave. El resto de los atributos es libre.
  hash_key = "id"
  attribute {
    name = "id"
    type = "S"
  }

  # Cifrado en reposo con la clave propiedad de AWS (por defecto, sin costo).
  # Point-in-time recovery apagado: cobra por GB respaldado.
}

resource "aws_sns_topic" "alertas" {
  name = "${local.nombre}-alertas"
  # Sin cifrado KMS: las alarmas de CloudWatch no pueden publicar en un
  # tópico cifrado con aws/sns, y una clave propia cuesta USD 1/mes.
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.email_alertas
}