FROM ubuntu
EXPOSE 80
WORKDIR /app
USER root

COPY entrypoint1.sh ./

RUN apt-get update && apt-get install -y wget curl unzip iproute2 systemctl

ENTRYPOINT [ "/usr/bin/bash", "entrypoint1.sh" ]
