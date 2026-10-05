#!/bin/bash
# Runs bin/container-firewall.sh on the Mac with stub getent and restore commands and checks the
# tables it would load (README.md, Residual risks: Container → Mac services).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/firewall-test.XXXXXX")"
mkdir -p "$T/bin"
# getent stub: FAKE_GETENT_V4 / FAKE_GETENT_V6 hold addresses; none means "not found" (exit 2).
cat > "$T/bin/getent" <<'EOF'
#!/bin/sh
case "$1" in ahostsv4) list="${FAKE_GETENT_V4:-}" ;; ahostsv6) list="${FAKE_GETENT_V6:-}" ;; esac
[ -n "$list" ] || exit 2
for a in $list; do echo "$a      STREAM $2"; done
EOF
# Restore stubs save the table they get; FAKE_RESTORE_FAIL=v4|v6 makes one fail.
cat > "$T/bin/iptables-restore" <<'EOF'
#!/bin/sh
cat > "$FAKE_OUT/v4"; [ "${FAKE_RESTORE_FAIL:-}" != v4 ]
EOF
cat > "$T/bin/ip6tables-restore" <<'EOF'
#!/bin/sh
cat > "$FAKE_OUT/v6"; [ "${FAKE_RESTORE_FAIL:-}" != v6 ]
EOF
chmod +x "$T/bin/"*
export FAKE_OUT="$T"
# OrbStack's container DNS; an IPv6 nameserver must be ignored by the IPv4 table.
printf 'search local\nnameserver 0.250.250.200\nnameserver fd07:b51a::1\n' > "$T/resolv.conf"
export RESOLV_CONF="$T/resolv.conf"
fw() { : > "$T/v4"; : > "$T/v6"; OUT="$(PATH="$T/bin:/usr/bin:/bin" /bin/sh "$ROOT/bin/container-firewall.sh" 2>&1)"; CODE=$?; }

export FAKE_GETENT_V4="0.250.250.254" FAKE_GETENT_V6="" FAKE_RESTORE_FAIL=""
fw
assert_eq "OrbStack: exit 0" 0 "$CODE"
assert_eq "OrbStack: IPv4 table" "*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -j ACCEPT
-A OUTPUT -d 0.250.250.200 -p udp --dport 53 -j ACCEPT
-A OUTPUT -d 0.250.250.200 -p tcp --dport 53 -j ACCEPT
-A OUTPUT -d 0.250.250.254 -j REJECT
-A OUTPUT -d 0.0.0.0/8 -j REJECT
-A OUTPUT -d 10.0.0.0/8 -j REJECT
-A OUTPUT -d 172.16.0.0/12 -j REJECT
-A OUTPUT -d 192.168.0.0/16 -j REJECT
-A OUTPUT -d 100.64.0.0/10 -j REJECT
-A OUTPUT -d 169.254.0.0/16 -j REJECT
-A OUTPUT -d 198.18.0.0/15 -j REJECT
-A OUTPUT -d 224.0.0.0/4 -j REJECT
COMMIT" "$(cat "$T/v4")"
assert_eq "OrbStack: IPv6 table" "*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -j ACCEPT
-A OUTPUT -p ipv6-icmp -j ACCEPT
-A OUTPUT -d fc00::/7 -j REJECT
-A OUTPUT -d fe80::/10 -j REJECT
-A OUTPUT -d ff00::/8 -j REJECT
COMMIT" "$(cat "$T/v6")"

export FAKE_GETENT_V4="" FAKE_GETENT_V6=""
fw
assert_eq "names do not resolve: exit 0" 0 "$CODE"
assert_contains "names do not resolve: Mac still rejected" "-A OUTPUT -d 0.250.250.254 -j REJECT" "$(cat "$T/v4")"
assert_contains "names do not resolve: LAN still rejected" "-A OUTPUT -d 192.168.0.0/16 -j REJECT" "$(cat "$T/v4")"

export FAKE_GETENT_V4="0.250.250.253" FAKE_GETENT_V6="fd07:b51a::254"
fw
assert_contains "other host address rejected" "-A OUTPUT -d 0.250.250.253 -j REJECT" "$(cat "$T/v4")"
assert_contains "OrbStack address kept as well" "-A OUTPUT -d 0.250.250.254 -j REJECT" "$(cat "$T/v4")"
assert_contains "IPv6 host address rejected" "-A OUTPUT -d fd07:b51a::254 -j REJECT" "$(cat "$T/v6")"
assert_eq "each address once" 1 "$(grep -c '0.250.250.254' "$T/v4")"

export RESOLV_CONF="$T/missing.conf" FAKE_GETENT_V4="0.250.250.254" FAKE_GETENT_V6=""
fw
assert_eq "no resolv.conf: exit 0" 0 "$CODE"
assert_not_contains "no resolv.conf: no DNS exception" "--dport 53" "$(cat "$T/v4")"
assert_contains "no resolv.conf: OrbStack range still rejected" "-A OUTPUT -d 0.0.0.0/8 -j REJECT" "$(cat "$T/v4")"
export RESOLV_CONF="$T/resolv.conf"

export FAKE_GETENT_V4="0.250.250.254" FAKE_GETENT_V6="" FAKE_RESTORE_FAIL=v4
fw
assert_eq "IPv4 restore fails: script fails" 1 "$([ "$CODE" -ne 0 ] && echo 1)"
export FAKE_RESTORE_FAIL=v6
fw
assert_eq "IPv6 restore fails: script fails" 1 "$([ "$CODE" -ne 0 ] && echo 1)"

finish
