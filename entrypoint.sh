#!/bin/bash
set -euo pipefail

function join_by { local IFS="$1"; shift; echo "$*"; }

# 전달된 JSON 문자열 파싱
input_json="$1"
AWS_ACCESS_KEY_ID=$(echo "$input_json" | jq -r '.["aws-access-key-id"]')
AWS_ACCESS_KEY=$(echo "$input_json" | jq -r '.["aws-access-key"]')
AWS_REGION=$(echo "$input_json" | jq -r '.["aws-region"]')
BUCKET=$(echo "$input_json" | jq -r '.bucket')
BUCKET_PATH=$(echo "$input_json" | jq -r '.["bucket-path"]')
TAR_PASSWORD=$(echo "$input_json" | jq -r '.["tar-password"]')
EMAIL=$(echo "$input_json" | jq -r '.email')
DOMAINS=$(echo "$input_json" | jq -r '.domains')
FILE_PATH=$(echo "$input_json" | jq -r '.["file-path"]')

CERTBOT_FILE_PATH=${FILE_PATH}_certbot.tar.gz
FILE_PATH=${FILE_PATH}.tar.gz

IFS=',' read -r -a DOMAIN_ARRAY <<< "$DOMAINS"
DOMAIN_ARGS=""
for domain in "${DOMAIN_ARRAY[@]}"; do
  DOMAIN_ARGS+=" --domain $domain"
done

FIRST_DOMAIN=${DOMAIN_ARRAY[0]}

# test-cert와 dry-run 옵션 처리
CERTBOT_OPTIONS=""

if [[ $(echo "$input_json" | jq -r '.["test-cert"]') == "true" ]]; then
  CERTBOT_OPTIONS+=" --test-cert"
fi

if [[ $(echo "$input_json" | jq -r '.["dry-run"]') == "true" ]]; then
  CERTBOT_OPTIONS+=" --dry-run"
fi

echo '*************** Setting up awscli ***************'
aws configure set output json
aws configure set region $AWS_REGION
aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_ACCESS_KEY

if [ -d /etc/letsencrypt ]; then
  echo "*************** Removing previous certificates from /etc/letsencrypt/* ***************"
  rm -rf /etc/letsencrypt/*
else
  echo "*************** /etc/letsencrypt directory does not exist, skipping removal ***************"
fi

EXISTS=$(aws s3api head-object --bucket $BUCKET --key $CERTBOT_FILE_PATH || echo 1)

if [[ $EXISTS != 1 ]]; then
  echo "*************** Fetching previous certificate from $BUCKET ***************"
  aws s3 cp s3://$BUCKET/$CERTBOT_FILE_PATH $CERTBOT_FILE_PATH

  if [[ -z $TAR_PASSWORD ]]; then
    tar -zxf $CERTBOT_FILE_PATH --directory /etc/letsencrypt/
  else
    gpg --pinentry-mode=loopback --passphrase "$TAR_PASSWORD" -d $CERTBOT_FILE_PATH | tar --directory /etc/letsencrypt/ -zxf -
  fi

  rm -f $CERTBOT_FILE_PATH
else
  echo "Certificate not found on $BUCKET, will attempt to create a new one"
fi

echo "*************** Creating or renewing certificate for $DOMAINS ***************"
certbot certonly --agree-tos --non-interactive --dns-route53 -m $EMAIL \
  --cert-name ${FIRST_DOMAIN} \
  $DOMAIN_ARGS $CERTBOT_OPTIONS
if [[ $? -eq 0 ]]; then
  echo "Certificate issued or renewed successfully."
elif [[ $? -eq 2 ]]; then
  echo "Certificate is already up to date. No renewal performed."
else
  echo "Certificate issuance or renewal failed."
fi

tar -zcf $CERTBOT_FILE_PATH --directory /etc/letsencrypt/ .
if [[ ! -z $TAR_PASSWORD ]]; then
  mv $CERTBOT_FILE_PATH cert.tar.gz
  gpg --batch --yes --pinentry-mode loopback --passphrase "$TAR_PASSWORD" -o $CERTBOT_FILE_PATH -c cert.tar.gz
  rm -f cert.tar.gz
fi

tar -zcf $FILE_PATH --dereference --directory /etc/letsencrypt/live/${FIRST_DOMAIN}/ .
if [[ ! -z $TAR_PASSWORD ]]; then
  mv $FILE_PATH cert.tar.gz
  gpg --batch --yes --pinentry-mode loopback --passphrase "$TAR_PASSWORD" -o $FILE_PATH -c cert.tar.gz
  rm -f cert.tar.gz
fi

SERIAL=$(openssl x509 -in /etc/letsencrypt/live/${FIRST_DOMAIN}/cert.pem -serial -noout | awk -F= '{print tolower($2)}')
NAME=$(echo "${FIRST_DOMAIN}-${SERIAL}" | sed 's/\./-/g')

echo '*************** Uploading created/renewed certificate to storage ***************'
aws s3 cp $CERTBOT_FILE_PATH s3://$BUCKET/$CERTBOT_FILE_PATH
aws s3 cp $FILE_PATH s3://$BUCKET/$FILE_PATH

echo "certificate-name=${NAME}" >> "$GITHUB_OUTPUT"
echo "certificate-path=/etc/letsencrypt/live/${FIRST_DOMAIN}/" >> $GITHUB_OUTPUT

echo '*************** Cleaning up ***************'
rm -rf /etc/letsencrypt/*

echo '*************** Done ***************'