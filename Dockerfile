ARG BUILD_TAG=latest

FROM --platform=linux/amd64 forumi0721/alpine-buildbase:${BUILD_TAG} as builder

LABEL maintainer="forumi0721@gmail.com"

ENV TARGET_ARCH=x64

COPY local/. /usr/local/

RUN ["docker-init"]



FROM --platform=linux/amd64 scratch

LABEL maintainer="forumi0721@gmail.com"

COPY --from=builder /build/dist/dist-alpine-x64 /

#RUN ["docker-build-start"]

RUN ["docker-init"]

#RUN ["docker-build-end"]

ENTRYPOINT ["docker-run"]

