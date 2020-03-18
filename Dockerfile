ARG BUILD_ARCH=x64

FROM forumi0721/alpine-${BUILD_ARCH}-base as builder

LABEL maintainer="forumi0721@gmail.com"

ENV TARGET_ARCH=x64

COPY local/. /usr/local/

RUN ["docker-init"]

ENTRYPOINT ["docker-run"]



FROM scratch

COPY --from=builder /build/dist/dist-alpine-x64 /

ENTRYPOINT ["docker-run"]

