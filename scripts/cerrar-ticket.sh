#!/usr/bin/env bash
# Uso: bash scripts/cerrar-ticket.sh INC-20261112-A1B2C3D4 "Era yo probando la Fase 4"
set -euo pipefail
export AWS_PAGER=""
export AWS_REGION="us-east-1"

if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <id-del-ticket> \"nota de cierre\"" >&2
  exit 1
fi

ID="$1"
NOTA="${2//\"/\'}"   # Cambia comillas dobles por simples para no romper el JSON
AHORA="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
QUIEN="$(aws sts get-caller-identity --query Arn --output text)"

aws dynamodb update-item --table-name centinela-incidentes \
  --key "{\"id\": {\"S\": \"${ID}\"}}" \
  --update-expression "SET #estado = :e, cerrado_en = :t, cerrado_por = :p, nota_cierre = :n" \
  --condition-expression "attribute_exists(id)" \
  --expression-attribute-names '{"#estado": "estado"}' \
  --expression-attribute-values "{\":e\": {\"S\": \"CERRADO\"}, \":t\": {\"S\": \"${AHORA}\"}, \":p\": {\"S\": \"${QUIEN}\"}, \":n\": {\"S\": \"${NOTA}\"}}" \
  --return-values ALL_NEW \
  --query "Attributes.[id.S, estado.S, cerrado_por.S, nota_cierre.S]" --output text