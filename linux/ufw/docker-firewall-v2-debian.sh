#!/bin/bash

# ============================================================
# DOCKER FIREWALL MANAGER v4.1 (Debian)
#
# Docker DOCKER-USER firewall management
# IPv4 / iptables (iptables-nft or iptables-legacy)
#
# Configuration:  /etc/docker-firewall-manager.conf
# Managed chain:  DOCKER-MANAGER
#
# Debian notes:
#   apt install iptables      (not installed by default on Debian 11+)
#   No python3 or sudo required (run as root with "su -" or sudo)
# ============================================================

set -Eeuo pipefail

# ------------------------------------------------------------
# SETTINGS
# ------------------------------------------------------------

CHAIN="DOCKER-USER"
MANAGED="DOCKER-MANAGER"

CONFIG="/etc/docker-firewall-manager.conf"
BACKUP_DIR="/var/backups/docker-firewall"
SCRIPT="/usr/local/sbin/docker-firewall-manager.sh"
SERVICE="docker-firewall-manager"

VERSION="4.1"

# docker0 = default bridge, br+ = user-defined Docker bridges
BRIDGES=("docker0" "br+")

# Debian: "su" (without "-") does not put /usr/sbin or /sbin in PATH,
# which is where iptables lives. Set it explicitly.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ------------------------------------------------------------
# ROOT CHECK
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "[!] Please run as root (use 'su -' or sudo)."
    exit 1
fi

# ------------------------------------------------------------
# DEPENDENCIES
# ------------------------------------------------------------

for CMD in iptables iptables-save systemctl; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "[!] Missing dependency: $CMD"
        [[ "$CMD" == iptables* ]] && echo "    Install it with: apt install iptables"
        exit 1
    fi
done

# ------------------------------------------------------------
# IPTABLES BACKEND DETECTION
#
# Debian 10+ defaults to iptables-nft, but Docker may be using
# iptables-legacy (or vice versa). Pick whichever backend can
# actually see Docker's DOCKER-USER chain.
# ------------------------------------------------------------

IPT="iptables"
IPT_SAVE="iptables-save"

detect_iptables() {

    local CAND

    for CAND in iptables iptables-nft iptables-legacy; do

        command -v "$CAND" >/dev/null 2>&1 || continue
        command -v "${CAND}-save" >/dev/null 2>&1 || continue

        if "$CAND" -w -nL "$CHAIN" >/dev/null 2>&1; then
            IPT="$CAND"
            IPT_SAVE="${CAND}-save"
            return 0
        fi

    done

    return 1

}

# ------------------------------------------------------------
# CONFIGURATION INITIALISATION
# ------------------------------------------------------------

initialise_config() {

    mkdir -p "$(dirname "$CONFIG")"
    mkdir -p "$BACKUP_DIR"

    if [[ ! -f "$CONFIG" ]]; then
        printf 'DEFAULT|ACCEPT\n' > "$CONFIG"
    fi

    if ! grep -q '^DEFAULT|' "$CONFIG"; then
        echo 'DEFAULT|ACCEPT' >> "$CONFIG"
    fi

    chmod 600 "$CONFIG"
}

# ------------------------------------------------------------
# VALIDATE / NORMALISE IPv4 ADDRESS OR CIDR (pure bash)
#
# 1.2.3.4      -> 1.2.3.4
# 1.2.3.4/32   -> 1.2.3.4
# 10.1.2.3/8   -> 10.0.0.0/8   (host bits cleared)
# ------------------------------------------------------------

normalise_ip() {

    local INPUT="$1"
    local ADDR="$INPUT"
    local PREFIX=32
    local O1 O2 O3 O4 IP_INT MASK NET

    if [[ "$INPUT" == */* ]]; then
        ADDR="${INPUT%%/*}"
        PREFIX="${INPUT#*/}"

        [[ "$PREFIX" =~ ^[0-9]{1,2}$ ]] || return 1
        PREFIX=$((10#$PREFIX))
        (( PREFIX <= 32 )) || return 1
    fi

    [[ "$ADDR" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1

    O1=$((10#${BASH_REMATCH[1]}))
    O2=$((10#${BASH_REMATCH[2]}))
    O3=$((10#${BASH_REMATCH[3]}))
    O4=$((10#${BASH_REMATCH[4]}))

    (( O1 <= 255 && O2 <= 255 && O3 <= 255 && O4 <= 255 )) || return 1

    IP_INT=$(( (O1 << 24) | (O2 << 16) | (O3 << 8) | O4 ))
    MASK=$(( (0xFFFFFFFF << (32 - PREFIX)) & 0xFFFFFFFF ))
    NET=$(( IP_INT & MASK ))

    printf '%d.%d.%d.%d' \
        $(( (NET >> 24) & 255 )) \
        $(( (NET >> 16) & 255 )) \
        $(( (NET >> 8) & 255 )) \
        $(( NET & 255 ))

    if (( PREFIX != 32 )); then
        printf '/%d' "$PREFIX"
    fi

    printf '\n'

}

# ------------------------------------------------------------
# VALIDATE PORT
# ------------------------------------------------------------

valid_port() {

    [[ "$1" =~ ^[0-9]{1,5}$ ]] || return 1

    (( 10#$1 >= 1 && 10#$1 <= 65535 ))

}

# ------------------------------------------------------------
# READ IP / PORT
# ------------------------------------------------------------

read_ip() {

    local INPUT

    read -rp "IPv4 address / CIDR: " INPUT

    IP=$(normalise_ip "$INPUT") || {
        echo "[!] Invalid IPv4 address or CIDR."
        return 1
    }

}

read_port() {

    read -rp "TCP port: " PORT

    if ! valid_port "$PORT"; then
        echo "[!] Invalid TCP port."
        return 1
    fi

    PORT=$((10#$PORT))

}

# ------------------------------------------------------------
# CONFIGURATION VALIDATION
# ------------------------------------------------------------

validate_config() {

    local TYPE VALUE EXTRA
    local DEFAULT_COUNT=0

    while IFS='|' read -r TYPE VALUE EXTRA || [[ -n "${TYPE:-}" ]]; do

        [[ -z "$TYPE" ]] && continue

        if [[ -n "${EXTRA:-}" || -z "${VALUE:-}" ]]; then
            echo "[!] Invalid configuration entry: $TYPE"
            return 1
        fi

        case "$TYPE" in

            DEFAULT)
                [[ "$VALUE" == "ACCEPT" || "$VALUE" == "DROP" ]] || {
                    echo "[!] Invalid default action."
                    return 1
                }

                DEFAULT_COUNT=$((DEFAULT_COUNT + 1))
                ;;

            ALLOW_IP|DENY_IP)
                normalise_ip "$VALUE" >/dev/null || {
                    echo "[!] Invalid IP in configuration: $VALUE"
                    return 1
                }
                ;;

            ALLOW_PORT|DENY_PORT)
                valid_port "$VALUE" || {
                    echo "[!] Invalid port in configuration: $VALUE"
                    return 1
                }
                ;;

            *)
                echo "[!] Unknown configuration type: $TYPE"
                return 1
                ;;

        esac

    done < "$CONFIG"

    if (( DEFAULT_COUNT != 1 )); then
        echo "[!] Configuration must contain exactly one DEFAULT entry."
        return 1
    fi

}

# ------------------------------------------------------------
# SAVE CONFIGURATION
# ------------------------------------------------------------

commit_config() {

    local TEMP="$1"

    chmod 600 "$TEMP"
    mv -f "$TEMP" "$CONFIG"

    echo "[+] Configuration saved."
}

save_config() {

    validate_config || return 1

    chmod 600 "$CONFIG"

    echo "[+] Configuration saved: $CONFIG"

}

# ------------------------------------------------------------
# BACKUP FIREWALL
# ------------------------------------------------------------

backup_firewall() {

    mkdir -p "$BACKUP_DIR"

    local FILE="$BACKUP_DIR/iptables-$(date +%Y%m%d-%H%M%S).rules"

    "$IPT_SAVE" > "$FILE"

    chmod 600 "$FILE"

    echo "[+] Firewall backup: $FILE"

}

# ------------------------------------------------------------
# INITIALISE DOCKER FIREWALL
# ------------------------------------------------------------

initialise_firewall() {

    if ! detect_iptables; then

        echo "[!] Docker DOCKER-USER chain is unavailable."
        echo "[!] Ensure Docker is running (systemctl start docker)."

        return 1
    fi

    # Create managed chain if required.
    "$IPT" -w -N "$MANAGED" 2>/dev/null || true

    # Remove duplicate jumps to our managed chain.
    while "$IPT" -w -C "$CHAIN" -j "$MANAGED" 2>/dev/null; do
        "$IPT" -w -D "$CHAIN" -j "$MANAGED"
    done

    # Ensure our manager runs first.
    "$IPT" -w -I "$CHAIN" 1 -j "$MANAGED"

}

# ------------------------------------------------------------
# ADD BRIDGE RULES
# ------------------------------------------------------------

add_bridge_rules() {

    local RULE_TYPE="$1"
    local VALUE="$2"
    local BRIDGE

    for BRIDGE in "${BRIDGES[@]}"; do

        case "$RULE_TYPE" in

            DENY_IP)
                "$IPT" -w -A "$MANAGED" -o "$BRIDGE" -s "$VALUE" -j DROP
                ;;

            ALLOW_IP)
                "$IPT" -w -A "$MANAGED" -o "$BRIDGE" -s "$VALUE" -j ACCEPT
                ;;

            DENY_PORT)
                "$IPT" -w -A "$MANAGED" -o "$BRIDGE" -p tcp \
                    -m conntrack --ctdir ORIGINAL \
                    --ctorigdstport "$VALUE" -j DROP
                ;;

            ALLOW_PORT)
                "$IPT" -w -A "$MANAGED" -o "$BRIDGE" -p tcp \
                    -m conntrack --ctdir ORIGINAL \
                    --ctorigdstport "$VALUE" -j ACCEPT
                ;;

        esac

    done

}

# ------------------------------------------------------------
# APPLY FIREWALL CONFIGURATION
# ------------------------------------------------------------

apply_rules() {

    echo ""
    echo "[*] Applying Docker firewall configuration..."

    validate_config || return 1

    initialise_firewall || return 1

    # Only flush our own managed chain.
    "$IPT" -w -F "$MANAGED"

    local BRIDGE
    local TYPE VALUE

    # --------------------------------------------------------
    # 0. CONTAINER-TO-CONTAINER TRAFFIC
    # Traffic entering and leaving Docker bridges is not
    # "inbound from outside", so leave it to Docker's own rules.
    # Without this, a DROP default would break inter-container
    # networking (e.g. docker compose stacks).
    # --------------------------------------------------------

    for BRIDGE in "${BRIDGES[@]}"; do

        "$IPT" -w -A "$MANAGED" -i "$BRIDGE" -o "$BRIDGE" -j RETURN

    done

    # --------------------------------------------------------
    # 1. DENY IP RULES (deny always wins)
    # --------------------------------------------------------

    while IFS='|' read -r TYPE VALUE; do
        [[ "$TYPE" == "DENY_IP" ]] || continue
        add_bridge_rules "$TYPE" "$VALUE"
    done < "$CONFIG"

    # --------------------------------------------------------
    # 2. DENY PORT RULES
    # --------------------------------------------------------

    while IFS='|' read -r TYPE VALUE; do
        [[ "$TYPE" == "DENY_PORT" ]] || continue
        add_bridge_rules "$TYPE" "$VALUE"
    done < "$CONFIG"

    # --------------------------------------------------------
    # 3. ESTABLISHED CONNECTIONS
    # --------------------------------------------------------

    for BRIDGE in "${BRIDGES[@]}"; do

        "$IPT" -w -A "$MANAGED" -o "$BRIDGE" \
            -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    done

    # --------------------------------------------------------
    # 4. ALLOW IP RULES
    # --------------------------------------------------------

    while IFS='|' read -r TYPE VALUE; do
        [[ "$TYPE" == "ALLOW_IP" ]] || continue
        add_bridge_rules "$TYPE" "$VALUE"
    done < "$CONFIG"

    # --------------------------------------------------------
    # 5. ALLOW PORT RULES (original published port)
    # --------------------------------------------------------

    while IFS='|' read -r TYPE VALUE; do
        [[ "$TYPE" == "ALLOW_PORT" ]] || continue
        add_bridge_rules "$TYPE" "$VALUE"
    done < "$CONFIG"

    # --------------------------------------------------------
    # 6. DEFAULT ACTION
    # --------------------------------------------------------

    local DEFAULT

    DEFAULT=$(awk -F'|' '$1=="DEFAULT" {print $2}' "$CONFIG")

    if [[ "$DEFAULT" == "DROP" ]]; then

        echo "[*] Default policy: DROP"

        for BRIDGE in "${BRIDGES[@]}"; do

            "$IPT" -w -A "$MANAGED" -o "$BRIDGE" \
                -m conntrack --ctstate NEW -j DROP

        done

    else

        echo "[*] Default policy: ACCEPT"

    fi

    # --------------------------------------------------------
    # 7. RETURN UNMATCHED TRAFFIC
    # --------------------------------------------------------

    "$IPT" -w -A "$MANAGED" -j RETURN

    echo ""
    echo "[+] Docker firewall applied successfully (backend: $IPT)."
    echo "[+] Active default action: $DEFAULT"
    echo "[+] Managed rules:"

    "$IPT" -w -L "$MANAGED" -n -v --line-numbers

}

# ------------------------------------------------------------
# ADD RULE
# ------------------------------------------------------------

add_rule() {

    local TYPE="$1"
    local VALUE="$2"
    local ENTRY="${TYPE}|${VALUE}"

    if grep -Fxq -- "$ENTRY" "$CONFIG"; then
        echo "[!] This rule already exists."
        return 1
    fi

    local TEMP
    TEMP=$(mktemp "${CONFIG}.XXXXXX")

    cp "$CONFIG" "$TEMP"
    printf '%s\n' "$ENTRY" >> "$TEMP"

    commit_config "$TEMP"

    apply_rules

}

allow_ip()   { read_ip   || return 0; add_rule "ALLOW_IP"   "$IP";   }
deny_ip()    { read_ip   || return 0; add_rule "DENY_IP"    "$IP";   }
allow_port() { read_port || return 0; add_rule "ALLOW_PORT" "$PORT"; }
deny_port()  { read_port || return 0; add_rule "DENY_PORT"  "$PORT"; }

# ------------------------------------------------------------
# DEFAULT ACTION
# ------------------------------------------------------------

set_default_action() {

    echo ""
    echo "1) ACCEPT - Allow unmatched Docker traffic"
    echo "2) DROP   - Block new inbound Docker traffic"

    read -rp "Select action: " ACTION

    case "$ACTION" in
        1) ACTION="ACCEPT" ;;
        2) ACTION="DROP" ;;
        *)
            echo "[!] Invalid selection."
            return
            ;;
    esac

    local TEMP
    TEMP=$(mktemp "${CONFIG}.XXXXXX")

    awk -F'|' '$1 != "DEFAULT" {print}' "$CONFIG" > "$TEMP"
    printf 'DEFAULT|%s\n' "$ACTION" >> "$TEMP"

    commit_config "$TEMP"

    apply_rules

}

# ------------------------------------------------------------
# LIST CONFIGURATION
# ------------------------------------------------------------

list_rules() {

    echo ""
    echo "========================================"
    echo " SAVED CONFIGURATION"
    echo "========================================"

    awk -F'|' '
    /^DEFAULT\|/    { print "Default action: " $2; next }
    /^ALLOW_IP\|/   { print "[ALLOW IP]   " $2; next }
    /^DENY_IP\|/    { print "[DENY IP]    " $2; next }
    /^ALLOW_PORT\|/ { print "[ALLOW PORT] " $2; next }
    /^DENY_PORT\|/  { print "[DENY PORT]  " $2; next }
    ' "$CONFIG"

    echo ""
    echo "========================================"
    echo " ACTIVE MANAGED RULES"
    echo "========================================"

    "$IPT" -w -L "$MANAGED" -n -v --line-numbers || true

    echo ""
    echo "========================================"
    echo " DOCKER-USER CHAIN"
    echo "========================================"

    "$IPT" -w -L "$CHAIN" -n -v --line-numbers || true

}

# ------------------------------------------------------------
# REMOVE RULE
# ------------------------------------------------------------

remove_rule() {

    echo ""
    echo "========== CONFIGURED RULES =========="

    grep -E '^(ALLOW_IP|DENY_IP|ALLOW_PORT|DENY_PORT)\|' "$CONFIG" |
        nl -ba || true

    echo ""

    read -rp "Rule number to remove: " NUM

    if [[ ! "$NUM" =~ ^[0-9]+$ ]] || (( 10#$NUM < 1 )); then
        echo "[!] Invalid rule number."
        return
    fi

    NUM=$((10#$NUM))

    local TEMP
    TEMP=$(mktemp "${CONFIG}.XXXXXX")

    awk -F'|' -v target="$NUM" '
    $1 ~ /^(ALLOW_IP|DENY_IP|ALLOW_PORT|DENY_PORT)$/ {
        count++
        if (count == target) next
    }
    {print}
    ' "$CONFIG" > "$TEMP"

    if cmp -s "$CONFIG" "$TEMP"; then
        rm -f "$TEMP"
        echo "[!] Rule not found."
        return
    fi

    commit_config "$TEMP"

    apply_rules

}

# ------------------------------------------------------------
# RESET MANAGED RULES
# ------------------------------------------------------------

reset_firewall() {

    echo ""
    echo "[!] This removes all configured IP and port rules."
    echo "[!] Default action will become ACCEPT."

    read -rp "Type YES to confirm: " CONFIRM

    [[ "$CONFIRM" == "YES" ]] || return 0

    backup_firewall

    printf 'DEFAULT|ACCEPT\n' > "$CONFIG"
    chmod 600 "$CONFIG"

    apply_rules

    echo "[+] Managed firewall reset."

}

save_firewall() {

    save_config || return 0

    apply_rules

}

restore_firewall() {

    if [[ ! -f "$CONFIG" ]]; then
        echo "[!] Configuration file not found."
        return
    fi

    echo "[*] Loading saved configuration..."

    apply_rules

}

# ------------------------------------------------------------
# SYSTEMD PERSISTENCE
# Copies this script to $SCRIPT automatically if needed.
# ------------------------------------------------------------

install_persistence() {

    local SELF
    SELF=$(readlink -f "${BASH_SOURCE[0]}")

    if [[ "$SELF" != "$SCRIPT" ]]; then

        if [[ ! -f "$SELF" ]]; then
            echo "[!] Cannot locate this script file. Save it to:"
            echo "    $SCRIPT"
            return 1
        fi

        echo "[*] Installing script to $SCRIPT"
        install -D -m 755 "$SELF" "$SCRIPT"

    fi

    echo "[*] Installing systemd service..."

    cat > "/etc/systemd/system/${SERVICE}.service" <<EOF
[Unit]
Description=Docker Firewall Manager
Requires=docker.service
After=docker.service
PartOf=docker.service

[Service]
Type=oneshot
ExecStart=${SCRIPT} --apply
ExecReload=${SCRIPT} --apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE"

    echo "[+] Systemd persistence installed."
    echo "[+] Service: ${SERVICE}.service"

}

# ------------------------------------------------------------
# FIREWALL STATUS
# ------------------------------------------------------------

firewall_status() {

    echo ""
    echo "========================================"
    echo " DOCKER FIREWALL STATUS"
    echo "========================================"

    echo ""
    echo "Version: $VERSION"

    echo ""
    echo "Docker service:"
    systemctl is-active docker || true

    echo ""
    echo "iptables backend in use:"
    "$IPT" --version

    echo ""
    echo "Configuration:"
    echo "$CONFIG"

    echo ""
    echo "Default action:"
    awk -F'|' '$1=="DEFAULT" {print $2}' "$CONFIG"

    echo ""
    echo "Systemd persistence:"
    systemctl is-enabled "$SERVICE" 2>/dev/null || echo "Not installed"

    echo ""
    echo "Managed chain:"
    "$IPT" -w -L "$MANAGED" -n -v --line-numbers || true

    echo ""
    echo "Docker user chain:"
    "$IPT" -w -L "$CHAIN" -n -v --line-numbers || true

}

# ------------------------------------------------------------
# STARTUP MODE
# ------------------------------------------------------------

initialise_config
detect_iptables || true

if [[ "${1:-}" == "--apply" ]]; then

    apply_rules
    exit $?

fi

# ------------------------------------------------------------
# MAIN MENU
# Strict error exit is disabled here so a failed action returns
# to the menu instead of killing the script.
# ------------------------------------------------------------

set +e

while true; do

    clear

    echo "================================================"
    echo "          DOCKER FIREWALL MANAGER v${VERSION}"
    echo "================================================"
    echo ""
    echo " 1) Allow IP / CIDR"
    echo " 2) Deny IP / CIDR"
    echo ""
    echo " 3) Allow TCP port"
    echo " 4) Deny TCP port"
    echo ""
    echo " 5) Set default action"
    echo ""
    echo " 6) List firewall rules"
    echo " 7) Remove managed rule"
    echo " 8) Reset managed firewall"
    echo ""
    echo " 9) Firewall status"
    echo "10) Save configuration"
    echo "11) Restore configuration"
    echo "12) Backup current firewall"
    echo ""
    echo "13) Install boot persistence"
    echo "14) Exit"
    echo ""
    echo "================================================"

    read -rp "Select option: " OPT

    case "$OPT" in

        1) allow_ip ;;
        2) deny_ip ;;
        3) allow_port ;;
        4) deny_port ;;
        5) set_default_action ;;
        6) list_rules ;;
        7) remove_rule ;;
        8) reset_firewall ;;
        9) firewall_status ;;
        10) save_firewall ;;
        11) restore_firewall ;;
        12) backup_firewall ;;
        13) install_persistence ;;
        14) exit 0 ;;

        *)
            echo "[!] Invalid option."
            ;;

    esac

    echo ""
    read -rp "Press ENTER to continue..."

done
