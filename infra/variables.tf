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