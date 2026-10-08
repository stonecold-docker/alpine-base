FROM forumi0721/alpine-base:latest as builder

LABEL maintainer="forumi0721@gmail.com"

ARG BUILD_EDITION=latest

COPY local/. /usr/local/

RUN ["docker-build"]



FROM forumi0721/scratch:latest

LABEL maintainer="forumi0721@gmail.com"

COPY --from=builder /output/. /

ENTRYPOINT ["docker-run"]

