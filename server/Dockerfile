# --- build ---
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY . .
# go.sum hiányában az első buildnél feloldja a függőségeket; commitold a go.sum-ot a reprodukálhatósághoz.
RUN go mod tidy && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/pinty-server .

# --- futtatás ---
FROM alpine:3.20
RUN adduser -D -u 10001 pinty && mkdir -p /data && chown pinty /data
USER pinty
ENV PINTY_DATA=/data PINTY_ADDR=:8080
COPY --from=build /out/pinty-server /usr/local/bin/pinty-server
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["pinty-server"]
