#!/usr/bin/env bash
# Centinela: simula 4 incidentes reales y mide cuánto tarda la respuesta.
# Todo lo que crea lleva la etiqueta o el prefijo centinela-sim.
set -euo pipefail
export AWS_PAGER=""
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no convertir rutas como /aws/...
export AWS_REGION="us-east-1"

TRAIL="centinela-trail"
TABLA="centinela-incidentes"
LIMITE=600   # segundos máximos de espera

SUFIJO="$(date +%s)"
CUENTA="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="centinela-sim-${CUENTA}-${SUFIJO}"
USUARIO="centinela-sim-${SUFIJO}"

paso() { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(date -u +%H:%M:%S)" "$1"; }
ok()   { printf '  \033[1;32m✔ %-28s resuelto en %4d s\033[0m\n' "$1" "$2"; }

paso "Simulación en la cuenta ${CUENTA}"

VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
if [[ "$VPC_ID" == "None" ]]; then
  echo "No hay VPC por defecto en ${AWS_REGION}. Créala con: aws ec2 create-default-vpc" >&2
  exit 1
fi

INICIO=$SECONDS

paso "1/4 Security Group con SSH abierto a internet"
SG_ID="$(aws ec2 create-security-group --group-name "centinela-sim-${SUFIJO}" \
  --description "Simulacion Centinela" --vpc-id "$VPC_ID" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=centinela-simulacion,Value=true}]' \
  --query GroupId --output text)"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
echo "  ${SG_ID}: tcp/22 desde 0.0.0.0/0"

paso "2/4 Bucket sin bloqueo de acceso público"
aws s3api create-bucket --bucket "$BUCKET" > /dev/null
aws s3api put-bucket-tagging --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=centinela-simulacion,Value=true}]'
aws s3api delete-public-access-block --bucket "$BUCKET"
echo "  ${BUCKET}: Block Public Access eliminado"

paso "3/4 Usuario IAM con access key nueva"
aws iam create-user --user-name "$USUARIO" \
  --tags Key=centinela-simulacion,Value=true > /dev/null
aws iam create-access-key --user-name "$USUARIO" > /dev/null   # El secreto nunca se muestra
echo "  ${USUARIO}: access key creada"

paso "4/4 CloudTrail detenido"
aws cloudtrail stop-logging --name "$TRAIL"
echo "  ${TRAIL}: registro detenido"

paso "Esperando a Centinela (máximo ${LIMITE} s)..."
sg=0; s3=0; ct=0; key=0
while (( SECONDS - INICIO < LIMITE )); do
  t=$(( SECONDS - INICIO ))
  if (( !sg )) && [[ "$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
        --query 'length(SecurityGroups[0].IpPermissions)' --output text)" == "0" ]]; then
    sg=1; ok "Security Group" "$t"
  fi
  if (( !s3 )) && [[ "$(aws s3api get-public-access-block --bucket "$BUCKET" \
        --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text 2>/dev/null || echo False)" == "True" ]]; then
    s3=1; ok "Bucket S3" "$t"
  fi
  if (( !ct )) && [[ "$(aws cloudtrail get-trail-status --name "$TRAIL" \
        --query IsLogging --output text)" == "True" ]]; then
    ct=1; ok "CloudTrail" "$t"
  fi
  if (( !key )) && [[ "$(aws dynamodb scan --table-name "$TABLA" \
        --query "length(Items[?contains(recurso.S, '${USUARIO}')])" --output text)" != "0" ]]; then
    key=1; ok "Access key (ticket)" "$t"
  fi
  (( sg && s3 && ct && key )) && break
  sleep 15
done

if (( sg && s3 && ct && key )); then
  paso "Los 4 incidentes fueron detectados y atendidos"
else
  paso "Tiempo agotado: revisa los logs de la Lambda"
  exit 1
fi
echo "  Tickets:  bash scripts/ver-tickets.sh"
echo "  Limpiar:  bash scripts/limpiar-simulacion.sh"