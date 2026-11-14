# -----------------------------------------------------------------------------
# Fase 6: servidor sin puertos de entrada, administrado solo con Systems Manager.
# Se crea con crear_servidor = true. Gasta créditos mientras exista.
# -----------------------------------------------------------------------------

locals {
  servidor = var.crear_servidor ? 1 : 0
}

# --- Red: la VPC por defecto, en una sola zona --------------------------------

data "aws_vpc" "default" {
  count   = local.servidor
  default = true
}

data "aws_subnets" "default" {
  count = local.servidor
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
  filter {
    name   = "availability-zone"
    values = ["${local.region}a"]
  }
}

data "aws_ssm_parameter" "al2023" {
  count = local.servidor
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "servidor" {
  count       = local.servidor
  name        = "${local.nombre}-servidor"
  description = "Sin reglas de entrada: el acceso es solo por Session Manager"
  vpc_id      = data.aws_vpc.default[0].id

  egress {
    description = "HTTPS saliente: Systems Manager, CloudWatch y repositorios de paquetes"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Identidad de la instancia -------------------------------------------------

data "aws_iam_policy_document" "confianza_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "servidor" {
  count              = local.servidor
  name               = "${local.nombre}-servidor"
  assume_role_policy = data.aws_iam_policy_document.confianza_ec2.json
}

resource "aws_iam_role_policy_attachment" "servidor_ssm" {
  count      = local.servidor
  role       = aws_iam_role.servidor[0].name
  policy_arn = "arn:${local.particion}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "servidor_cloudwatch" {
  count      = local.servidor
  role       = aws_iam_role.servidor[0].name
  policy_arn = "arn:${local.particion}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "servidor" {
  count = local.servidor
  name  = "${local.nombre}-servidor"
  role  = aws_iam_role.servidor[0].name
}

# --- La instancia ---------------------------------------------------------------

resource "aws_instance" "servidor" {
  count                       = local.servidor
  ami                         = data.aws_ssm_parameter.al2023[0].value
  instance_type               = var.tipo_instancia
  subnet_id                   = sort(data.aws_subnets.default[0].ids)[0]
  vpc_security_group_ids      = [aws_security_group.servidor[0].id]
  iam_instance_profile        = aws_iam_instance_profile.servidor[0].name
  associate_public_ip_address = true # Sin NAT Gateway (USD 32/mes) necesita IP pública para salir
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required" # IMDSv2 obligatorio
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = false
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y nginx amazon-cloudwatch-agent
    systemctl enable --now nginx

    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'JSON'
    {
      "agent": { "metrics_collection_interval": 60, "omit_hostname": true },
      "metrics": {
        "namespace": "CWAgent",
        "append_dimensions": { "InstanceId": "$${aws:InstanceId}" },
        "metrics_collected": {
          "disk": { "measurement": ["used_percent"], "resources": ["/"], "drop_device": true },
          "mem": { "measurement": ["mem_used_percent"] }
        }
      }
    }
    JSON

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  EOF

  tags = {
    Name = "${local.nombre}-servidor"
  }
}

# --- Registro de sesiones ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "sesiones" {
  count             = local.servidor
  name              = "/${local.nombre}/sesiones"
  retention_in_days = var.dias_retencion_logs
}

resource "aws_ssm_document" "preferencias_sesion" {
  count           = local.servidor
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Preferencias de Session Manager: cada sesión se registra en CloudWatch Logs"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sesiones[0].name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      runAsEnabled                = false
      runAsDefaultUser            = ""
      kmsKeyId                    = ""
      shellProfile = {
        linux   = ""
        windows = ""
      }
    }
  })
}

# --- Runbooks ejecutables ---------------------------------------------------------

resource "aws_ssm_document" "diagnostico" {
  count           = local.servidor
  name            = "Centinela-Diagnostico"
  document_type   = "Command"
  document_format = "YAML"
  content         = <<-YAML
    schemaVersion: "2.2"
    description: "Diagnóstico rápido: carga, disco, memoria, servicios caídos y carpetas más pesadas."
    mainSteps:
      - action: aws:runShellScript
        name: diagnostico
        inputs:
          runCommand:
            - echo "== Carga =="; uptime
            - echo "== Disco =="; df -h /
            - echo "== Memoria =="; free -m
            - echo "== Servicios con fallas =="; systemctl --failed --no-pager || true
            - echo "== nginx =="; systemctl is-active nginx || true
            - echo "== Carpetas más pesadas =="; du -xh --max-depth=3 / 2>/dev/null | sort -rh | head -10
  YAML
}

resource "aws_ssm_document" "liberar_disco" {
  count           = local.servidor
  name            = "Centinela-LiberarDisco"
  document_type   = "Command"
  document_format = "YAML"
  content         = <<-YAML
    schemaVersion: "2.2"
    description: "Libera espacio: caché de paquetes, journal y archivos temporales antiguos."
    parameters:
      DiasAntiguedad:
        type: String
        default: "7"
        description: "Borra archivos de /tmp y /var/tmp con más de N días (0 = todos)."
        allowedPattern: "^[0-9]{1,3}$"
    mainSteps:
      - action: aws:runShellScript
        name: liberar
        inputs:
          runCommand:
            - echo "Antes:"; df -h /
            - dnf clean all
            - journalctl --vacuum-size=100M
            - find /tmp /var/tmp -xdev -type f -mmin +$(( {{ DiasAntiguedad }} * 1440 )) -print -delete
            - echo "Después:"; df -h /
  YAML
}

resource "aws_ssm_document" "reiniciar_servicio" {
  count           = local.servidor
  name            = "Centinela-ReiniciarServicio"
  document_type   = "Command"
  document_format = "YAML"
  content         = <<-YAML
    schemaVersion: "2.2"
    description: "Reinicia un servicio y muestra su estado. El nombre se valida para evitar inyección de comandos."
    parameters:
      Servicio:
        type: String
        default: nginx
        allowedPattern: "^[a-zA-Z0-9@._-]{1,64}$"
    mainSteps:
      - action: aws:runShellScript
        name: reiniciar
        inputs:
          runCommand:
            - systemctl restart {{ Servicio }}
            - sleep 2
            - systemctl is-active {{ Servicio }}
            - systemctl status {{ Servicio }} --no-pager
  YAML
}

# --- Parches e inventario (State Manager) ---------------------------------------

resource "aws_ssm_association" "escaneo_parches" {
  count               = local.servidor
  name                = "AWS-RunPatchBaseline"
  association_name    = "${local.nombre}-escaneo-parches"
  schedule_expression = "cron(0 3 ? * SUN *)"
  parameters = {
    Operation = "Scan"
  }
  targets {
    key    = "InstanceIds"
    values = [aws_instance.servidor[0].id]
  }
}

resource "aws_ssm_association" "inventario" {
  count               = local.servidor
  name                = "AWS-GatherSoftwareInventory"
  association_name    = "${local.nombre}-inventario"
  schedule_expression = "cron(0 2 ? * * *)"
  targets {
    key    = "InstanceIds"
    values = [aws_instance.servidor[0].id]
  }
}