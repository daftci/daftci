# Dockerfile
# DAFt runtime image used by coordinator/reaper/runner/test-driver containers.
# Provides bash + git + yq + mc + bats.
# ARG BASE_IMAGE allows overriding the base from config.yaml.

ARG BASE_IMAGE=docker.io/library/alpine:3.19
FROM ${BASE_IMAGE}

# Install bash, git, coreutils (gtimeout), curl, ca-certs.
RUN apk add --no-cache bash git coreutils findutils grep sed gawk \
        curl ca-certificates jq bats openssh-client \
    && ln -sf /usr/bin/gtimeout /usr/local/bin/timeout

# Install yq (mikefarah).
RUN ARCH="$(uname -m)" \
    && case "${ARCH}" in \
         aarch64|arm64) YQ_ARCH=arm64 ;; \
         x86_64|amd64)  YQ_ARCH=amd64 ;; \
         *) echo "unsupported arch: ${ARCH}" >&2 ; exit 1 ;; \
       esac \
    && curl -sSfL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH}" \
         -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Install mc (MinIO client).
RUN ARCH="$(uname -m)" \
    && case "${ARCH}" in \
         aarch64|arm64) MC_ARCH=arm64 ;; \
         x86_64|amd64)  MC_ARCH=amd64 ;; \
         *) echo "unsupported arch: ${ARCH}" >&2 ; exit 1 ;; \
       esac \
    && curl -sSfL "https://dl.min.io/client/mc/release/linux-${MC_ARCH}/mc" \
         -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

# Default git identity for in-container commits.
RUN git config --system user.email 'daft-runner@compose.local' \
    && git config --system user.name 'daft-runner' \
    && git config --system commit.gpgsign false \
    && git config --system init.defaultBranch main

WORKDIR /work

CMD ["bash"]
