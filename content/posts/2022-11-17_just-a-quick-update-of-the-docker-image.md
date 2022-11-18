---
title: "Just a Quick Update of the Docker Image"
date: 2022-11-17T13:37:08+01:00
draft: true
tags: ["til", "docker"]
---

The tale starts with a teammate updating the docker base image from `openjdk:11-jdk-buster` to `openjdk:17-jdk-slim`.
All the tests are green so it was merged.
And that started a small adventure through debugging docker containers.
<!--more-->

Because of course that would not work.
Well, actually the build of the container worked and the software was behaving normally.
Except for the fact that it got unresponsive for a few seconds every 10 minutes.

Setup: the service and it's dependencies (database, reverse proxy, ...) are deployed via docker-compose.

## Step 1: The health check
First we checked the logs with `docker logs`.
The service was starting anew every 10 minutes but no exceptions or any indication on why this is happening.
My first guess was somthing similar to liveness-probes from kubernetes.
Though I thought that docker(-compose) does not automatically restart containers unless they stopped by themselves.

Let's first check if there even is a healthcheck:
- there is none in the `Dockerfile` itself
- `docker inspect` shows a healthcheck on the container. And checking the docker-compose.yml confirms that the health check was added there.

The check is `curl localhost:8080`.
Hmm, the service behaves normally, so that should not be a problem.
Let's check ourselves:
`docker exec -it` into the container, try the curl command and:
```sh
# curl
sh: 1: curl: not found
```

The base image was changed to `*-slim` which in principle is a good idea, but that also means that curl is no longer installed by default.
That means the health check always fails.
And the inconspicuous `willfarrell/autoheal` container in the compose file will notice that and helpfully restarts the container once the check has failed often enough.

Simple fix:
Copy the boilder plate from the [docker best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#run) and install curl into the image.

Now the basic problem is fixed, but I noticed something else that seemed to be a simple fix: the `openjdk` image has a deprecation notice in it's documentation.

## Step 2: The base image
try eclipse temurin.
Run into a bunch of runtime errors.
run locally, it works

be very confused.
Try increasingly weird stuff, like pinning the image by sha256, looking into if jenkins does weird stuff to the runner
even looking into mvnw vs dash even though that makes no sense because it is the same image locally and on CI
patching mvnw script to print debug infos

playing with the different variants of the image and suddenly, one works.

## Step 3: The environment

experimenting why one works but the other does not
give up and google

find issue indicating old docker version, check and see: local docker 1.20 >> jenkins 1.19
accept the hint of the gods and just use the working base image

## Setp 4: Optimisations
multistage: use jre for final image
reoder stages to reduce image size
add health check
security: don't chown the binary to the runtime user
