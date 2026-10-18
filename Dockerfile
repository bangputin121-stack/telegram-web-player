FROM golang:1.26 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go generate

# Normalise the generated TDLib library to the exact path main.go loads
# (./libtdjson.so.1.8.67). go generate may name or place it differently, so
# locate it (preferring /app) and fail the build if it is missing.
RUN set -eux; \
    lib="$(find /app / -xdev \( -type f -o -type l \) -name 'libtdjson.so*' 2>/dev/null | head -n 1)"; \
    test -n "$lib"; \
    echo "Found TDLib library at: $lib"; \
    if [ "$(readlink -f "$lib")" != "/app/libtdjson.so.1.8.67" ]; then \
        cp -L "$lib" /app/libtdjson.so.1.8.67; \
    fi; \
    ls -l /app/libtdjson.so.1.8.67

RUN CGO_ENABLED=0 GOOS=linux go build -o tgweb main.go

FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    ca-certificates \
    ffmpeg \
    curl \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*


RUN wget -O /usr/local/bin/yt-dlp \
    https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_linux \
    && chmod +x /usr/local/bin/yt-dlp

RUN curl -fsSL https://deno.land/install.sh | sh \
    && ln -sf /root/.deno/bin/deno /usr/local/bin/deno

ENV DENO_INSTALL="/root/.deno"
ENV PATH="${DENO_INSTALL}/bin:${PATH}"

COPY --from=builder /app/tgweb .
COPY --from=builder /app/libtdjson.so.1.8.67 ./libtdjson.so.1.8.67

CMD ["./tgweb"]
