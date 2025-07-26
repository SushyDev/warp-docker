# ---- Builder Stage ----
# This stage is only used to download and extract the gost binary.
FROM debian:bullseye-slim AS BUILDER

ARG GOST_URL
ARG TARGET_PLATFORM

# Install curl for downloading
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and extract gost in a single step
RUN set -ex && \
    echo "Downloading GOST for ${TARGETPLATFORM} from ${GOST_URL}" && \
    \
    # 1. Download to a temporary file. The -f flag fails on server errors (like 404).
    curl -fSL "${GOST_URL}" -o /tmp/gost.tar.gz && \
    \
    # 2. Extract only the 'gost' binary from the archive into the target directory.
    tar -xzf /tmp/gost.tar.gz -C /usr/local/bin/ gost && \
    \
    # 3. Make the binary executable and clean up the downloaded archive.
    chmod +x /usr/local/bin/gost && \
    rm /tmp/gost.tar.gz

# ---- Final Stage ----
FROM debian:bullseye-slim

ARG WARP_VERSION
ARG GOST_VERSION
ARG COMMIT_SHA
ARG TARGET_PLATFORM

LABEL org.opencontainers.image.authors="cmj2002"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL GOST_VERSION=${GOST_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

# Install dependencies, then remove build-time-only packages and clean up
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl gnupg lsb-release sudo jq ipcalc && \
    # Add cloudflare-warp repository
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    # Install cloudflare-warp
    apt-get update && \
    apt-get install -y --no-install-recommends cloudflare-warp && \
    # Remove build-time dependencies
    apt-get remove -y gnupg lsb-release && \
    apt-get autoremove -y && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy gost binary from builder stage and set up user
COPY --from=builder /usr/local/bin/gost /usr/bin/gost

RUN chmod +x /usr/bin/gost && \
    chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp

# Accept Cloudflare WARP TOS
RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV GOST_ARGS="-L :1080"
ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV WARP_LICENSE_KEY=
ENV BETA_FIX_HOST_CONNECTIVITY=
ENV WARP_ENABLE_NAT=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
