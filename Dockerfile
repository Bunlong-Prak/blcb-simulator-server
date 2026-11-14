# syntax=docker/dockerfile:1
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.2.4
ARG DEBIAN_VERSION=bookworm-20250113-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ================================
# Builder Stage
# ================================
FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install Hex + Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib

# Compile assets
RUN mix assets.deploy

# Compile project
RUN mix compile

# Copy runtime config before release
COPY config/runtime.exs config/

# Assemble release
RUN mix release

# ================================
# Runner Stage
# ================================
FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV=prod
ENV PORT=4000
ENV PHX_SERVER=true

# Copy release artifact from builder
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/bl_simulator ./

USER nobody

EXPOSE 4000

CMD ["bin/bl_simulator", "start"]
