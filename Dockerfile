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
    libudev-dev

# Download and verify QEMU source
WORKDIR /qemu
RUN wget "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz"
RUN wget "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz.sig"

RUN gpg --keyserver keyserver.ubuntu.com --recv-keys CEACC9E15534EBABB82D3FA03353C9CEF108B584
RUN gpg --verify "qemu-${QEMU_VERSION}.tar.xz.sig" "qemu-${QEMU_VERSION}.tar.xz"

# Extract and build QEMU with extensive GPIO and device support
RUN tar xvf "qemu-${QEMU_VERSION}.tar.xz"
RUN cd "qemu-${QEMU_VERSION}" && \
    ./configure \
    --target-list=aarch64-softmmu,arm-softmmu \
    --enable-system \
    --enable-linux-user \
    --disable-werror \
    --enable-kvm \
    --enable-opengl \
    --enable-usb \
    --enable-libusb \
    --enable-libudev \
    --enable-virtfs \
    --audio-drv-list=alsa,pa

RUN cd "qemu-${QEMU_VERSION}" && \
    make -j$(nproc)

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
COPY --from=qemu-builder /qemu/qemu-${QEMU_VERSION}/aarch64-softmmu/qemu-system-aarch64 /usr/local/bin/qemu-system-aarch64
COPY --from=qemu-builder /qemu/qemu-${QEMU_VERSION}/arm-softmmu/qemu-system-arm /usr/local/bin/qemu-system-arm
COPY --from=qemu-builder /qemu/qemu-${QEMU_VERSION}/qemu-img /usr/local/bin/qemu-img
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
ARG FILESYSTEM_IMAGE_URL="https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2023-12-11/2023-12-11-raspbian-bookworm-lite.img.xz"
ARG FILESYSTEM_IMAGE_CHECKSUM="3f5b121a2f10dad5e121b22ee569a047aab9cc216e9d3fd40b994ee12cc16e93"

# Download and Prepare Filesystem
ADD $FILESYSTEM_IMAGE_URL /filesystem.xz
RUN echo "${FILESYSTEM_IMAGE_CHECKSUM}  /filesystem.xz" | sha256sum -c && \
    xz -d /filesystem.xz && \
    mv *.img /sdcard/filesystem.img

# Resize Filesystem
RUN qemu-img resize /sdcard/filesystem.img +2G

# Default to Pi 4
CMD ["pi4"]