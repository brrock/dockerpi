FROM debian:latest AS dockerpi

LABEL maintainer="Benjy Ross <benjy@benjyross.xyz>"
RUN apt update && \
    apt install -y --no-install-recommends \
    qemu-system \
    qemu-utils \
    mtools \
    qemu-kvm && \
    rm -rf /var/lib/apt/lists/*
# Entrypoint Script
COPY entrypoint.sh /entrypoint.sh
# set up
COPY setup.sh /entrypoint.sh

RUN chmod +x /*.sh 

VOLUME /sdcard
EXPOSE 2222
ENTRYPOINT ["/entrypoint.sh"]