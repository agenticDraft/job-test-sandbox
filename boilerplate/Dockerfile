# Base image for job tests (FIRST-INSTALLATION.md, Task 3; spec Guardrails / Layer 2).
# Built once with `sandbox build`. Each project gets its own volume and container;
# this image is never modified per project.
FROM node:24-bookworm

# iptables: used only by the sandbox up firewall helper (bin/container-firewall.sh); without
# NET_ADMIN the work container cannot use it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip ca-certificates curl iptables \
 && rm -rf /var/lib/apt/lists/*

# Standalone code-server under /usr/local (https://coder.com/docs/code-server/install).
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/usr/local

# npm install scripts never run; one package at a time: npm rebuild <pkg> --ignore-scripts=false
ENV NPM_CONFIG_IGNORE_SCRIPTS=true
ENV LANG=C.UTF-8
# No credential is ever stored in the container.
RUN git config --system credential.helper ""

COPY sandbox-prompt.sh /etc/sandbox-prompt.sh
RUN useradd --create-home --shell /bin/bash dev \
 && mkdir -p /home/dev/project /home/dev/.local/share/code-server/User \
 && echo '. /etc/sandbox-prompt.sh' >> /home/dev/.bashrc \
 && chown -R dev:dev /home/dev
COPY --chown=dev:dev code-server-settings.json /home/dev/.local/share/code-server/User/settings.json

USER dev
WORKDIR /home/dev/project
