#!/bin/bash
set -euo pipefail

function join_by { local IFS="$1"; shift; echo "$*"; }

# 전달된 JSON 문자열 파싱
input_json="$1"
AWS_ACCESS_KEY_ID=$(echo "$input_json" | jq -r '.["aws-access-key-id"]')
AWS_ACCESS_KEY=$(echo "$input_json" | jq -r '.["aws-access-key"]')
AWS_REGION=$(echo "$input_json" | jq -r '.["aws-region"]')
BUCKET=$(echo "$input_json" | jq -r '.bucket')
TAR_PASSWORD=$(echo "$input_json" | jq -r '.["tar-password"]')
EMAIL=$(echo "$input_json" | jq -r '.email')
DOMAINS=$(echo "$input_json" | jq -r '.domains')
FILE_PATH=$(echo "$input_json" | jq -r '.["file-path"]')
GENERATE_FULLCERT=$(echo "$input_json" | jq -r '.["generate-fullcert"]')

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

# 러너/스텝 디버그 활성 시
if [ "${ACTIONS_RUNNER_DEBUG:-}" = "true" ] || [ "${ACTIONS_STEP_DEBUG:-}" = "true" ]; then
  # certbot verbose
  CERTBOT_OPTIONS+=" -v"
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
output=$(certbot certonly --agree-tos --non-interactive --dns-route53 -m $EMAIL \
  --cert-name ${FIRST_DOMAIN} \
  $DOMAIN_ARGS $CERTBOT_OPTIONS)
exit_code=$?

# Certbot 실행 결과 확인
if [[ $exit_code -ne 0 ]]; then
  echo "Certbot command failed with exit code $exit_code."
  exit $exit_code
fi

# Certbot이 성공하면 /etc/letsencrypt가 존재해야 함
if [[ ! -d /etc/letsencrypt ]]; then
  echo "❌ Error: /etc/letsencrypt directory does not exist after Certbot execution."
  exit 1
fi

renewal_status="renewed"
# 갱신 여부 판단
if [[ "$output" =~ "Certificate not yet due for renewal" ]]; then
  renewal_status="not-renewed"
fi

if [[ $GENERATE_FULLCERT == "true" ]]; then
  pushd /etc/letsencrypt/live/${FIRST_DOMAIN}/
    if [[ ! -f fullcert.pem ]]; then
      echo "fullcert.pem not found in /etc/letsencrypt/live/${FIRST_DOMAIN}/, creating it..."
      cat privkey.pem fullchain.pem > fullcert.pem
      renewal_status="renewed"
    else
      echo "fullcert.pem already exists in /etc/letsencrypt/live/${FIRST_DOMAIN}/, checking if it needs to be updated..."
      current_fullcert=$(cat privkey.pem fullchain.pem)
      existing_fullcert=$(cat fullcert.pem)
      if [[ "$current_fullcert" != "$existing_fullcert" ]]; then
        echo "fullcert.pem is outdated, updating it..."
        cat privkey.pem fullchain.pem > fullcert.pem
        renewal_status="renewed"
      else
        echo "fullcert.pem is up to date."
      fi
    fi
  popd
fi

echo "renewal-status=$renewal_status" >> $GITHUB_OUTPUT

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

echo '*************** Copying the created/renewed certificate to a local directory for further processing ***************'
mkdir -p $PWD/${FIRST_DOMAIN}
cp -rL /etc/letsencrypt/live/${FIRST_DOMAIN}/ $PWD/${FIRST_DOMAIN}

echo "certificate-name=${NAME}" >> "$GITHUB_OUTPUT"
echo "certificate-path=${PWD}/${FIRST_DOMAIN}/" >> $GITHUB_OUTPUT
echo "certificate-s3-path=s3://$BUCKET/$FILE_PATH" >> $GITHUB_OUTPUT

echo '*************** Cleaning up ***************'
rm -rf /etc/letsencrypt/*

echo '*************** Done ***************'