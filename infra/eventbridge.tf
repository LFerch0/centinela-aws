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