FROM ghcr.io/sagernet/sing-box:latest AS singbox

FROM python:3.12-alpine

# sing-box binary from official image
COPY --from=singbox /usr/local/bin/sing-box /usr/local/bin/sing-box

RUN apk add --no-cache wget jq

COPY convert.py /convert.py
COPY entrypoint.sh /entrypoint.sh
COPY template.json /template.json

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
