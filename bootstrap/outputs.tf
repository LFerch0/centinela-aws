output "bucket_estado" {
  description = "Nombre del bucket para el backend de infra/"
  value       = aws_s3_bucket.estado.bucket
}