ARG REGISTRY
ARG BOOTSTRAP_TAG
FROM ${REGISTRY}/runner-images/bootstrap:${BOOTSTRAP_TAG}

USER root

# --- Internal CA certs ---
COPY shared/certs/ /usr/local/share/ca-certificates/
RUN update-ca-certificates

# --- Apt: swap to JFrog mirror ---
COPY shared/jfrog-ubuntu-mirror.list /etc/apt/sources.list.d/jfrog.list
COPY shared/microsoft-packages.list /etc/apt/sources.list.d/microsoft.list
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update

# --- Tool configs that point at JFrog ---
COPY shared/.npmrc /etc/npmrc
COPY shared/pip.conf /etc/pip.conf
COPY shared/.terraformrc /etc/terraformrc

# Make sure the runner user picks them up too
RUN cp /etc/npmrc /home/runner/.npmrc && \
    cp /etc/terraformrc /home/runner/.terraformrc && \
    mkdir -p /home/runner/.config/pip && \
    cp /etc/pip.conf /home/runner/.config/pip/pip.conf && \
    chown -R runner:runner /home/runner/.npmrc /home/runner/.terraformrc /home/runner/.config

# --- Tell Node/npm/Java about the CA bundle ---
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

USER runner
