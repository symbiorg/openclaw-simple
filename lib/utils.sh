#!/bin/bash

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
error() { log "ERROR: $*"; exit 1; }
success() { log "✓ $*"; }

validate() {
  [[ -z "$HETZNER_TOKEN" ]] && error "Set HETZNER_TOKEN"
  [[ -z "$TAILSCALE_KEY" ]] && error "Set TAILSCALE_KEY"
  [[ -z "$ANTHROPIC_KEY" ]] && error "Set ANTHROPIC_KEY"

  # Test Hetzner API
  if ! curl -sf -H "Authorization: Bearer $HETZNER_TOKEN" \
    https://api.hetzner.cloud/v1/servers?per_page=1 >/dev/null; then
    error "Invalid Hetzner token"
  fi

  success "Credentials valid"
}
