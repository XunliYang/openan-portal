# syntax=docker/dockerfile:1
#
# OpenAN Portal container image.
#
# The Portal is a pure frontend SPA: this image builds the static output
# (portal/dist/, source-mode plugins compiled in) and serves it with nginx.
# Backend services are deployed externally; their endpoints are injected at
# container start via environment variables (see default.conf.template):
#
#   docker build -t openan-portal .
#   docker run -p 8080:80 \
#       -e REGISTRY_URL=http://registry-host:5000 \
#       -e BACKEND_URL=http://orchestrate-host:5001 \
#       openan-portal

# ---- Build stage: compile the Portal SPA (Vite 8 requires Node >= 20.19) ----
FROM node:22-alpine AS build
WORKDIR /app

# Copy workspace manifests first so `npm ci` is cached independently of
# source changes. npm workspaces resolve from the repository root.
COPY package.json package-lock.json ./
COPY portal/package.json portal/
COPY packages/portal-sdk/package.json packages/portal-sdk/
COPY packages/shared-workflow/package.json packages/shared-workflow/
COPY plugins/demo-showcase/package.json plugins/demo-showcase/
COPY plugins/hello-portal/package.json plugins/hello-portal/
COPY plugins/orchestration-center/package.json plugins/orchestration-center/
COPY plugins/registry-center/package.json plugins/registry-center/

RUN npm ci

COPY . .
RUN npm run build

# ---- Runtime stage: nginx serves the static output ----
FROM nginx:alpine

COPY --from=build /app/portal/dist /usr/share/nginx/html

# envsubst template: the official nginx image renders this to
# /etc/nginx/conf.d/default.conf at container start, substituting
# ${REGISTRY_URL} and ${BACKEND_URL} from the environment.
COPY default.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 80
