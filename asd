ARG REGISTRY
ARG BASE_TAG
FROM ${REGISTRY}/runners/base:${BASE_TAG}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        dotnet-sdk-6.0 \
    && rm -rf /var/lib/apt/lists/*
USER runner



ARG REGISTRY
ARG BASE_TAG
FROM ${REGISTRY}/runners/base:${BASE_TAG}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        dotnet-sdk-8.0 \
    && rm -rf /var/lib/apt/lists/*
USER runner



ARG REGISTRY
ARG BASE_TAG
FROM ${REGISTRY}/runners/base:${BASE_TAG}

USER root
RUN if apt-cache show dotnet-sdk-10.0 >/dev/null 2>&1; then \
        apt-get update && apt-get install -y --no-install-recommends dotnet-sdk-10.0 \
            && rm -rf /var/lib/apt/lists/*; \
    else \
        curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
            && bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet \
            && ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
            && rm /tmp/dotnet-install.sh; \
    fi
USER runner





version: v1.1.0
stepTimeout: 3600
steps:
  - id: build-base
    build: >
      -t $Registry/runners/base:$ID
      -t $Registry/runners/base:latest
      --build-arg JFROG_PS_URL={{.Values.jfrogUrl}}
      -f base/Dockerfile .

  - id: push-base
    push:
      - $Registry/runners/base:$ID
      - $Registry/runners/base:latest
    when: ['build-base']

  - id: build-dotnet6
    build: >
      -t $Registry/runners/dotnet6:$ID
      -t $Registry/runners/dotnet6:latest
      --build-arg REGISTRY=$Registry
      --build-arg BASE_TAG=$ID
      -f dotnet6/Dockerfile .
    when: ['push-base']

  - id: build-dotnet8
    build: >
      -t $Registry/runners/dotnet8:$ID
      -t $Registry/runners/dotnet8:latest
      --build-arg REGISTRY=$Registry
      --build-arg BASE_TAG=$ID
      -f dotnet8/Dockerfile .
    when: ['push-base']

  - id: build-dotnet10
    build: >
      -t $Registry/runners/dotnet10:$ID
      -t $Registry/runners/dotnet10:latest
      --build-arg REGISTRY=$Registry
      --build-arg BASE_TAG=$ID
      -f dotnet10/Dockerfile .
    when: ['push-base']

  - id: push-variants
    push:
      - $Registry/runners/dotnet6:$ID
      - $Registry/runners/dotnet6:latest
      - $Registry/runners/dotnet8:$ID
      - $Registry/runners/dotnet8:latest
      - $Registry/runners/dotnet10:$ID
      - $Registry/runners/dotnet10:latest
    when: ['build-dotnet6', 'build-dotnet8', 'build-dotnet10']
