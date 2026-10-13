# syntax=docker/dockerfile:1
# Copyright (c) 2026 Huawei Technologies Co., Ltd.
# All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
# OpenAN Portal container image.
#
# The Portal is a pure frontend SPA: this image builds the static output
# (portal/dist/, source-mode plugins compiled in) and serves it with nginx.
# The runtime stage uses the unprivileged nginx image so the container runs
# as a non-root user under arbitrary UIDs (OpenShift-compatible), listening
# on port 8080. Backend endpoints default to the in-cluster service names
# (see 15-openan-backends.envsh) and can be overridden at container start:
#
#   docker build -t openan-portal .
#   docker run -p 8080:8080 openan-portal                       # in-cluster defaults
#   docker run -p 8080:8080 \
#       -e BACKEND_HOST=192.168.1.10 -e REGISTRY_HOST=192.168.1.11 \
#       openan-portal                                           # component override
#   docker run -p 8080:8080 \
#       -e REGISTRY_URL=http://registry-host:5000 \
#       -e BACKEND_URL=http://orchestrate-host:5001 \
#       openan-portal                                           # full URL override

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

# ---- Runtime stage: unprivileged nginx serves the static output ----
# nginxinc/nginx-unprivileged runs as the nginx user (uid 101) and tolerates
# arbitrary UIDs with GID 0, as enforced by OpenShift's restricted SCC.
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY --from=build /app/portal/dist /usr/share/nginx/html

# envsubst template: rendered to /etc/nginx/conf.d/default.conf at container
# start, substituting ${REGISTRY_URL} and ${BACKEND_URL} from the environment.
COPY default.conf.template /etc/nginx/templates/default.conf.template

COPY 15-openan-backends.envsh /docker-entrypoint.d/15-openan-backends.envsh

# The unprivileged base image builds as uid 101; escalate briefly to
# normalize line endings (CRLF Windows checkout) and set the exec bit —
# the nginx entrypoint only sources executable *.envsh files.
USER root
RUN sed -i 's/\r$//' /docker-entrypoint.d/15-openan-backends.envsh \
    && chmod 0755 /docker-entrypoint.d/15-openan-backends.envsh
USER nginx

# Backend endpoint components; defaults match the in-cluster service names.
ENV REGISTRY_HOST=registry-center \
    REGISTRY_PORT=5000 \
    REGISTRY_SCHEME=http \
    BACKEND_HOST=orchestration-center \
    BACKEND_PORT=5001 \
    BACKEND_SCHEME=http

EXPOSE 8080
