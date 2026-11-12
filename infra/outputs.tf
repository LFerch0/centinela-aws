output "tabla_incidentes" {
  description = "Tabla DynamoDB con los tickets"
  value       = aws_dynamodb_table.incidentes.name
}

output "topico_alertas_arn" {
  description = "ARN del tópico SNS de alertas"
  value       = aws_sns_topic.alertas.arn
}