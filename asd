RUN apk add --no-cache curl unzip ca-certificates gnupg \
  && curl -fsSLo /tmp/terraform.zip \
    "${HASHICORP_MIRROR}/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
  && curl -fsSLo /tmp/terraform_SHA256SUMS \
    "${HASHICORP_MIRROR}/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
  && cd /tmp \
  && grep "terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" terraform_SHA256SUMS | sha256sum -c - \
  && unzip /tmp/terraform.zip -d /usr/local/bin \
  && chmod +x /usr/local/bin/terraform \
  && terraform version \
  && rm -f /tmp/terraform.zip /tmp/terraform_SHA256SUMS
