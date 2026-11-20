# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Modifica rispetto a upstream (fase 5): rimossi i default `BUILDPLATFORM=linux/amd64`,
# `TARGETOS=linux` e `TARGETARCH=amd64`. Con BuildKit/buildx queste variabili sono
# valorizzate in automatico; i default le sovrascrivevano, quindi `--platform linux/arm64`
# produceva un binario amd64 e compilava in emulazione. Serve BuildKit (`docker buildx build`).
FROM --platform=$BUILDPLATFORM golang:1.27.0-alpine@sha256:4c9fe60190a2a3350ddc51de80d0224b8a6698d12bdfc999fee45ea9d6c46dbc AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src

# restore dependencies
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# Skaffold passes in debug-oriented compiler flags
ARG SKAFFOLD_GO_GCFLAGS
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 go build -ldflags="-s -w" -gcflags="${SKAFFOLD_GO_GCFLAGS}" -o /go/bin/frontend .

# Modifica rispetto a upstream (fase 5): tag `nonroot` e digest dell'indice multi-arch,
# per build riproducibili e utente non-root di default (hadolint DL3006).
FROM gcr.io/distroless/static:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931
WORKDIR /src
COPY --from=builder /go/bin/frontend /src/server
# Modifica rispetto a upstream (fase 5): --chmod fissa i permessi (sola lettura per tutti),
# così l'immagine non dipende dai modi dei file sull'host (su volumi esterni sono 0700 e
# l'utente non-root non potrebbe leggere i template).
COPY --chmod=a=rX ./templates ./templates
COPY --chmod=a=rX ./static ./static

# Definition of this variable is used by 'skaffold debug' to identify a golang binary.
# Default behavior - a failure prints a stack trace for the current goroutine.
# See https://golang.org/pkg/runtime/
ENV GOTRACEBACK=single

EXPOSE 8080
ENTRYPOINT ["/src/server"]
