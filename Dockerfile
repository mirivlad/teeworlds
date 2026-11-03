# Build Teeworlds with the server-side AI bots on a clean Debian toolchain.
FROM debian:bookworm AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential cmake python3 pkg-config zlib1g-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN cmake -S . -B /build -DCLIENT=OFF -DCMAKE_BUILD_TYPE=Release \
 && cmake --build /build --target teeworlds_srv -j 2

FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 zlib1g libgcc-s1 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 10001 teeworlds \
 && useradd --uid 10001 --gid 10001 --no-create-home teeworlds \
 && mkdir -p /srv/teeworlds /config \
 && chown -R teeworlds:teeworlds /config
COPY --from=build /build/teeworlds_srv /srv/teeworlds/teeworlds_srv
COPY --from=build /build/data /srv/teeworlds/data
COPY docker/entrypoint.sh /usr/local/bin/teeworlds-entrypoint
RUN chmod 0755 /usr/local/bin/teeworlds-entrypoint
WORKDIR /srv/teeworlds
ENV XDG_DATA_HOME=/config/data
USER teeworlds:teeworlds
VOLUME /config
EXPOSE 8303/udp
ENTRYPOINT ["/usr/local/bin/teeworlds-entrypoint"]
