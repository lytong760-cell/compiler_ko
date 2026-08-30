# Bước 1: Tải phiên bản Zig 0.13.0 chuẩn
FROM alpine:latest AS builder
RUN apk add --no-cache wget tar xz
WORKDIR /app

# Tải và giải nén Zig 0.13.0
RUN wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz && \
    tar -xf zig-linux-x86_64-0.13.0.tar.xz && \
    mv zig-linux-x86_64-0.13.0 /opt/zig

ENV PATH="/opt/zig:${PATH}"

# Build ứng dụng
COPY . .
RUN zig build-exe src/main.zig -O ReleaseSafe --name ko

# Bước 2: Tạo container chạy
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/ko ./ko
EXPOSE 8080
CMD ["./ko"]
