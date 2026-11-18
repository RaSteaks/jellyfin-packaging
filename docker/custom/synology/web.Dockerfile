FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS publish-web
RUN apk add --no-cache alpine-sdk autoconf automake libtool nasm python3 git libpng-dev gifsicle
WORKDIR /src
COPY . .
ARG JELLYFIN_VERSION
RUN npm ci --no-audit && npm run build:production

FROM scratch AS web
COPY --from=publish-web /src/dist/ /
