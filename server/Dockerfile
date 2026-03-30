# Build the Lean server binary, then run it in a minimal container.
# The server connects to Postgres at db:5432 (Docker network).

FROM ubuntu:24.04 AS builder

# Install Lean toolchain + C library dependencies
RUN apt-get update && apt-get install -y \
    curl git build-essential \
    libssl-dev libpq-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install elan (Lean version manager)
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

WORKDIR /app

# Copy lakefile first for dependency caching
COPY lakefile.lean lean-toolchain ./
RUN lake update

# Copy source and build
COPY Server/ Server/
RUN lake build

# Runtime image
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    libssl3 libpq5 libcurl4 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/.lake/build/bin/server /usr/local/bin/server

EXPOSE 8000
CMD ["server"]
