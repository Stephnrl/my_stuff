ARG NODE_VERSIONS="18.20.4 20.17.0 22.9.0 24.0.0"
ARG NODE_MIRROR="https://artifactory.example.com/artifactory/nodejs-org"

RUN mkdir -p $RUNNER_TOOL_CACHE && \
    for v in $NODE_VERSIONS; do \
        mkdir -p $RUNNER_TOOL_CACHE/node/${v}/x64 && \
        curl -fsSL "${NODE_MIRROR}/v${v}/node-v${v}-linux-x64.tar.xz" \
            | tar -xJ -C $RUNNER_TOOL_CACHE/node/${v}/x64 --strip-components=1 && \
        touch $RUNNER_TOOL_CACHE/node/${v}/x64.complete; \
    done
