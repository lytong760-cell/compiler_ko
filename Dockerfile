# Bước 1: Tải phiên bản Zig 0.16.0 chuẩn
FROM alpine:latest AS builder
RUN apk add --no-cache wget tar xz
WORKDIR /app

# Tải và giải nén Zig 0.16.0
RUN wget https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz && \
    tar -xf zig-x86_64-linux-0.16.0.tar.xz && \
    mv zig-x86_64-linux-0.16.0 /opt/zig

ENV PATH="/opt/zig:${PATH}"

# Build ứng dụng qua build graph của build.zig
COPY . .
RUN zig build

# Bước 2: Tạo container chạy
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/zig-out/bin/ko ./ko
EXPOSE 8080
CMD ["./ko"]
