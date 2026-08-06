FROM golang:1.25-alpine

WORKDIR /app

COPY go.mod go.sum ./

RUN go mod download

COPY *.go ./

# Pure GO build without C dependencies
# Linux as target OS
# Compiler builds package and writes output binary "docker-gs-ping"
RUN CGO_ENABLED=0 GOOS=linux go build -o /docker-gs-ping

# Runs binary file
CMD ["/docker-gs-ping"]