FROM mcr.microsoft.com/dotnet/sdk:10.0.404@sha256:fe0fd4e93bd2fbb47c883b7a6369e5c8d3db8bf01cdc5981f6ee35fbdf3ff4fb AS publish-server
WORKDIR /src
COPY . .
ARG DOTNET_RID
RUN dotnet publish Jellyfin.Server -c Release -r "${DOTNET_RID}" --self-contained true \
      -p:DebugSymbols=false -p:DebugType=none -o /out

FROM scratch AS server
COPY --from=publish-server /out/ /
