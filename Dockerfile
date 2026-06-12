# ================================
# Build image
# ================================
FROM swift:6.3-noble AS build

WORKDIR /build

# Resolve dependencies first so they cache independently of source changes.
COPY ./Package.* ./
RUN swift package resolve

COPY . .

RUN swift build -c release --product App --static-swift-stdlib

WORKDIR /staging

RUN cp "$(swift build --package-path /build -c release --show-bin-path)/App" ./
RUN find -L "$(swift build --package-path /build -c release --show-bin-path)" -regex '.*\.resources$' -exec cp -Ra {} ./ \; || true

# ================================
# Run image
# ================================
FROM ubuntu:noble

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y ca-certificates tzdata libcurl4 \
    && rm -r /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

WORKDIR /app

COPY --from=build --chown=vapor:vapor /staging /app

USER vapor:vapor

EXPOSE 8080

ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
