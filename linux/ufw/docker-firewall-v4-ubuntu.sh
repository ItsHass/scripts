
#!/bin/bash

# ============================================================
# DOCKER FIREWALL MANAGER v4
#
# Docker DOCKER-USER firewall management
# IPv4 / iptables
#
# Features:
# - IP / CIDR allow and deny
# - Port allow and deny
# - Default ACCEPT / DROP
# - Correct rule priority
# - Docker published-port awareness
# - Automatic configuration persistence
# - Systemd boot integration
# - Firewall backups
# - Rule counters and management
#
# Configuration:
# /etc/docker-firewall-manager.conf
#
# Managed chain:
# DOCKER-MANAGER
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

VERSION="4.0"

# Docker bridge interfaces:
# docker0 = default bridge
# br+     = user-defined Docker bridges

BRIDGES=("docker0" "br+")

# ------------------------------------------------------------
# ROOT CHECK
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "[!] Please run using sudo."
    exit 1
fi

# ------------------------------------------------------------
# DEPENDENCIES
# ------------------------------------------------------------

for CMD in iptables python3 systemctl; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "[!] Missing dependency: $CMD"
        exit 1
    fi
done

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
# VALIDATE IP / CIDR
# ------------------------------------------------------------

normalise_ip() {

    python3 - "$1" <<'PY'
import ipaddress
import sys

try:
    network = ipaddress.ip_network(sys.argv[1], strict=False)

    if network.version != 4:
        sys.exit(1)

    if network.prefixlen == 32:
        print(network.network_address)
    else:
        print(network)

except ValueError:
    sys.exit(1)
PY

}

# ------------------------------------------------------------
# VALIDATE PORT
# ------------------------------------------------------------

valid_port() {

    [[ "$1" =~ ^[0-9]{1,5}$ ]] || return 1

    (( 10#$1 >= 1 && 10#$1 <= 65535 ))

}

# ------------------------------------------------------------
# READ IP
# ------------------------------------------------------------

read_ip() {

    local INPUT

    read -rp "IPv4 address / CIDR: " INPUT

    IP=$(normalise_ip "$INPUT") || {
        echo "[!] Invalid IPv4 address or CIDR."
        return 1
    }

}

# ------------------------------------------------------------
# READ PORT
# ------------------------------------------------------------

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

                ((DEFAULT_COUNT+=1))
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
# SAVE CONFIGURATION ATOMICALLY
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

    iptables-save > "$FILE"

    chmod 600 "$FILE"

    echo "[+] Firewall backup: $FILE"

}

# ------------------------------------------------------------
# INITIALISE DOCKER FIREWALL
# ------------------------------------------------------------

initialise_firewall() {

    if ! iptables -w -nL "$CHAIN" >/dev/null 2>&1; then

        echo "[!] Docker DOCKER-USER chain is unavailable."
        echo "[!] Ensure Docker is running and using the iptables backend."

        return 1
    fi

    # Create managed chain if required.
    iptables -w -N "$MANAGED" 2>/dev/null || true

    # Remove duplicate jumps to our managed chain.
    while iptables -w -C "$CHAIN" -j "$MANAGED" 2>/dev/null; do
        iptables -w -D "$CHAIN" -j "$MANAGED"
    done

    # Ensure our manager runs first.
    iptables -w -I "$CHAIN" 1 -j "$MANAGED"

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
                iptables -w -A "$MANAGED" \
                    -o "$BRIDGE" \
                    -s "$VALUE" \
                    -j DROP
                ;;

            ALLOW_IP)
                iptables -w -A "$MANAGED" \
                    -o "$BRIDGE" \
                    -s "$VALUE" \
                    -j ACCEPT
                ;;

            DENY_PORT)
                iptables -w -A "$MANAGED" \
                    -o "$BRIDGE" \
                    -p tcp \
                    -m conntrack \
                    --ctdir ORIGINAL \
                    --ctorigdstport "$VALUE" \
                    -j DROP
                ;;

            ALLOW_PORT)
                iptables -w -A "$MANAGED" \
                    -o "$BRIDGE" \
                    -p tcp \
                    -m conntrack \
                    --ctdir ORIGINAL \
                    --ctorigdstport "$VALUE" \
                    -j ACCEPT
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
    iptables -w -F "$MANAGED"

    # --------------------------------------------------------
    # 1. DENY IP RULES
    # Highest priority: deny always wins.
    # --------------------------------------------------------

    while IFS='|' read -r TYPE VALUE; do

        [[ "$TYPE" == "DENY_IP" ]] || continue

        add_bridge_rules "$TYPE" "$VALUE"

    done < "$CONFIG"

    # --------------------------------------------------------
    # 2. DENY PORT RULES
    # These also block existing connections.
    # --------------------------------------------------------

    while IFS='|' read -r TYPE VALUE; do

        [[ "$TYPE" == "DENY_PORT" ]] || continue

        add_bridge_rules "$TYPE" "$VALUE"

    done < "$CONFIG"

    # --------------------------------------------------------
    # 3. ESTABLISHED CONNECTIONS
    # Allow existing traffic to Docker containers.
    # Deny rules above still take precedence.
    # --------------------------------------------------------

    local BRIDGE

    for BRIDGE in "${BRIDGES[@]}"; do

        iptables -w -A "$MANAGED" \
            -o "$BRIDGE" \
            -m conntrack \
            --ctstate RELATED,ESTABLISHED \
            -j ACCEPT

    done

    # --------------------------------------------------------
    # 4. ALLOW IP RULES
    # --------------------------------------------------------

    while IFS='|' read -r TYPE VALUE; do

        [[ "$TYPE" == "ALLOW_IP" ]] || continue

        add_bridge_rules "$TYPE" "$VALUE"

    done < "$CONFIG"

    # --------------------------------------------------------
    # 5. ALLOW PORT RULES
    # Uses original published Docker port.
    # Example: 8080:80 matches port 8080.
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

            iptables -w -A "$MANAGED" \
                -o "$BRIDGE" \
                -m conntrack \
                --ctstate NEW \
                -j DROP

        done

    else

        echo "[*] Default policy: ACCEPT"

    fi

    # --------------------------------------------------------
    # 7. RETURN UNMATCHED TRAFFIC
    # --------------------------------------------------------

    iptables -w -A "$MANAGED" -j RETURN

    echo ""
    echo "[+] Docker firewall applied successfully."

    echo "[+] Active default action: $DEFAULT"

    echo "[+] Managed rules:"

    iptables -w -L "$MANAGED" -n -v --line-numbers

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

# ------------------------------------------------------------
# ALLOW IP
# ------------------------------------------------------------

allow_ip() {

    read_ip || return

    add_rule "ALLOW_IP" "$IP"

}

# ------------------------------------------------------------
# DENY IP
# ------------------------------------------------------------

deny_ip() {

    read_ip || return

    add_rule "DENY_IP" "$IP"

}

# ------------------------------------------------------------
# ALLOW PORT
# ------------------------------------------------------------

allow_port() {

    read_port || return

    add_rule "ALLOW_PORT" "$PORT"

}

# ------------------------------------------------------------
# DENY PORT
# ------------------------------------------------------------

deny_port() {

    read_port || return

    add_rule "DENY_PORT" "$PORT"

}

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

    awk '
    /^DEFAULT\|/ {
        print "Default action: " $2
        next
    }
    /^ALLOW_IP\|/ {
        print "[ALLOW IP]   " $2
        next
    }
    /^DENY_IP\|/ {
        print "[DENY IP]    " $2
        next
    }
    /^ALLOW_PORT\|/ {
        print "[ALLOW PORT] " $2
        next
    }
    /^DENY_PORT\|/ {
        print "[DENY PORT]  " $2
        next
    }
    ' "$CONFIG"

    echo ""
    echo "========================================"
    echo " ACTIVE MANAGED RULES"
    echo "========================================"

    iptables -w -L "$MANAGED" -n -v --line-numbers

    echo ""
    echo "========================================"
    echo " DOCKER-USER CHAIN"
    echo "========================================"

    iptables -w -L "$CHAIN" -n -v --line-numbers

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

    if [[ ! "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 )); then
        echo "[!] Invalid rule number."
        return
    fi

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

    [[ "$CONFIRM" == "YES" ]] || return

    backup_firewall

    printf 'DEFAULT|ACCEPT\n' > "$CONFIG"

    chmod 600 "$CONFIG"

    apply_rules

    echo "[+] Managed firewall reset."

}

# ------------------------------------------------------------
# SAVE
# ------------------------------------------------------------

save_firewall() {

    save_config || return

    apply_rules

}

# ------------------------------------------------------------
# RESTORE
# ------------------------------------------------------------

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
# ------------------------------------------------------------

install_persistence() {

    if [[ ! -f "$SCRIPT" ]]; then

        echo "[!] Save this script to:"
        echo "$SCRIPT"

        return

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
    echo "iptables backend:"

    iptables --version

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

    iptables -w -L "$MANAGED" -n -v --line-numbers

    echo ""
    echo "Docker user chain:"

    iptables -w -L "$CHAIN" -n -v --line-numbers

}

# ------------------------------------------------------------
# STARTUP MODE
# ------------------------------------------------------------

initialise_config

if [[ "${1:-}" == "--apply" ]]; then

    apply_rules

    exit $?

fi

# ------------------------------------------------------------
# MAIN MENU
# ------------------------------------------------------------

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
