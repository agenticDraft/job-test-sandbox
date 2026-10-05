# Runs inside the firewall helper container (bin/sandbox firewall_container), never on the Mac.
# Replaces the filter tables of the work container's network namespace: replies and DNS pass; the
# Mac (OrbStack host 0.250.250.254 and whatever host.docker.internal / host.orb.internal resolve
# to), the rest of 0.0.0.0/8 (OrbStack's undocumented services), 198.18.0.0/15 and private,
# link-local and multicast ranges are rejected; the internet is allowed. Why: README.md, Residual
# risks. RESOLV_CONF is only set by tests.
set -eu
NAMES="host.docker.internal host.orb.internal"

# IPv4 nameservers of the container (OrbStack: 0.250.250.200) stay reachable on port 53 only.
dns_accept=""
for ns in $({ sed -n 's/^nameserver[[:space:]]*//p' "${RESOLV_CONF:-/etc/resolv.conf}" 2>/dev/null || true; }); do
  case "$ns" in *:*) continue ;; esac
  for proto in udp tcp; do
    rule="-A OUTPUT -d $ns -p $proto --dport 53 -j ACCEPT"
    if [ -z "$dns_accept" ]; then dns_accept="$rule"; else dns_accept="$dns_accept
$rule"; fi
  done
done

# resolve <ahostsv4|ahostsv6> [always-included address]: unique addresses of NAMES, one per line.
resolve() {
  { for n in $NAMES; do getent "$1" "$n" || true; done | cut -d " " -f 1
    if [ -n "${2:-}" ]; then echo "$2"; fi
  } | sort -u
}

# table <extra accept rules, one per line, or ""> <target>...: a full filter table, so loading it
# replaces the old one and a rerun never stacks rules.
table() {
  extra="$1"; shift
  echo '*filter'
  echo ':INPUT ACCEPT [0:0]'
  echo ':FORWARD ACCEPT [0:0]'
  echo ':OUTPUT ACCEPT [0:0]'
  echo '-A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT'
  if [ -n "$extra" ]; then echo "$extra"; fi
  for t in "$@"; do echo "-A OUTPUT -d $t -j REJECT"; done
  echo 'COMMIT'
}

mac4="$(resolve ahostsv4 0.250.250.254)"
mac6="$(resolve ahostsv6)"
# Word splitting of the address lists is intended.
table "$dns_accept" $mac4 0.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 \
  169.254.0.0/16 198.18.0.0/15 224.0.0.0/4 | iptables-restore
# ICMPv6 stays open: neighbour discovery needs it, and the ff00::/8 reject would block it.
table "-A OUTPUT -p ipv6-icmp -j ACCEPT" $mac6 fc00::/7 fe80::/10 ff00::/8 | ip6tables-restore
