# alpine-base

#### [alpine-x64-base](https://hub.docker.com/r/forumi0721/alpine-x64-base/)
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/forumi0721/alpine-x64-base/latest)
![Docker Image Size (tag)](https://img.shields.io/docker/image-size/forumi0721/alpine-x64-base/latest)
![MicroBadger Layers (tag)](https://img.shields.io/microbadger/layers/forumi0721/alpine-x64-base/latest)
![Docker Pulls](https://img.shields.io/docker/pulls/forumi0721/alpine-x64-base)
![Docker Stars](https://img.shields.io/docker/stars/forumi0721/alpine-x64-base)
#### [alpine-aarch64-base](https://hub.docker.com/r/forumi0721/alpine-aarch64-base/)
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/forumi0721/alpine-aarch64-base/latest)
![Docker Image Size (tag)](https://img.shields.io/docker/image-size/forumi0721/alpine-aarch64-base/latest)
![MicroBadger Layers (tag)](https://img.shields.io/microbadger/layers/forumi0721/alpine-aarch64-base/latest)
![Docker Pulls](https://img.shields.io/docker/pulls/forumi0721/alpine-aarch64-base)
![Docker Stars](https://img.shields.io/docker/stars/forumi0721/alpine-aarch64-base)
#### [alpine-armhf-base](https://hub.docker.com/r/forumi0721/alpine-armhf-base/)
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/forumi0721/alpine-armhf-base/latest)
![Docker Image Size (tag)](https://img.shields.io/docker/image-size/forumi0721/alpine-armhf-base/latest)
![MicroBadger Layers (tag)](https://img.shields.io/microbadger/layers/forumi0721/alpine-armhf-base/latest)
![Docker Pulls](https://img.shields.io/docker/pulls/forumi0721/alpine-armhf-base)
![Docker Stars](https://img.shields.io/docker/stars/forumi0721/alpine-armhf-base)



----------------------------------------
#### Description

* Distribution : [Alpine Linux](https://alpinelinux.org/)
* Architecture : x64,aarch64,armhf
* Appplication : -



----------------------------------------
#### Run

```sh
docker run -i -t --rm \
           forumi0721/alpine-[ARCH]-base:latest
```



----------------------------------------
#### Usage

```dockerfile
FROM forumi0721/alpine-[ARCH]-base:latest

#For cross compile on dockerhub (aarch64,armhf)
RUN ["docker-build-start"]

RUN 'build-code'

#For cross compile on dockerhub  (aarch64,armhf)
RUN ["docker-build-end"]
```



----------------------------------------
#### Docker Options

| Option             | Description                                      |
|--------------------|--------------------------------------------------|
| -                  | -                                                |


#### Ports

| Port               | Description                                      |
|--------------------|--------------------------------------------------|
| -                  | -                                                |


#### Volumes

| Volume             | Description                                      |
|--------------------|--------------------------------------------------|
| -                  | -                                                |


#### Environment Variables

| ENV                | Description                                      |
|--------------------|--------------------------------------------------|
| -                  | -                                                |

