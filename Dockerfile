FROM alpine:latest AS builder
RUN apk add --no-cache zig
WORKDIR /app
COPY . .
RUN zig build -Doptimize=ReleaseSafe

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/zig-out/bin/* ./app
EXPOSE 8080
CMD ["./app"]
