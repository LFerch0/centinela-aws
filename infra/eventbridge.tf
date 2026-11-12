locals {
  llamada_api = "AWS API Call via CloudTrail"
  sin_error   = [{ exists = false }]

  reglas = {
    "sg-abierto" = {
      descripcion = "Security Group que abre puertos de entrada"
      patron = {
        source        = ["aws.ec2"]
        "detail-type" = [local.llamada_api]
        detail = {
          eventSource = ["ec2.amazonaws.com"]
          eventName   = ["AuthorizeSecurityGroupIngress", "ModifySecurityGroupRules"]
          errorCode   = local.sin_error
        }
      }
    }
    "s3-publico" = {
      descripcion = "Cambios en el acceso público de un bucket S3"
      patron = {
        source        = ["aws.s3"]
        "detail-type" = [local.llamada_api]
        detail = {
          eventSource = ["s3.amazonaws.com"]
          eventName   = ["DeleteBucketPublicAccessBlock", "PutBucketPublicAccessBlock", "PutBucketPolicy", "PutBucketAcl"]
          errorCode   = local.sin_error
        }
      }
    }
    "cloudtrail-alterado" = {
      descripcion = "Alguien detuvo o borró un trail"
      patron = {
        source        = ["aws.cloudtrail"]
        "detail-type" = [local.llamada_api]
        detail = {
          eventSource = ["cloudtrail.amazonaws.com"]
          eventName   = ["StopLogging", "DeleteTrail"]
          errorCode   = local.sin_error
        }
      }
    }
    "login-root" = {
      descripcion = "Inicio de sesión exitoso con la cuenta root"
      patron = {
        source        = ["aws.signin"]
        "detail-type" = ["AWS Console Sign In via CloudTrail"]
        detail = {
          eventName        = ["ConsoleLogin"]
          userIdentity     = { type = ["Root"] }
          responseElements = { ConsoleLogin = ["Success"] }
        }
      }
    }
    "login-fallido" = {
      descripcion = "Inicio de sesión fallido en la consola"
      patron = {
        source        = ["aws.signin"]
        "detail-type" = ["AWS Console Sign In via CloudTrail"]
        detail = {
          eventName        = ["ConsoleLogin"]
          responseElements = { ConsoleLogin = ["Failure"] }
        }
      }
    }
    "access-key-nueva" = {
      descripcion = "Se creó una access key de IAM"
      patron = {
        source        = ["aws.iam"]
        "detail-type" = [local.llamada_api]
        detail = {
          eventSource = ["iam.amazonaws.com"]
          eventName   = ["CreateAccessKey"]
          errorCode   = local.sin_error
        }
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "deteccion" {
  for_each = local.reglas

  name          = "${local.nombre}-${each.key}"
  description   = each.value.descripcion
  event_pattern = jsonencode(each.value.patron)
}

resource "aws_cloudwatch_event_target" "deteccion" {
  for_each = local.reglas

  rule = aws_cloudwatch_event_rule.deteccion[each.key].name
  arn  = aws_lambda_function.remediador.arn

  retry_policy {
    maximum_retry_attempts       = 8
    maximum_event_age_in_seconds = 3600
  }
}

# Política del recurso Lambda: solo ESTA regla puede invocarla
resource "aws_lambda_permission" "deteccion" {
  for_each = local.reglas

  statement_id  = "EventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediador.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.deteccion[each.key].arn
}