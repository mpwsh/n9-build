FROM ubuntu:20.04

# Avoid timezone prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# Base tools and runtime libs the Qt SDK installer needs.
# Combined into one RUN with apt cache cleanup so the package metadata
# doesn't end up in the final image.
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
# Must land before the install RUN, but doesn't need to be in the same layer
# (it's tiny). Don't remove this COPY when refactoring — installer fails
# silently without it.
WORKDIR /workspace
COPY install.qs ./

# Fetch, unzip, install, and trim — ALL IN ONE LAYER.
# This is critical: if these are separate RUNs (or if the .zip is COPY'd
# from the host), the intermediate files persist in lower layers and the
# image bloats to ~3.5GB even though the live filesystem is ~2GB.
RUN curl -fsSL https://n9.mpw.sh/sdk/QtSdk-offline-linux-x86_64-v1.2.1.zip -o QtSDK.zip \
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

# Configure the Harmattan target as default. Sanity-check the toolchain
# while we're at it — verifies gcc + qmake are wired up correctly. All
# combined into one RUN so the verification doesn't generate empty layers.
RUN mad-admin create harmattan_10.2011.34-1_rt1.2 || true \
 && mad set harmattan_10.2011.34-1_rt1.2 \
 && mad-admin list \
 && /opt/QtSDK/Madde/targets/harmattan_10.2011.34-1_rt1.2/bin/gcc --version \
 && test -x /opt/QtSDK/Madde/targets/harmattan_10.2011.34-1_rt1.2/bin/qmake

# n9 build script. Last because it's the most-edited file — put it last
# so changes to it only invalidate this small layer, not the SDK install.
COPY n9.sh /usr/local/bin/n9
RUN chmod +x /usr/local/bin/n9

WORKDIR /root
CMD ["/bin/bash"]
