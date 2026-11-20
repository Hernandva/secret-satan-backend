# ---- Build ----
FROM swift:6.0-jammy AS build
WORKDIR /build
COPY Package.swift Package.resolved* ./
RUN swift package resolve
COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --product App --static-swift-stdlib

# ---- Runtime ----
FROM ubuntu:jammy
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --user-group --create-home --system --no-log-init --home-dir /app vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /build/.build/release/App /app/App
RUN mkdir /data && chown vapor:vapor /data
USER vapor:vapor
ENV DATABASE_PATH=/data/db.sqlite
EXPOSE 8080
ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
