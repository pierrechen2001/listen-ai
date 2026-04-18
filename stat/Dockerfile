FROM golang:1.23-alpine AS builder

WORKDIR /app

# Download dependencies first for better layer caching
COPY go.mod go.sum ./
RUN go mod download

# Copy and build the application
COPY . .
RUN go build -o stat .

FROM alpine:latest

WORKDIR /app

COPY --from=builder /app/stat .

EXPOSE 8002

CMD ["./stat"]
