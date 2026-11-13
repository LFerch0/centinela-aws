variable "region" {
  description = "Región de AWS. En us-east-1 llegan los eventos de IAM y de inicio de sesión."
  type        = string
  default     = "us-east-1"
}

variable "proyecto" {
  description = "Nombre del proyecto para las etiquetas."
  type        = string
  default     = "centinela-aws"
}

variable "email_alertas" {
  description = "Correo que recibe las alertas de Centinela."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.email_alertas))
    error_message = "Escribe un correo válido."
  }
}

variable "url_repositorio" {
  description = "URL de tu repositorio, para enlazar los runbooks en cada alerta."
  type        = string
  default     = ""
}

variable "puertos_sensibles" {
  description = "Puertos que nunca deben quedar abiertos a 0.0.0.0/0 ni ::/0."
  type        = list(number)
  default     = [22, 3389, 3306, 5432, 1433, 27017]
}

variable "dias_retencion_logs" {
  description = "Días que se guardan los logs de las Lambdas."
  type        = number
  default     = 14
}

variable "crear_servidor" {
  description = "Crea la EC2 administrada con Systems Manager. Gasta créditos mientras exista."
  type        = bool
  default     = false
}

variable "tipo_instancia" {
  description = "Tipo de instancia del servidor."
  type        = string
  default     = "t3.micro"
}