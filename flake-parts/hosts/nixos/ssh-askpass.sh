# OpenSSH's "none" hint is a touch reminder, not a password request.
# Keep credential output on the original stdout; never capture or log it.
notify_touch() {
  @notify@ --app-name='SSH security key' --icon=dialog-information \
    --urgency=normal --transient --expire-time=15000 \
    'Touch your YubiKey' 'Touch the sensor on your inserted YubiKey to finish SSH authentication.' \
    >/dev/null 2>&1 || true
}

if [ "${SSH_ASKPASS_PROMPT:-}" = none ]; then
  notify_touch
  exit 0
fi

@askpass@ "$@"
status=$?
if [ "$status" -eq 0 ]; then
  case "${1:-}" in
    'Enter PIN and confirm user presence '*) notify_touch ;;
  esac
fi
exit "$status"
