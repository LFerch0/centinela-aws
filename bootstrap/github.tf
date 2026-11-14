# -----------------------------------------------------------------------------
# Identidad de GitHub Actions en AWS, sin access keys.
#   - Proveedor OIDC: AWS confía en los tokens que firma GitHub.
#   - Rol de plan: solo lectura, para los pull requests.
#   - Rol de apply: solo para el environment "produccion" (con aprobación).
# -----------------------------------------------------------------------------

variable "github_repo" {
  description = "Repositorio en formato usuario/repositorio, exactamente como aparece en GitHub."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "Usa el formato usuario/repositorio, sin https://github.com/."
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS ya no usa estas huellas para validar a GitHub, pero el campo se acepta.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# --- Rol de plan ---------------------------------------------------------------

data "aws_iam_policy_document" "confianza_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Sin esta condición, CUALQUIER repositorio de GitHub podría asumir el rol.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "leer_estado" {
  statement {
    sid       = "ListarBucketEstado"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.estado.arn]
  }
  statement {
    sid       = "LeerEstado"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.estado.arn}/*"]
  }
}

resource "aws_iam_role" "github_plan" {
  name                 = "centinela-github-plan"
  description          = "GitHub Actions: terraform plan en pull requests (solo lectura)"
  assume_role_policy   = data.aws_iam_policy_document.confianza_plan.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_lectura" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_estado" {
  name   = "leer-estado-terraform"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.leer_estado.json
}

# --- Rol de apply ----------------------------------------------------------------

data "aws_iam_policy_document" "confianza_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:produccion"]
    }
  }
}

resource "aws_iam_role" "github_apply" {
  name                 = "centinela-github-apply"
  description          = "GitHub Actions: terraform apply desde main, con aprobación (environment produccion)"
  assume_role_policy   = data.aws_iam_policy_document.confianza_apply.json
  max_session_duration = 3600
}

# Riesgo aceptado: Terraform crea roles, Lambdas y EC2, así que el apply necesita
# permisos amplios. Se mitiga con OIDC (sin llaves), confianza limitada al
# environment "produccion" con aprobación humana y sesiones de 1 hora.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.github_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- Salidas -----------------------------------------------------------------------

output "rol_plan_arn" {
  description = "Variable AWS_ROLE_PLAN en GitHub"
  value       = aws_iam_role.github_plan.arn
}

output "rol_apply_arn" {
  description = "Variable AWS_ROLE_APPLY en GitHub"
  value       = aws_iam_role.github_apply.arn
}