#!/bin/bash
set -eu

output=$1
export JELLYFIN_VERSION=$3
npm ci --no-audit
npm run build:production
cp -a dist/. "$output/"
