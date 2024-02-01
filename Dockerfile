FROM node:21-alpine

ENV SWITCH_HOSTNAME=10.90.90.90 PORT=80 USERNAME=admin PASSWORD= DEBUG=

RUN apk add --no-cache bash curl jq

RUN npm install -g jsonrepair

COPY ./dlink-dgs.sh /usr/bin/dlink-dgs.sh

ENTRYPOINT ["/usr/bin/dlink-dgs.sh"]
