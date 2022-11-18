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
Also add `HEALTHCHECK` to the Dockerfile itself to make the origin of the dependency obvious.

Now the basic problem is fixed, but I noticed something else that seemed to be a simple fix: the `openjdk` image has a deprecation notice in it's documentation.

## Step 2: The base image
Thankfully the deprecation also provides a few alternative images that should be actively supported.
After cross-checking the list with [whichjdk.com/](https://whichjdk.com/), I decided to try migrating to `eclipse-temurin`.

After replacing the base image and running a successful local `docker build`, I committed the changes and went for lunch.
That was as easy as I hoped it to be.

But when I came back after the break, the CI Jenkins server did not agree with my assessment.
For some reason the build failed when executing `./mvnw package`, which is... unexpected.

```
# docker build .
[...]
Step 11/22 : RUN ./mvnw clean package
 ---> Running in 3eee9a97e249
[91mError: JAVA_HOME is not defined correctly.
  We cannot execute /opt/java/openjdk/bin/java
[0mThe command '/bin/sh -c ./mvnw clean package' returned a non-zero code: 1
```

Once a Dockerfile has been successfully built, it is supposed to work anywhere.
So why isn't it working in the CI?
I ran down any rabithole I could think of, including:
- adding printf-style logging to the mvnw script via `set -x` and checking that `java` is actually a binary
- patching out the mvnw check in the script
- pinning the container image by specifying `eclipse-temurin:17-jdk@sha256:333ff936365bd7187f7bb943194f9581a4a84a1e925a826399ae7fd8de078965` to avoid the CI pulling a different image (possible if it had a different cpu architecture)
- a quick look, if the jenkins runner could be using a different shell that broke the script (totally not possible since 1) the script specifies it's interpreter and 2) how could jenkins even do that in the general case)

Just before giving up, I decided to play around with the different image variants, since there was an image for ubuntu jammy (default) and focal.
And to my surprise, the `eclipse-temurin:17-jdk-focal` image works?!

## Step 3: The environment
experimenting why one works but the other does not
give up and google

```
Step 11/22 : RUN ./mvnw clean package
 ---> Running in 5f55c1fd9436
[91mError: JAVA_HOME is not defined correctly.
  We cannot execute /opt/java/openjdk/bin/java
[0m[91m--2022-11-18 22:34:23--  https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.1.1/maven-wrapper-3.1.1.jar
[0m[91mResolving repo.maven.apache.org (repo.maven.apache.org)... [0m[91m151.101.112.215
Connecting to repo.maven.apache.org (repo.maven.apache.org)|151.101.112.215|:443... [0m[91mconnected.
[0m[91mHTTP request sent, awaiting response... [0m[91m200 OK
Length: 59925 (59K) [application/java-archive]
[0m[91mSaving to: ‘/tmp/.mvn/wrapper/maven-wrapper.jar’
[0m[91m
     0K .[0m[91m.[0m[91m..[0m[91m.[0m[91m.[0m[91m..[0m[91m.[0m[91m.[0m[91m ..[0m[91m.[0m[91m...[0m[91m..[0m[91m.[0m[91m. ..[0m[91m.[0m[91m.[0m[91m..[0m[91m.[0m[91m.[0m[91m..[0m[91m ..[0m[91m...[0m[91m..... .......... 85% 4.07M 0s
    50K ........                                      [0m[91m        100% 12.2M=0.01s

[0m[91m2022-11-18 22:34:24 (4.51 MB/s) - ‘/tmp/.mvn/wrapper/maven-wrapper.jar’ saved [59925/59925]

[0m[0.066s][warning][os,thread] Failed to start thread "GC Thread#0" - pthread_create failed (EPERM) for attributes: stacksize: 1024k, guardsize: 4k, detached.
#
# There is insufficient memory for the Java Runtime Environment to continue.
# Cannot create worker GC thread. Out of system resources.
# An error report file with more information is saved as:
# /tmp/hs_err_pid6.log
The command '/bin/sh -c ./mvnw clean package' returned a non-zero code: 1
```
find issue indicating old docker version, check and see: local docker 1.20 >> jenkins 1.19
accept the hint of the gods and just use the working base image

## Setp 4: Optimisations
multistage: use jre for final image
reorder stages to reduce image size
security: don't chown the binary to the runtime user
