#!/usr/bin/env bash
# Uso: bash scripts/ver-tickets.sh             -> todos, del más antiguo al más reciente
#      bash scripts/ver-tickets.sh pendientes  -> solo los que necesitan a una persona
set -euo pipefail
export AWS_PAGER=""
export AWS_REGION="us-east-1"

FILTRO=""
if [[ "${1:-}" == "pendientes" ]]; then
  FILTRO="[?estado.S=='REQUIERE_REVISION' || estado.S=='FALLO_REMEDIACION']"
fi

aws dynamodb scan --table-name centinela-incidentes --output table \
  --query "sort_by(Items, &registrado_en.S)${FILTRO}[].[id.S, severidad.S, tipo.S, estado.S, segundos_hasta_respuesta.N, recurso.S]"