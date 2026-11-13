#!/usr/bin/env bash
# Centinela: borra todo lo que creó simular-ataque.sh, buscando por etiqueta y prefijo.
set -euo pipefail
export AWS_PAGER=""
export MSYS_NO_PATHCONV=1
export AWS_REGION="us-east-1"

echo "Security Groups:"
for SG in $(aws ec2 describe-security-groups \
    --filters Name=tag:centinela-simulacion,Values=true \
    --query 'SecurityGroups[].GroupId' --output text); do
  aws ec2 delete-security-group --group-id "$SG" && echo "  borrado ${SG}"
done

echo "Buckets:"
for B in $(aws s3api list-buckets \
    --query "Buckets[?starts_with(Name, 'centinela-sim-')].Name" --output text); do
  aws s3 rb "s3://${B}" --force > /dev/null && echo "  borrado ${B}"
done

echo "Usuarios IAM:"
for U in $(aws iam list-users \
    --query "Users[?starts_with(UserName, 'centinela-sim-')].UserName" --output text); do
  for K in $(aws iam list-access-keys --user-name "$U" \
      --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
    aws iam delete-access-key --user-name "$U" --access-key-id "$K"
  done
  aws iam delete-user --user-name "$U" && echo "  borrado ${U}"
done

echo "CloudTrail:"
aws cloudtrail start-logging --name centinela-trail
echo "  registro activo: $(aws cloudtrail get-trail-status --name centinela-trail --query IsLogging --output text)"     