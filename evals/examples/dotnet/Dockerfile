FROM mcr.microsoft.com/dotnet/sdk:10.0.404 AS build
WORKDIR /src
COPY global.json Directory.Build.props Directory.Packages.props ./
COPY src/Orders.Api/Orders.Api.csproj src/Orders.Api/packages.lock.json src/Orders.Api/
RUN dotnet restore src/Orders.Api/Orders.Api.csproj --locked-mode
COPY src/ src/
# The image build has no .git; the pipeline passes the sha for the version.
ARG CI_COMMIT_SHA
RUN dotnet publish src/Orders.Api/Orders.Api.csproj --configuration Release --no-restore --output /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0.15
# The runtime image has no HTTP client for the health check.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app ./
USER $APP_UID
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
    CMD ["curl", "--fail", "--silent", "--output", "/dev/null", "http://127.0.0.1:8080/health"]
ENTRYPOINT ["dotnet", "Orders.Api.dll"]
