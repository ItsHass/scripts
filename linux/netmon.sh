#!/usr/bin/env bash
#
# netmon.sh — Network connectivity / outbound traffic monitor
# ------------------------------------------------------------
# Purpose: run continuously on a hosted Linux server to record connectivity
# health (gateway, DNS, external hosts, HTTP outbound) and automatically
# capture deep diagnostics the moment a problem is seen, so you have hard
# evidence to give your hosting/network provider when UptimeRobot reports
# timeouts.
#
# It answers the question: "when the outside world sees a timeout, is the
# problem INSIDE this box (NIC errors, local resource exhaustion, DNS
# resolver) or OUTSIDE it (gateway/upstream/ISP)?"
#
# USAGE
#   sudo ./netmon.sh                # run in foreground
#   sudo ./netmon.sh &              # run in background
#   (see bottom of file for systemd service, which is the recommended way)
#
# OUTPUT
#   $LOG_DIR/netmon.csv       - one row per check cycle (easy to graph/analyse)
#   $LOG_DIR/netmon.log       - human-readable running log
#   $LOG_DIR/incidents/       - one file per detected incident with full
#                               diagnostics (traceroute/mtr, ss, ip -s link,
#                               uptime/load) captured at the time of failure
#
# Requires: bash, ping, curl, ip, awk, getent. Optional: mtr, traceroute.
# ------------------------------------------------------------

set -u

### ---------------------- CONFIG ---------------------------------------

# How often to run a check cycle, in seconds.
INTERVAL="${INTERVAL:-30}"

# Hosts to ping by IP (bypasses DNS) — pick stable, high-uptime anycast IPs.
PING_TARGETS=("1.1.1.1" "8.8.8.8" "9.9.9.9")

# Domain to resolve to test DNS resolution specifically.
DNS_TEST_DOMAIN="cloudflare.com"

# HTTP(S) endpoint(s) to test real outbound traffic (TLS + HTTP layer).
HTTP_TARGETS=("https://www.cloudflare.com" "https://www.google.com")

# Packet loss % on a target that counts as a "failure" for that target.
LOSS_THRESHOLD=20

# curl max time (seconds) before it's considered a timeout/failure.
CURL_MAX_TIME=8

# Number of pings sent per target per cycle.
PING_COUNT=4

# Where to write logs / evidence.
LOG_DIR="${LOG_DIR:-/var/log/netmon}"
CSV_FILE="$LOG_DIR/netmon.csv"
LOG_FILE="$LOG_DIR/netmon.log"
INCIDENT_DIR="$LOG_DIR/incidents"

# Minimum seconds between two incident-capture bundles (avoid spamming
# diagnostics if the link is flapping badly).
INCIDENT_COOLDOWN=60

### ---------------------- SETUP ------------------------------------------

mkdir -p "$LOG_DIR" "$INCIDENT_DIR"

if command -v mtr >/dev/null 2>&1; then
    TRACE_CMD="mtr"
elif command -v traceroute >/dev/null 2>&1; then
    TRACE_CMD="traceroute"
else
    TRACE_CMD=""
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S%z') $*" | tee -a "$LOG_FILE"
}

# Init CSV header if new file
if [ ! -f "$CSV_FILE" ]; then
    echo "timestamp,gateway_ip,gateway_loss_pct,gateway_avg_rtt_ms,ext_targets_loss_summary,dns_ok,dns_time_ms,http_summary,iface,iface_rx_errors,iface_tx_errors,iface_rx_dropped,iface_tx_dropped,load1,cycle_status" > "$CSV_FILE"
fi

last_incident_time=0

### ---------------------- HELPER FUNCTIONS --------------------------------

get_default_iface() {
    ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

get_default_gateway() {
    ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

# ping_target <ip> -> prints "loss_pct avg_rtt_ms" (avg may be blank if 100% loss)
ping_target() {
    local target="$1"
    local out loss avg
    out=$(ping -n -c "$PING_COUNT" -W 2 "$target" 2>/dev/null)
    loss=$(echo "$out" | awk -F', ' '/packet loss/ {for(i=1;i<=NF;i++) if ($i ~ /packet loss/) print $i}' | grep -oE '[0-9]+(\.[0-9]+)?%' | tr -d '%')
    avg=$(echo "$out" | awk -F'/' '/rtt|round-trip/ {print $5}')
    [ -z "$loss" ] && loss=100
    echo "${loss} ${avg}"
}

# dns_resolve_time -> prints resolution time in ms, or "FAIL"
dns_resolve_time() {
    local start end
    start=$(date +%s%N)
    if getent hosts "$DNS_TEST_DOMAIN" >/dev/null 2>&1; then
        end=$(date +%s%N)
        echo $(( (end - start) / 1000000 ))
    else
        echo "FAIL"
    fi
}

# http_check <url> -> prints "code total_time_ms" or "FAIL 0"
http_check() {
    local url="$1"
    local result
    result=$(curl -o /dev/null -s --max-time "$CURL_MAX_TIME" \
        -w "%{http_code} %{time_total}" "$url" 2>/dev/null)
    if [ -z "$result" ]; then
        echo "FAIL 0"
    else
        local code time_s time_ms
        code=$(echo "$result" | awk '{print $1}')
        time_s=$(echo "$result" | awk '{print $2}')
        time_ms=$(awk -v t="$time_s" 'BEGIN{printf "%.0f", t*1000}')
        if [ "$code" = "000" ]; then
            echo "FAIL $time_ms"
        else
            echo "$code $time_ms"
        fi
    fi
}

get_iface_stats() {
    local iface="$1"
    local base="/sys/class/net/$iface/statistics"
    if [ -d "$base" ]; then
        echo "$(cat "$base/rx_errors" 2>/dev/null || echo NA) $(cat "$base/tx_errors" 2>/dev/null || echo NA) $(cat "$base/rx_dropped" 2>/dev/null || echo NA) $(cat "$base/tx_dropped" 2>/dev/null || echo NA)"
    else
        echo "NA NA NA NA"
    fi
}

# capture_incident <reason> — dumps deep diagnostics to a timestamped file
capture_incident() {
    local reason="$1"
    local now
    now=$(date +%s)
    if (( now - last_incident_time < INCIDENT_COOLDOWN )); then
        log "Incident detected ($reason) but within cooldown window — skipping extra capture."
        return
    fi
    last_incident_time=$now

    local ts file
    ts=$(date '+%Y%m%d_%H%M%S')
    file="$INCIDENT_DIR/incident_${ts}.txt"

    {
        echo "=== NETWORK INCIDENT CAPTURE ==="
        echo "Time      : $(date '+%Y-%m-%d %H:%M:%S%z')"
        echo "Reason    : $reason"
        echo
        echo "--- System load / uptime ---"
        uptime
        echo
        echo "--- Memory ---"
        free -h
        echo
        echo "--- Default route ---"
        ip route show default
        echo
        echo "--- Interface state (ip -s link) ---"
        ip -s link
        echo
        echo "--- Socket summary (ss -s) ---"
        ss -s
        echo
        echo "--- Established/outbound connections snapshot ---"
        ss -tn state established 2>/dev/null | head -50
        echo
        for target in "${PING_TARGETS[@]}"; do
            echo "--- Ping to $target ---"
            ping -n -c 5 -W 2 "$target" 2>&1
            echo
            if [ -n "$TRACE_CMD" ]; then
                echo "--- $TRACE_CMD to $target ---"
                if [ "$TRACE_CMD" = "mtr" ]; then
                    mtr -r -c 10 "$target" 2>&1
                else
                    traceroute -w 2 -q 2 "$target" 2>&1
                fi
                echo
            fi
        done
        echo "--- DNS check ($DNS_TEST_DOMAIN) ---"
        getent hosts "$DNS_TEST_DOMAIN" 2>&1 || echo "DNS RESOLUTION FAILED"
        echo
        echo "--- Recent kernel network-related messages (dmesg) ---"
        dmesg 2>/dev/null | tail -50 || echo "(dmesg not accessible — try running as root)"
        echo "=== END CAPTURE ==="
    } > "$file" 2>&1

    log "!! INCIDENT CAPTURED: $reason -> $file"
}

### ---------------------- MAIN LOOP --------------------------------------

log "netmon.sh started. Logging to $LOG_DIR (interval=${INTERVAL}s)"
trap 'log "netmon.sh stopping (signal received)"; exit 0' SIGINT SIGTERM

while true; do
    cycle_start=$(date '+%Y-%m-%d %H:%M:%S%z')
    cycle_status="OK"
    incident_reasons=()

    iface=$(get_default_iface)
    gw=$(get_default_gateway)
    [ -z "$iface" ] && iface="unknown"
    [ -z "$gw" ] && gw="unknown"

    # 1. Gateway check (local hop — first-mile issue if this fails)
    gw_loss="" ; gw_rtt=""
    if [ "$gw" != "unknown" ]; then
        read -r gw_loss gw_rtt <<< "$(ping_target "$gw")"
        if [ "$gw_loss" -ge "$LOSS_THRESHOLD" ] 2>/dev/null; then
            cycle_status="FAIL"
            incident_reasons+=("gateway ${gw} loss=${gw_loss}%")
        fi
    else
        gw_loss="NA"; gw_rtt="NA"
    fi

    # 2. External targets (bypassing DNS) — upstream/ISP issue if these fail
    ext_summary=()
    for t in "${PING_TARGETS[@]}"; do
        read -r loss rtt <<< "$(ping_target "$t")"
        ext_summary+=("${t}:${loss}%/${rtt:-NA}ms")
        if [ "$loss" -ge "$LOSS_THRESHOLD" ] 2>/dev/null; then
            cycle_status="FAIL"
            incident_reasons+=("external ${t} loss=${loss}%")
        fi
    done
    ext_summary_str=$(IFS='|'; echo "${ext_summary[*]}")

    # 3. DNS resolution
    dns_time=$(dns_resolve_time)
    dns_ok="yes"
    if [ "$dns_time" = "FAIL" ]; then
        dns_ok="no"
        cycle_status="FAIL"
        incident_reasons+=("dns resolution of ${DNS_TEST_DOMAIN} failed")
    fi

    # 4. HTTP outbound checks
    http_summary=()
    for url in "${HTTP_TARGETS[@]}"; do
        read -r code ms <<< "$(http_check "$url")"
        http_summary+=("${url}:${code}/${ms}ms")
        if [ "$code" = "FAIL" ]; then
            cycle_status="FAIL"
            incident_reasons+=("http check to ${url} failed/timed out")
        fi
    done
    http_summary_str=$(IFS='|'; echo "${http_summary[*]}")

    # 5. Interface error/drop counters (local NIC/driver issue indicator)
    read -r rx_err tx_err rx_drop tx_drop <<< "$(get_iface_stats "$iface")"

    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo NA)

    # Write CSV row
    echo "${cycle_start},${gw},${gw_loss},${gw_rtt:-NA},\"${ext_summary_str}\",${dns_ok},${dns_time},\"${http_summary_str}\",${iface},${rx_err},${tx_err},${rx_drop},${tx_drop},${load1},${cycle_status}" >> "$CSV_FILE"

    if [ "$cycle_status" = "FAIL" ]; then
        reason_str=$(IFS='; '; echo "${incident_reasons[*]}")
        log "FAIL detected: $reason_str"
        capture_incident "$reason_str"
    else
        log "OK — gw=${gw_loss}%/${gw_rtt:-NA}ms dns=${dns_time}ms http=${http_summary_str}"
    fi

    sleep "$INTERVAL"
done

### ---------------------- OPTIONAL: systemd service -----------------------
# Save the block below as /etc/systemd/system/netmon.service, then:
#   sudo systemctl daemon-reload
#   sudo systemctl enable --now netmon
#
# [Unit]
# Description=Network connectivity/outbound monitor
# After=network-online.target
# Wants=network-online.target
#
# [Service]
# Type=simple
# ExecStart=/usr/local/bin/netmon.sh
# Restart=always
# RestartSec=5
# User=root
#
# [Install]
# WantedBy=multi-user.target
