# alpine-base
![Docker Pulls](https://img.shields.io/docker/pulls/forumi0721/alpine-base)
![Docker Stars](https://img.shields.io/docker/stars/forumi0721/alpine-base)

#### x86_64
![Docker Image Version](https://img.shields.io/docker/v/forumi0721/alpine-base/latest)
![Docker Image Size](https://img.shields.io/docker/image-size/forumi0721/alpine-base/latest)
#### aarch64
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/forumi0721/alpine-base/aarch64)
![Docker Image Size (tag)](https://img.shields.io/docker/image-size/forumi0721/alpine-base/aarch64)



----------------------------------------
#### Description

* Distribution : [Alpine Linux](https://alpinelinux.org/)
* Architecture : x64,aarch64
* Appplication : -



----------------------------------------
#### Run

```sh
docker run -i -t --rm \
           forumi0721/alpine-base:[tag]
```



----------------------------------------
#### Usage

```dockerfile
FROM forumi0721/alpine-base:[tag]

#For cross compile on dockerhub (aarch64)
RUN ["docker-build-start"]

RUN 'build-code'

#For cross compile on dockerhub  (aarch64)
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

