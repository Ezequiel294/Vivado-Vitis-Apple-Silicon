# x86-64 Ubuntu environment for AMD Vivado/Vitis 2026.1 under Rosetta.
# The image stays thin: Vivado itself is installed manually (GUI) onto
# the `xilinx-install` named volume mounted at /opt/Xilinx.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# X11 client libs + GTK (installer and Vivado GUIs), fonts, locale,
# libtinfo5 (required by Vivado, dropped in Ubuntu 24.04), build tools
# for the udev stub, and general utilities.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        locales \
        sudo \
        gcc \
        libc6-dev \
        make \
        libtinfo5 \
        libncurses5 \
        libx11-6 libxext6 libxrender1 libxtst6 libxi6 libxrandr2 \
        libxcursor1 libxfixes3 libxft2 libfreetype6 \
        libgtk-3-0 libglib2.0-0 libcanberra-gtk3-module \
        libnss3 libnspr4 libasound2 \
        libyaml-0-2 \
        libsm6 libice6 libxinerama1 \
        fontconfig fonts-dejavu-core fonts-liberation \
        x11-apps x11-utils xauth \
        lsb-release \
        libusb-1.0-0 \
        less nano wget unzip \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# No-op libudev stub: prevents the known Vivado-under-Rosetta crash in
# udev_enumerate_scan_devices() (docker/for-mac#7320). Activated via
# LD_PRELOAD in docker-compose.yml.
COPY udev-stub.c udev-stub.map /opt/stub/
# SONAME + LIBUDEV_183 version tag let the stub fully impersonate the real
# library: FlexLM (license checkout) dlopens libudev directly (bypassing
# LD_PRELOAD), and OS tools like apt need versioned symbols to keep working.
RUN gcc -shared -fPIC -Wl,-soname,libudev.so.1 \
        -Wl,--version-script=/opt/stub/udev-stub.map \
        -o /opt/stub/libudev-stub.so /opt/stub/udev-stub.c \
    && ln -sf /opt/stub/libudev-stub.so /lib/x86_64-linux-gnu/libudev.so.1

# Non-root user; sudo without password for in-container convenience.
RUN useradd -m -s /bin/bash -u 501 user \
    && echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user

# Vivado install target and config dir (named volumes mount here);
# owned by `user` so the GUI installer can write without sudo.
RUN mkdir -p /opt/Xilinx /home/user/.Xilinx \
    && chown user:user /opt/Xilinx /home/user/.Xilinx

USER user
WORKDIR /home/user

CMD ["/bin/bash"]
