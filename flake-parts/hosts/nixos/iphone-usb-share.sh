#!/usr/bin/env bash
set -euo pipefail

IFACE="${IPHONE_USB_IFACE:-iphoneusb}"
CON_NAME="${IPHONE_USB_CONNECTION:-iphone-usb-share}"
HOST_ADDR="${IPHONE_USB_HOST:-10.44.0.1/24}"

log() { printf 'iphone-usb-share: %s\n' "$*"; }

wait_iface() {
  local n=0
  while [[ ! -e "/sys/class/net/${IFACE}" ]]; do
    n=$((n + 1))
    if (( n > 30 )); then
      log "interface ${IFACE} did not appear"
      return 1
    fi
    sleep 0.2
  done
}

up() {
  wait_iface
  ip link set "$IFACE" up
  nmcli device set "$IFACE" managed yes || true

  if nmcli -t -f NAME connection show | grep -Fxq "$CON_NAME"; then
    nmcli connection modify "$CON_NAME" \
      connection.interface-name "$IFACE" \
      connection.autoconnect yes \
      connection.autoconnect-priority 200 \
      ipv4.method shared \
      ipv4.addresses "$HOST_ADDR" \
      ipv4.never-default yes \
      ipv6.method disabled
  else
    nmcli connection add type ethernet \
      ifname "$IFACE" \
      con-name "$CON_NAME" \
      autoconnect yes \
      connection.autoconnect-priority 200 \
      ipv4.method shared \
      ipv4.addresses "$HOST_ADDR" \
      ipv4.never-default yes \
      ipv6.method disabled
  fi

  # Wired profiles can steal USB NICs after a link change.
  while IFS=: read -r name type device _; do
    if [[ "$type" == "802-3-ethernet" && "$name" != "$CON_NAME" && "$device" == "$IFACE" ]]; then
      nmcli connection modify "$name" connection.autoconnect no || true
      nmcli device disconnect "$IFACE" || true
    fi
  done < <(nmcli -t -f NAME,TYPE,DEVICE connection show)

  nmcli connection up "$CON_NAME" ifname "$IFACE"

  # The phone's local.iphonex.usb-network launch daemon handles its address,
  # route, and configd DNS state on every reconnect. Do not authenticate from
  # this root service with a user's touch-required key or temporary host pin.
  log "Linux share is up on ${IFACE}; phone-side launchd handles reconnects"
}

down() {
  nmcli connection down "$CON_NAME" >/dev/null 2>&1 || true
}

case "${1:-up}" in
  up) up ;;
  down) down ;;
  *) log "usage: iphone-usb-share up|down"; exit 2 ;;
esac
