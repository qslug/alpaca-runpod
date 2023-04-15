###################
# Builder Stage
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Don't write .pyc bytecode
ENV PYTHONDONTWRITEBYTECODE=1

# Create workspace working directory
RUN mkdir /build
WORKDIR /build

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && apt-get install -y \
        git wget build-essential \
        python3-venv python3-pip \
        gnupg ca-certificates \
    && update-ca-certificates

ENV VIRTUAL_ENV=/workspace/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m venv ${VIRTUAL_ENV} && \
    pip install -U -I torch==2.0.0+cu118 torchvision==0.15.1+cu118 --extra-index-url "https://download.pytorch.org/whl/cu118" 


###################
# Runtime Stage
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04 as runtime

# Use bash shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND noninteractive\
    SHELL=/bin/bash

# Python logs go strait to stdout/stderr w/o buffering
ENV PYTHONUNBUFFERED=1

# Don't write .pyc bytecode
ENV PYTHONDONTWRITEBYTECODE=1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && apt install -y --no-install-recommends \
        wget bash curl git git-lfs vim tmux \
        build-essential lsb-release \
        python3-pip python3-venv \
        openssh-server \
        gnupg ca-certificates && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Install runpodctl
RUN wget https://github.com/runpod/runpodctl/releases/download/v1.9.0/runpodctl-linux-amd -O runpodctl && \
    chmod a+x runpodctl && \
    mv runpodctl /usr/local/bin

ENV VIRTUAL_ENV=/workspace/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
RUN echo "source ${VIRTUAL_ENV}/bin/activate" >> /root/.bashrc

# Workaround for:
#   https://github.com/TimDettmers/bitsandbytes/issues/62
#   https://github.com/TimDettmers/bitsandbytes/issues/73
ENV LD_LIBRARY_PATH="/usr/local/cuda-11.8/targets/x86_64-linux/lib/"
RUN ln /usr/local/cuda/targets/x86_64-linux/lib/libcudart.so.11.8.89 /usr/local/cuda-11.8/targets/x86_64-linux/lib/libcudart.so
RUN ln /usr/local/cuda/targets/x86_64-linux/lib/libnvrtc.so.11.8.89 /usr/local/cuda-11.8/targets/x86_64-linux/lib/libnvrtc.so


ADD requirements-runpod.txt /
RUN pip install --no-cache-dir -r requirements-runpod.txt

WORKDIR /workspace
RUN git clone https://github.com/tatsu-lab/stanford_alpaca.git

WORKDIR /workspace/stanford_alpaca
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -U git+https://github.com/zphang/transformers.git@68d640f7c368bcaaaecfc678f11908ebbd3d6176

WORKDIR /workspace

ADD start.sh /
RUN chmod +x /start.sh
CMD [ "/start.sh" ]