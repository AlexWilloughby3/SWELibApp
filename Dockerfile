# Multi-stage build: formally verify and compile the Lean server,
# then copy just the binary into a slim runtime image.
#
# Build context must be the parent directory containing both SWELib/ and SWELibApp/.
# docker-compose.yml sets this automatically.

# Stage 1: build and verify
FROM debian:12-slim AS builder
RUN apt-get update -y && apt-get install -y \
    curl git build-essential pkg-config \
    libssl-dev libpq-dev libcurl4-openssl-dev libssh2-1-dev
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:$PATH"
WORKDIR /build
COPY SWELib ./SWELib
COPY SWELibApp ./SWELibApp
WORKDIR /build/SWELibApp
RUN lake build server

# Stage 2: runtime
FROM debian:12-slim
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    libpq5 libssl3 libcurl4 libssh2-1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/SWELibApp/.lake/build/bin/server /app/server
EXPOSE 8000
CMD ["/app/server"]
