#!/usr/bin/env bash
set -euo pipefail

# Instala deps base
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl git jq python3 python3-pip unzip make \
  build-essential gcc \
  libpcap-dev \
  golang-go

# Go env
export GOPATH=/root/go
export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"

# ProjectDiscovery
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Atualiza templates do nuclei
nuclei -update-templates || true

echo "OK: deps instaladas."
echo "Bins:"
which subfinder httpx naabu nuclei || true

