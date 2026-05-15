FROM ubuntu:20.04

# Avoid timezone prompts
ENV DEBIAN_FRONTEND=noninteractive

# Basic tools for exploration and extraction
RUN apt-get update && apt-get install -y \
    unzip \
    pkg-config \
    vim \
    file \
    tree \
    nano \
    less \
    bash \
    libglib2.0-0 \
    libgl1-mesa-glx \
    libfontconfig1 \
    libxrender1 \
    libxext6 \
    libx11-6 \
    libsm6 \
    g++ \
    make \
    openssh-client \
    gcc \
    wget \
    xvfb


WORKDIR /workspace

RUN wget https://n9.mpw.sh/sdk/QtSdk-offline-linux-x86_64-v1.2.1.zip -O /workspace/QtSDK.zip
RUN unzip QtSDK.zip || true
RUN xvfb-run -a ./QtSdk-offline-linux-x86_64-v1.2.1.run --script install.qs --verbose \
 && rm -f QtSdk-offline-linux-x86_64-v1.2.1.run QtSDK.zip

ENV PATH=/opt/QtSDK/Madde/bin:$PATH

RUN mad-admin create harmattan_10.2011.34-1_rt1.2 || true
RUN mad set harmattan_10.2011.34-1_rt1.2 || true
RUN mad-admin list
RUN /opt/QtSDK/Madde/targets/harmattan_10.2011.34-1_rt1.2/bin/gcc --version
RUN ls -la /opt/QtSDK/Madde/targets/harmattan_10.2011.34-1_rt1.2/bin/qmake

ENV QMAKESPEC=/opt/QtSDK/Madde/sysroots/harmattan_sysroot_10.2011.34-1_slim/usr/share/qt4/mkspecs/linux-g++-maemo

RUN rm -rf /workspace
WORKDIR /root

COPY n9.sh /usr/local/bin/n9
RUN chmod +x /usr/local/bin/n9


CMD ["/bin/bash"]
