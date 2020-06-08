#!/usr/bin/env sh

progress='auto'
if [ "$DEBUG" != '0' ] && [ "$DEBUG" != 'false' ]; then
  progress='plain'
fi

DOCKER_BUILDKIT=1 docker build --build-arg BUILDKIT_INLINE_CACHE=1 --progress="$progress" .
