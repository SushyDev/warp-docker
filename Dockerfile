FROM debian:bullseye-slim

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

# Install dependencies, then remove build-time-only packages and clean up
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl gnupg lsb-release sudo jq ipcalc ca-certificates && \
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

RUN chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp

# Accept Cloudflare WARP TOS
RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV WARP_LICENSE_KEY=
ENV BETA_FIX_HOST_CONNECTIVITY=
ENV WARP_ENABLE_NAT=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
