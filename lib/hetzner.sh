#!/bin/bash

HETZNER_API="https://api.hetzner.cloud/v1"

hetzner_create_server() {
  local name="$1"
  local user_data="$2"

  log "Creating Hetzner server: $name"

  local response=$(curl -s -X POST "$HETZNER_API/servers" \
    -H "Authorization: Bearer $HETZNER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"server_type\": \"cx22\",
      \"location\": \"nbg1\",
      \"image\": \"ubuntu-24.04\",
      \"user_data\": $(echo "$user_data" | jq -Rs .)
    }")

  local server_id=$(echo "$response" | jq -r '.server.id')
  if [[ "$server_id" == "null" || -z "$server_id" ]]; then
    error "Failed to create server: $(echo "$response" | jq -r '.error.message // "Unknown error"')"
  fi

  success "Server created: $server_id"
  echo "$server_id"
}

hetzner_get_ip() {
  local server_id="$1"

  log "Waiting for IP address..."
  for i in {1..30}; do
    local response=$(curl -s "$HETZNER_API/servers/$server_id" \
      -H "Authorization: Bearer $HETZNER_TOKEN")

    local ip=$(echo "$response" | jq -r '.server.public_net.ipv4.ip')
    if [[ "$ip" != "null" && -n "$ip" ]]; then
      success "IP assigned: $ip"
      echo "$ip"
      return 0
    fi

    sleep 2
  done

  error "Timeout waiting for IP"
}

hetzner_wait_ready() {
  local ip="$1"

  log "Waiting for SSH to be available..."
  for i in {1..60}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
       "root@$ip" "echo ready" &>/dev/null; then
      success "SSH ready"
      break
    fi
    sleep 5
  done

  log "Waiting for cloud-init to complete..."
  for i in {1..120}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
       "root@$ip" "cloud-init status --wait" 2>/dev/null; then
      success "Server ready"
      return 0
    fi
    sleep 5
  done

  error "Timeout waiting for cloud-init"
}
