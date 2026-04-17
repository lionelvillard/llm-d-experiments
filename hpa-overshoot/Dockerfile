FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /hpa-overshoot .

FROM alpine:3.19
COPY --from=builder /hpa-overshoot /usr/local/bin/hpa-overshoot
ENTRYPOINT ["hpa-overshoot"]
