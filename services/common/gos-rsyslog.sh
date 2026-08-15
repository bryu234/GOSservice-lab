#!/usr/bin/env bash
set -euo pipefail

config_dir="${GOS_RSYSLOG_CONFIG_DIR:-/etc/rsyslog.d}"
config_file="$config_dir/10-gos-local-audit.conf"
marker_file="$config_dir/.gos-local-audit-initialized"

write_enabled_config() {
  cat >"$config_file" <<'EOF'
if ($syslogfacility-text == "auth" or $syslogfacility-text == "authpriv") then {
  action(type="omfile" file="/var/log/auth.log")
  stop
}

if ($syslogfacility-text != "mail") then {
  action(type="omfile" file="/var/log/syslog")
  stop
}
EOF
}

write_disabled_config() {
  cat >"$config_file" <<'EOF'
# if ($syslogfacility-text == "auth" or $syslogfacility-text == "authpriv") then {
#   action(type="omfile" file="/var/log/auth.log")
#   stop
# }
#
# if ($syslogfacility-text != "mail") then {
#   action(type="omfile" file="/var/log/syslog")
#   stop
# }
EOF
}

initialize_config() {
  local initial_state="${1:?initial rsyslog state is required}"

  mkdir -p "$config_dir"
  if [[ -e "$marker_file" ]]; then
    return
  fi

  if [[ ! -e "$config_file" ]]; then
    case "$initial_state" in
      enabled)
        write_enabled_config
        ;;
      disabled)
        write_disabled_config
        ;;
      *)
        echo "Unknown initial rsyslog state: $initial_state" >&2
        return 1
        ;;
    esac
    chmod 0644 "$config_file"
  fi

  touch "$marker_file"
}

local_audit_is_enabled() {
  grep -Eq '^[[:space:]]*if[[:space:]]*\(' "$config_file" 2>/dev/null
}

start_rsyslog() {
  local mode="${1:?rsyslog start mode is required}"
  local should_start="false"

  case "$mode" in
    required)
      should_start="true"
      ;;
    optional)
      if local_audit_is_enabled; then
        should_start="true"
      fi
      ;;
    mail)
      if local_audit_is_enabled || [[ -f "$config_dir/30-postfix.conf" ]]; then
        should_start="true"
      fi
      ;;
    *)
      echo "Unknown rsyslog start mode: $mode" >&2
      return 1
      ;;
  esac

  if [[ "$should_start" != "true" ]]; then
    return
  fi

  rm -f /run/rsyslogd.pid
  if rsyslogd -N1; then
    rsyslogd || echo "rsyslog failed to start; continuing without local audit." >&2
  else
    echo "Invalid rsyslog configuration; local audit was not started." >&2
  fi
}

case "${1:-}" in
  initialize)
    initialize_config "${2:-}"
    ;;
  start)
    start_rsyslog "${2:-}"
    ;;
  *)
    echo "Usage: $0 {initialize enabled|disabled|start required|optional|mail}" >&2
    exit 2
    ;;
esac
