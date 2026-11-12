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