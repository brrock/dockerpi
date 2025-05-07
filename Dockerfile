FROM debian:latest AS dockerpi

LABEL maintainer="Benjy Ross <benjy@benjyross.xyz>"
RUN apt update && \
    apt install -y --no-install-recommends \
    qemu-system \
    qemu-utils \
    bash \
    mtools \
    curl \
    fdisk \
    xz-utils \
    qemu-kvm && \
    rm -rf /var/lib/apt/lists/*
    
# Entrypoint Script

COPY entrypoint.sh /bin/entrypoint.sh
# set up
COPY setup.sh /bin/setup.sh

RUN chmod +x /bin/entrypoint.sh 

RUN chmod +x /bin/setup.sh 

RUN /bin/setup.sh

VOLUME /sdcard

EXPOSE 2222

ENTRYPOINT ["/bin/entrypoint.sh"]