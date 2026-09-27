# syntax=docker/dockerfile:1.7
# Re:VIEW（LuaLaTeX）で組版・検査するためのツールチェーン。
# 同じDockerfileから同じ中身になるよう、基点・apt・gem・npm・外部ファイルの
# 版をすべて固定する。

ARG UBUNTU_IMAGE=ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3
ARG NODE_IMAGE=node:22-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c

FROM ${NODE_IMAGE} AS node

FROM ${UBUNTU_IMAGE}

# aptの取得元はsnapshot.ubuntu.comの日付で固定する。
ARG APT_SNAPSHOT=20260915T000000Z
ARG PLANTUML_VERSION=1.2026.8
ARG PLANTUML_SHA256=5e1ecfa8ecd32c90b03bbf3b1eb6f020943f98ab0fcf4032be31a0002ee2c462
ARG EPUBCHECK_VERSION=5.4.0
ARG EPUBCHECK_SHA256=33350c61038e71dfb3d45a76aed04bf5481e6d5500cb780f6e98db8bbd15a28c
ARG DRAWIO_VERSION=31.5.3
ARG DRAWIO_SHA256=b2fd41f02567929c5fae4becbdc16bf118b1ef508a827a29ad9a883924263999

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Tokyo

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# TLSを中継するプロキシの内側でビルドするときだけ、追加のCAを
# BuildKitのsecretで渡す。secretはイメージのレイヤーに残らない。
# 1段目：凍結済みのnobleリリースpocket（http・GPG署名で検証）から
# ca-certificatesだけを入れ、snapshotへhttpsで接続できるようにする。
RUN --mount=type=secret,id=extra_ca,required=false \
    rm -f /etc/apt/sources.list.d/ubuntu.sources \
 && echo 'deb http://archive.ubuntu.com/ubuntu noble main' \
      > /etc/apt/sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -f /etc/apt/sources.list \
 && printf '%s\n' \
      "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT} noble main universe" \
      "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT} noble-updates main universe" \
      "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT} noble-security main universe" \
      > /etc/apt/sources.list.d/snapshot.list \
 && rm -rf /var/lib/apt/lists/*

COPY apt-packages.txt /tmp/apt-packages.txt
RUN --mount=type=secret,id=extra_ca,required=false \
    CAOPT=(); \
    if [ -s /run/secrets/extra_ca ]; then \
      cat /etc/ssl/certs/ca-certificates.crt /run/secrets/extra_ca > /tmp/ca.crt; \
      CAOPT=(-o Acquire::https::CAInfo=/tmp/ca.crt); \
    fi \
 && apt-get "${CAOPT[@]}" update \
 && xargs -a /tmp/apt-packages.txt \
      apt-get "${CAOPT[@]}" install -y --no-install-recommends \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/ca.crt /tmp/apt-packages.txt

# Node.jsはtextlintの要件（20.18以上）を満たす公式イメージから取る。
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# 外部ファイルはsha256を照合してから置く。
RUN --mount=type=secret,id=extra_ca,required=false \
    CURLOPT=(); \
    if [ -s /run/secrets/extra_ca ]; then \
      cat /etc/ssl/certs/ca-certificates.crt /run/secrets/extra_ca > /tmp/ca.crt; \
      CURLOPT=(--cacert /tmp/ca.crt); \
    fi \
 && gh=https://github.com \
 && mkdir -p /opt/plantuml /opt/epubcheck \
 && curl -fsSL "${CURLOPT[@]}" -o /opt/plantuml/plantuml.jar \
      "$gh/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar" \
 && echo "${PLANTUML_SHA256}  /opt/plantuml/plantuml.jar" | sha256sum -c - \
 && curl -fsSL "${CURLOPT[@]}" -o /tmp/epubcheck.zip \
      "$gh/w3c/epubcheck/releases/download/v${EPUBCHECK_VERSION}/epubcheck-${EPUBCHECK_VERSION}.zip" \
 && echo "${EPUBCHECK_SHA256}  /tmp/epubcheck.zip" | sha256sum -c - \
 && unzip -q /tmp/epubcheck.zip -d /tmp \
 && mv /tmp/epubcheck-${EPUBCHECK_VERSION}/* /opt/epubcheck/ \
 && curl -fsSL "${CURLOPT[@]}" -o /tmp/drawio.deb \
      "$gh/jgraph/drawio-desktop/releases/download/v${DRAWIO_VERSION}/drawio-amd64-${DRAWIO_VERSION}.deb" \
 && echo "${DRAWIO_SHA256}  /tmp/drawio.deb" | sha256sum -c - \
 && dpkg-deb -x /tmp/drawio.deb /tmp/drawio \
 && mv /tmp/drawio/opt/drawio /opt/drawio \
 && rm -rf /tmp/drawio /tmp/drawio.deb /tmp/epubcheck* /tmp/ca.crt

COPY bin/ /usr/local/bin/

# gemとnpmはロックファイルどおりに入れる。
WORKDIR /opt/toolchain
COPY Gemfile Gemfile.lock package.json package-lock.json ./
RUN --mount=type=secret,id=extra_ca,required=false \
    if [ -s /run/secrets/extra_ca ]; then \
      cat /etc/ssl/certs/ca-certificates.crt /run/secrets/extra_ca > /tmp/ca.crt; \
      export SSL_CERT_FILE=/tmp/ca.crt NODE_EXTRA_CA_CERTS=/tmp/ca.crt; \
    fi \
 && bundle config set --global frozen true \
 && bundle install --jobs 4 \
 && npm ci --omit=dev --no-audit --no-fund \
 && rm -rf /root/.npm /root/.bundle/cache /tmp/ca.crt

ENV PATH=/opt/toolchain/node_modules/.bin:$PATH \
    BUNDLE_GEMFILE=/opt/toolchain/Gemfile \
    BUNDLE_FROZEN=true

# LuaTeXのフォントキャッシュをイメージ内に作る。Noto CJKは初回の読み込みに1書体
# 数十秒かかるので、組版で使う書体をすべて一度読み込んでおく。実行時は任意のUIDで
# 動くため、書き込めるようにしておく（コンテナは使い捨て）。
ENV TEXMFCACHE=/opt/texmf-cache
COPY test/font-warmup.tex /tmp/warmup/font-warmup.tex
RUN mkdir -p "$TEXMFCACHE" \
 && luaotfload-tool --update --force \
 && cd /tmp/warmup \
 && lualatex -interaction=nonstopmode -halt-on-error font-warmup.tex > /dev/null \
 && cd / && rm -rf /tmp/warmup \
 && chmod -R a+rwX "$TEXMFCACHE"

COPY VERSION /opt/toolchain/VERSION
RUN toolchain-info > /opt/toolchain/versions.txt

WORKDIR /work
