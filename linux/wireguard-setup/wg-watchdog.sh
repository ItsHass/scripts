#!/usr/bin/env bash
#
# wg-watchdog - restart ACTIVE wg-quick interfaces whose last handshake is stale.
#
# Only interfaces that are currently up (per `wg show interfaces`) AND managed by
# a running wg-quick@<iface>.service are considered. Configs sitting in
# /etc/wireguard that aren't active are ignored.
#
# Logs verbosely to a file; prints to the console too when run interactively
# (TTY), or with --console / --dry-run / --force.
#
# Must run as root.
#
#
# sudo install -m 750 wg-watchdog.sh /usr/local/sbin/wg-watchdog
# echo '* * * * * root /usr/local/sbin/wg-watchdog' | sudo tee /etc/cron.d/wg-watchdog
#
#/var/log/wg-watchdog.log {
#    weekly
#    rotate 8
#    compress
#    missingok
#    notifempty
#}
#
# sudo wg-watchdog --dry-run                # report only, restart nothing
# sudo wg-watchdog --force -i wg0           # restart wg0 now, regardless of age
# sudo wg-watchdog -t 60 --dry-run          # try a 60s threshold
#


set -uo pipefail

THRESHOLD=600                      # seconds (10 minutes)
LOG_FILE="/var/log/wg-watchdog.log"
LOCK_FILE="/run/wg-watchdog.lock"
DRY_RUN=0
FORCE=0
CONSOLE=0
ONLY=()

# Print to the console automatically when run from an interactive terminal
[[ -t 1 ]] && CONSOLE=1

usage() {
  cat <<EOF
Usage: ${0##*/} [options]

  -t, --threshold SECS   Restart if last handshake is older than SECS (default: $THRESHOLD)
  -i, --interface NAME   Only check this interface (repeatable). Default: all active ones
  -l, --log-file PATH    Log file (default: $LOG_FILE)
  -c, --console          Also print log output to the terminal
  -n, --dry-run          Report what would happen, restart nothing (implies --console)
  -f, --force            Restart matching active interfaces regardless of handshake age
                         (implies --console)
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--threshold) THRESHOLD="${2:?missing value for $1}"; shift 2 ;;
    -i|--interface) ONLY+=("${2:?missing value for $1}"); shift 2 ;;
    -l|--log-file)  LOG_FILE="${2:?missing value for $1}"; shift 2 ;;
    -c|--console)   CONSOLE=1; shift ;;
    -n|--dry-run)   DRY_RUN=1; CONSOLE=1; shift ;;
    -f|--force)     FORCE=1; CONSOLE=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

if ! [[ $THRESHOLD =~ ^[0-9]+$ ]]; then
  echo "Threshold must be a whole number of seconds." >&2
  exit 2
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE" && chmod 640 "$LOG_FILE"

log() {
  local level=$1; shift
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S%z') [$level] $*"
  printf '%s\n' "$line" >> "$LOG_FILE"
  (( CONSOLE )) && printf '%s\n' "$line"
  return 0
}

human() {
  local s=$1
  printf '%dh %02dm %02ds' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
}

# Prevent overlapping runs (e.g. cron firing while a restart is in progress)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log WARN "Another instance is already running; exiting"
  exit 0
fi

for cmd in wg systemctl flock; do
  command -v "$cmd" >/dev/null 2>&1 || { log ERROR "Required command not found: $cmd"; exit 1; }
done

log INFO "=== run start (threshold=${THRESHOLD}s dry_run=$DRY_RUN force=$FORCE) ==="

read -ra IFACES <<< "$(wg show interfaces 2>/dev/null)"

if (( ${#IFACES[@]} == 0 )); then
  log INFO "No active WireGuard interfaces found; nothing to do"
  log INFO "=== run end ==="
  exit 0
fi

log INFO "Active WireGuard interfaces: ${IFACES[*]}"

FAILED=0

for iface in "${IFACES[@]}"; do
  # Optional interface filter
  if (( ${#ONLY[@]} )) && ! printf '%s\n' "${ONLY[@]}" | grep -qxF -- "$iface"; then
    log DEBUG "$iface: not in --interface list; skipping"
    continue
  fi

  unit="wg-quick@${iface}.service"

  # Only touch interfaces that wg-quick's systemd unit is actually running
  if ! systemctl is-active --quiet "$unit"; then
    log INFO "$iface: interface is up but $unit is not active (not managed by wg-quick@); skipping"
    continue
  fi

  now=$(date +%s)

  peer_count=$(wg show "$iface" peers | wc -l)
  if (( peer_count == 0 )); then
    log INFO "$iface: no peers configured; skipping"
    continue
  fi

  # Newest handshake across all peers (0 = never)
  latest=0
  while read -r peer ts; do
    [[ -z ${peer:-} ]] && continue
    if (( ts == 0 )); then
      log DEBUG "$iface: peer ${peer:0:8}... has never completed a handshake"
    else
      log DEBUG "$iface: peer ${peer:0:8}... last handshake $(human $((now - ts))) ago"
      (( ts > latest )) && latest=$ts
    fi
  done < <(wg show "$iface" latest-handshakes)

  # When did the unit last (re)start? Needed so a never-connected tunnel is
  # measured from its start time, and so a fresh restart gets a full grace period.
  started_str=$(systemctl show -p ActiveEnterTimestamp --value "$unit" 2>/dev/null)
  started=0
  [[ -n $started_str ]] && started=$(date -d "$started_str" +%s 2>/dev/null || echo 0)

  reference=$latest
  (( started > reference )) && reference=$started

  if (( reference == 0 )); then
    log WARN "$iface: cannot determine handshake or start time; skipping"
    continue
  fi

  age=$((now - reference))

  if (( latest == 0 )); then
    basis="no handshake yet, measured from unit start"
  else
    basis="newest handshake across $peer_count peer(s)"
  fi

  log INFO "$iface: age=$(human "$age") (${age}s) [$basis], threshold=${THRESHOLD}s, unit up since ${started_str:-unknown}"

  if (( FORCE )); then
    reason="forced"
  elif (( age >= THRESHOLD )); then
    reason="handshake stale (${age}s >= ${THRESHOLD}s)"
  else
    log INFO "$iface: healthy; no action"
    continue
  fi

  if (( DRY_RUN )); then
    log INFO "$iface: DRY RUN - would run: systemctl restart $unit ($reason)"
    continue
  fi

  log WARN "$iface: restarting $unit ($reason)"
  if out=$(systemctl restart "$unit" 2>&1); then
    sleep 3
    if systemctl is-active --quiet "$unit"; then
      log INFO "$iface: restart OK; $unit is active"
    else
      log ERROR "$iface: restart returned success but $unit is not active"
      FAILED=1
    fi
  else
    log ERROR "$iface: restart FAILED: $out"
    journalctl -u "$unit" -n 15 --no-pager 2>&1 | while IFS= read -r l; do log ERROR "$iface: journal: $l"; done
    FAILED=1
  fi
done

log INFO "=== run end ==="
exit $FAILED
