#!/usr/bin/env sh

progress='auto'
if [ "$DEBUG" != '0' ] && [ "$DEBUG" != 'false' ]; then
  progress='plain'
fi

IMAGE_NAME=${IMAGE_NAME:-djbender/passenger-nginx-alpine}

DOCKER_BUILDKIT=1 docker build --build-arg BUILDKIT_INLINE_CACHE=1 --progress="$progress" --tag "$IMAGE_NAME" .
