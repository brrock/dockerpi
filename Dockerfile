FROM debian:stable-slim AS qemu-builder
ARG QEMU_VERSION=9.2.0

# Install build dependencies
RUN apt-get update && apt-get install -y \
    wget gpg pkg-config \
    build-essential \
    libglib2.0-dev \
    libpixman-1-dev \
    ninja-build \
    python3 \
    git \
    ca-certificates \
    libfdt-dev \
    zlib1g-dev \
    xz-utils \
    unzip \
    libgpiod-dev \
    libusb-1.0-0-dev \
    libsystemd-dev \
    libudev-dev \
    python3-venv \
    libepoxy-dev \
    pkg-config \
    qemu-system-aarch64 \
    qemu-utils

# Download and verify QEMU source
WORKDIR /qemu


# gpio time
FROM debian:stable-slim AS gpio-builder
RUN apt-get update && apt-get install -y \
    gpiod 

# Fatcat builder stage
FROM debian:stable-slim AS fatcat-builder
ARG FATCAT_VERSION=v1.1.0

RUN apt-get update && apt-get install -y \
    wget \
    build-essential \
    cmake \
    ca-certificates

WORKDIR /fatcat
RUN wget "https://github.com/Gregwar/fatcat/archive/${FATCAT_VERSION}.tar.gz"

RUN tar xvf "${FATCAT_VERSION}.tar.gz"
RUN cmake fatcat-* -DCMAKE_CXX_FLAGS='-static'
RUN make -j$(nproc)

# DockerPi VM Stage with GPIO Support
FROM busybox:latest AS dockerpi-vm
LABEL maintainer="Benjy Ross <benjy@benjyross.xyz>"

# Install GPIO support tools
COPY --from=gpio-builder /usr/bin/gpiodetect /usr/local/bin/gpiodetect
COPY --from=gpio-builder /usr/bin/gpioinfo /usr/local/bin/gpioinfo
COPY --from=gpio-builder /usr/bin/gpioget /usr/local/bin/gpioget
COPY --from=gpio-builder /usr/bin/gpioset /usr/local/bin/gpioset

# Ensure the binaries are executable
RUN chmod +x /usr/local/bin/gpiodetect \
    /usr/local/bin/gpioinfo \
    /usr/local/bin/gpioget \
    /usr/local/bin/gpioset

# Copy QEMU and supporting binaries
COPY --from=qemu-builder /usr/bin/qemu-system-aarch64 /usr/local/bin/qemu-system-aarch64
COPY --from=qemu-builder /usr/bin/qemu-img /usr/local/bin/qemu-img
COPY --from=fatcat-builder /fatcat/fatcat /usr/local/bin/fatcat

# Kernel and Device Tree Support
RUN mkdir -p /root/kernels/pi4 /root/kernels/pi5

ADD https://github.com/raspberrypi/firmware/raw/master/boot/bcm2711-rpi-4-b.dtb /root/kernels/pi4/
ADD https://github.com/raspberrypi/firmware/raw/master/boot/kernel7l.img /root/kernels/pi4/kernel7l.img

ADD https://github.com/raspberrypi/firmware/raw/master/boot/bcm2712-rpi-5-b.dtb /root/kernels/pi5/
ADD https://github.com/raspberrypi/firmware/raw/master/boot/kernel_2712.img /root/kernels/pi5/kernel_2712.img

# GPIO Device Mapping
VOLUME /dev/gpiochip0

# Entrypoint Script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment Variables for GPIO and PI Configuration
ENV PI_GPIO_ENABLED=1
ENV PI_GPIO_CHIP="/dev/gpiochip0"
ENV PI_MODEL=pi4
ENV PI_RAM=4g

VOLUME /sdcard
ENTRYPOINT ["/entrypoint.sh"]

# Filesystem Stage
FROM dockerpi-vm AS dockerpi
LABEL maintainer="Benjy Ross <benjy@benjyross.xyz>"

# Raspbian Lite Image
ARG FILESYSTEM_IMAGE_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-11-19/2024-11-19-raspios-bookworm-arm64-lite.img.xz"
ARG FILESYSTEM_IMAGE_CHECKSUM="6ac3a10a1f144c7e9d1f8e568d75ca809288280a593eb6ca053e49b539f465a4"

# Download and Prepare Filesystem
ADD $FILESYSTEM_IMAGE_URL /filesystem.img.xz
RUN echo "${FILESYSTEM_IMAGE_CHECKSUM}  /filesystem.img.xz" | sha256sum -c && \
    xz -d /filesystem.img.xz && \
    mv filesystem.img /sdcard/

# Resize Filesystem
RUN qemu-img resize /sdcard/filesystem.img +2G

# Default to Pi 4
CMD ["pi4"]