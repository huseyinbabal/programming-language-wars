FROM rust:1.98 AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked

FROM gcr.io/distroless/cc-debian12
COPY --from=build /src/target/release/cache /cache
EXPOSE 8000
ENTRYPOINT ["/cache"]
