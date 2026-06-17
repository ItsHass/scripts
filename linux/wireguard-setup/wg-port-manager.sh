#!/bin/bash

WGCONF="/etc/wireguard/wg0.conf"
TEMPLATE_PORT="28967"

backup() {
    cp "$WGCONF" "$WGCONF.bak.$(date +%Y%m%d_%H%M%S)"
}

get_template_ip() {
    grep "DNAT" "$WGCONF" \
    | grep "dport $TEMPLATE_PORT" \
    | head -1 \
    | sed -E 's/.*--to-destination ([0-9.]+):.*/\1/'
}

list_rules() {

echo
echo "PORT     DESTINATION"
echo

grep "DNAT" "$WGCONF" |
while read -r line
do
    port=$(echo "$line" | sed -nE 's/.*--dport ([0-9]+).*/\1/p')
    ip=$(echo "$line" | sed -nE 's/.*--to-destination ([0-9.]+):.*/\1/p')

    [[ -n "$port" && -n "$ip" ]] && \
        echo "$port -> $ip"
done | sort -u

echo
}

add_rule() {

PORT="$1"
IP="$2"

if grep -q -- "--dport $PORT" "$WGCONF"
then
    echo "Port already exists"
    exit 1
fi

TEMPLATE_IP=$(get_template_ip)

if [[ -z "$TEMPLATE_IP" ]]
then
    echo "Could not locate template port $TEMPLATE_PORT"
    exit 1
fi

backup

awk \
-v oldport="$TEMPLATE_PORT" \
-v newport="$PORT" \
-v oldip="$TEMPLATE_IP" \
-v newip="$IP" '
{
    print

    if ($0 ~ "--dport " oldport) {
        line=$0

        gsub(oldport,newport,line)
        gsub(oldip,newip,line)

        print line
    }
}
' "$WGCONF" > /tmp/wg.conf

mv /tmp/wg.conf "$WGCONF"

echo
echo "Added:"
echo "$PORT -> $IP"
echo
}

remove_rule() {

PORT="$1"

backup

grep -v -- "--dport $PORT" "$WGCONF" \
| grep -v ":$PORT" \
> /tmp/wg.conf

mv /tmp/wg.conf "$WGCONF"

echo "Removed $PORT"
}

case "$1" in

list)
list_rules
;;

add)
add_rule "$2" "$3"
;;

remove)
remove_rule "$2"
;;

*)
echo "Usage:"
echo "./wg-port-mgr.sh list"
echo "./wg-port-mgr.sh add PORT DEST_IP"
echo "./wg-port-mgr.sh remove PORT"
;;

esac
