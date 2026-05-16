FROM ubuntu:20.04

# Avoid timezone prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# Base tools and runtime libs the Qt SDK installer needs.
RUN apt-get update && apt-get install -y --no-install-recommends \
  unzip \
  curl \
  ca-certificates \
  pkg-config \
  file \
  g++ \
  gcc \
  make \
  xvfb \
  libglib2.0-0 \
  libgl1-mesa-glx \
  libfontconfig1 \
  libxrender1 \
  libxext6 \
  libx11-6 \
  libsm6 \
  && rm -rf /var/lib/apt/lists/*

# install.qs drives the Qt SDK installer non-interactively.
# Installer fails silently if this isn't present when the .run executes.
WORKDIR /workspace
COPY install.qs ./

# Fetch, unzip, install, and trim — ALL IN ONE LAYER.
# Critical: separate RUNs would leave the .zip + extracted .run in lower
# layers, bloating the image to ~3.5GB.
RUN curl -fsSL https://github.com/mpwsh/n9-build/releases/download/sdk-assets/QtSdk-offline-linux-x86_64-v1.2.1.zip -o QtSDK.zip \
  && unzip -q QtSDK.zip \
  && rm QtSDK.zip \
  && xvfb-run -a ./QtSdk-offline-linux-x86_64-v1.2.1.run --script install.qs --verbose \
  && rm -f QtSdk-offline-linux-x86_64-v1.2.1.run \
  && rm -rf \
  /opt/QtSDK/Simulator \
  /opt/QtSDK/QtCreator \
  /opt/QtSDK/Symbian \
  /opt/QtSDK/Desktop \
  /opt/QtSDK/Documentation \
  /opt/QtSDK/Examples \
  /opt/QtSDK/Demos \
  /opt/QtSDK/QtSources \
  /opt/QtSDK/SDKMaintenanceTool* \
  /opt/QtSDK/.tempSDKMaintenanceTool \
  /opt/QtSDK/Madde/postinstall \
  && cd / && rm -rf /workspace

ENV PATH=/opt/QtSDK/Madde/bin:$PATH
ENV QMAKESPEC=/opt/QtSDK/Madde/sysroots/harmattan_sysroot_10.2011.34-1_slim/usr/share/qt4/mkspecs/linux-g++-maemo

RUN mad-admin create harmattan_10.2011.34-1_rt1.2 || true \
  && mad set harmattan_10.2011.34-1_rt1.2 \
  && mad-admin list \
  && /opt/QtSDK/Madde/targets/harmattan_10.2011.34-1_rt1.2/bin/gcc --version \
  && test -x /opt/QtSDK/Madde/targets/harmattan_10.2011.34-1_rt1.2/bin/qmake

# The n9 script. Same script as the host-side tool — auto-detects that
# /opt/QtSDK is present and builds locally inside the container.
COPY n9.sh /usr/local/bin/n9
RUN chmod +x /usr/local/bin/n9

WORKDIR /root
CMD ["/bin/bash"]
