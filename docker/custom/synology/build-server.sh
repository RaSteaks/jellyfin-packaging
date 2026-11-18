#!/bin/bash
set -eu

output=$1
arch=$2
case "$arch" in
    amd64) rid=linux-x64 ;;
    arm64) rid=linux-arm64 ;;
esac
dotnet publish Jellyfin.Server -c Release -r "$rid" --self-contained true \
    -p:DebugSymbols=false -p:DebugType=none -o "$output"
