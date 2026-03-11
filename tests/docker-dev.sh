docker run -it --rm \
  --entrypoint /bin/sh \
  -v /Users/reggie.pierce/Projects/github-regbo/lfp-env:/lfp-env \
  debian:stable-slim \
  -c 'apt-get update && apt-get install -y curl && exec /bin/sh'