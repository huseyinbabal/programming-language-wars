FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /cache .

FROM gcr.io/distroless/static-debian12
COPY --from=build /cache /cache
EXPOSE 8000
ENTRYPOINT ["/cache"]
