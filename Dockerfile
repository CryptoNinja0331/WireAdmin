FROM oven/bun:alpine as base
LABEL Maintainer="Shahrad Elahi <https://github.com/shahradelahi>"
WORKDIR /usr/src/app

ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY --from=chriswayg/tor-alpine:latest /usr/local/bin/obfs4proxy /usr/local/bin/obfs4proxy
COPY --from=chriswayg/tor-alpine:latest /usr/local/bin/meek-server /usr/local/bin/meek-server

# Set the mirror list
RUN echo "https://uk.alpinelinux.org/alpine/latest-stable/main" > /etc/apk/repositories && \
    echo "https://mirror.bardia.tech/alpine/latest-stable/main" >> /etc/apk/repositories && \
    echo "https://uk.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories &&\
    echo "https://mirror.bardia.tech/alpine/latest-stable/community" >> /etc/apk/repositories

# Update and upgrade packages
RUN apk update && apk upgrade

# Install required packages
RUN apk add -U --no-cache \
    iproute2 iptables net-tools \
    screen vim curl bash \
    wireguard-tools \
    openssl \
    dumb-init \
    tor \
    redis

# Clear cache
RUN rm -rf /var/cache/apk/*


FROM base AS deps

RUN mkdir -p /temp/dev
COPY web/package.json web/bun.lockb /temp/dev/
RUN cd /temp/dev && bun install --frozen-lockfile

RUN mkdir -p /temp/prod
COPY web/package.json web/bun.lockb /temp/prod/
RUN cd /temp/prod && bun install --frozen-lockfile --production


FROM base AS build
COPY --from=deps /temp/dev/node_modules node_modules
COPY web .

# build
ENV NODE_ENV=production
RUN bun run build


FROM base AS release

COPY --from=deps /temp/prod/node_modules node_modules
COPY --from=build /usr/src/app/build .
COPY --from=build /usr/src/app/package.json .

ENV NODE_ENV=production

# run the app
USER bun
EXPOSE 3000/tcp
CMD [ "bun", "start" ]
