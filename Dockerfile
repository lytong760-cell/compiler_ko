# Bước 1: Build file thực thi trực tiếp bằng Zig
FROM alpine:latest AS builder
RUN apk add --no-cache zig
WORKDIR /app
COPY . .
RUN zig build-exe src/main.zig -O ReleaseSafe --name ko

# Bước 2: Tạo container nhẹ để chạy
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/ko ./ko
EXPOSE 8080
CMD ["./ko"]
