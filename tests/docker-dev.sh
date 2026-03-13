docker run -it --rm \
  --entrypoint /bin/sh \
  -v $PWD:/lfp-env:ro \
  debian:stable-slim \
  -c 'apt-get update && apt-get install -y curl && exec /bin/sh'

# LFP_ENV_LOG_LEVEL=debug && eval "$(sh /lfp-env/install.sh)"