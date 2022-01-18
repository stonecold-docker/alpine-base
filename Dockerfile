ARG BASE_TAG=x64

FROM forumi0721/alpine-base:${BASE_TAG} as builder

LABEL maintainer="forumi0721@gmail.com"

ARG BUILD_TAG=x64

COPY local/bin/docker-build /usr/local/bin/

RUN ["docker-build"]



FROM forumi0721/scratch:x64

LABEL maintainer="forumi0721@gmail.com"

COPY --from=builder /output/. /

ENTRYPOINT ["docker-run"]

