#!/usr/bin/env bash
set -euo pipefail

IFACE="${IPHONE_USB_IFACE:-iphoneusb}"
CON_NAME="${IPHONE_USB_CONNECTION:-iphone-usb-share}"
HOST_ADDR="${IPHONE_USB_HOST:-10.44.0.1/24}"
PHONE_ADDR="${IPHONE_USB_PHONE:-10.44.0.2}"
PHONE_MASK="${IPHONE_USB_MASK:-255.255.255.0}"
PHONE_GW="${IPHONE_USB_GW:-10.44.0.1}"
SSH_PORT="${IPHONE_SSH_PORT:-2222}"
SSH_USER="${IPHONE_SSH_USER:-mobile}"
SSH_IDENTITY="${IPHONE_SSH_IDENTITY:-/home/nick/.ssh/id_ed25519_sk_main}"
SSH_KNOWN_HOSTS="${IPHONE_SSH_KNOWN_HOSTS:-/home/nick/.hermes/cache/scratch/iphone-ssh-hostkey}"

log() { printf 'iphone-usb-share: %s\n' "$*"; }

ssh_phone() {
  local args=(
    -o BatchMode=yes
    -o ConnectTimeout=4
    -o IdentitiesOnly=yes
    -i "$SSH_IDENTITY"
    -o StrictHostKeyChecking=yes
    -p "$SSH_PORT"
  )
  if [[ -f "$SSH_KNOWN_HOSTS" ]]; then
    args+=(-o "UserKnownHostsFile=$SSH_KNOWN_HOSTS")
  fi
  ssh "${args[@]}" "${SSH_USER}@127.0.0.1" "$@"
}

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

  if ssh_phone 'true' >/dev/null 2>&1; then
    ssh_phone "sudo -n /var/jb/usr/sbin/ifconfig anpi0 ${PHONE_ADDR} netmask ${PHONE_MASK} up; sudo -n /var/jb/usr/sbin/route -n add default ${PHONE_GW} 2>/dev/null || sudo -n /var/jb/usr/sbin/route add default ${PHONE_GW}; if test -x /var/jb/usr/local/bin/usb-dns-probe; then sudo -n /var/jb/usr/local/bin/usb-dns-probe; fi" \
      || log "phone address/DNS helper failed (Linux share is still up)"
  else
    log "phone SSH not ready; Linux share is up on ${IFACE}"
  fi
}

down() {
  nmcli connection down "$CON_NAME" >/dev/null 2>&1 || true
}

case "${1:-up}" in
  up) up ;;
  down) down ;;
  *) log "usage: iphone-usb-share up|down"; exit 2 ;;
esac
