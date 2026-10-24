# OpenSSH terminates this notifier when signing completes or is cancelled.
if [ "${SSH_ASKPASS_PROMPT:-}" = none ]; then
  notification_id=
  sleeper=
  stopping=0
  close_notification() {
    if [ -n "$sleeper" ]; then
      kill "$sleeper" 2>/dev/null || true
      wait "$sleeper" 2>/dev/null || true
    fi
    case "$notification_id" in
      ''|*[!0-9]*) return ;;
    esac
    @gdbus@ call --session --dest org.freedesktop.Notifications \
      --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification \
      "$notification_id" >/dev/null 2>&1 || true
  }
  trap close_notification EXIT
  # Defer cleanup until notify-send has returned its ID, even if interrupted.
  trap 'stopping=1' TERM INT HUP
  notification_id=$(@notify@ --print-id --app-name='SSH security key' --icon=dialog-information \
    --urgency=normal --transient --expire-time=15000 \
    'Touch your YubiKey' 'Touch the sensor on your inserted YubiKey to finish SSH authentication.' \
    2>/dev/null) || exit 0
  while [ "$stopping" -eq 0 ]; do
    @sleep@ 1 &
    sleeper=$!
    wait "$sleeper" || true
  done
  exit 0
fi

# Keep credentials on inherited stdout; never capture or log them.
exec @askpass@ "$@"
