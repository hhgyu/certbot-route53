FROM python:3.12-alpine

RUN apk add --no-cache --update \
 augeas \
 aws-cli \
 bash \
 curl \
 gnupg \
 gzip \
 jq \
 libffi \
 openssl \
 tar \
 which \
 xz

# python 3
ENV PYTHONUNBUFFERED=1
RUN echo "**** install Python ****" && \
    apk add --no-cache python3 && \
    if [ ! -e /usr/bin/python ]; then ln -sf python3 /usr/bin/python ; fi && \
    \
    echo "**** install pip ****" && \
    python3 -m ensurepip && \
    rm -r /usr/lib/python*/ensurepip && \
    pip3 install --no-cache --upgrade pip setuptools wheel certbot certbot-route53 && \
    if [ ! -e /usr/bin/pip ]; then ln -s pip3 /usr/bin/pip ; fi

RUN mkdir -p /etc/letsencrypt

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
