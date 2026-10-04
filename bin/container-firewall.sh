# Runs inside the firewall helper container (bin/sandbox firewall_container), never on the Mac.
# Replaces the filter tables of the work container's network namespace: replies pass; the Mac
# (OrbStack host 0.250.250.254 and whatever host.docker.internal / host.orb.internal resolve to)
# and private, link-local and multicast ranges are rejected; everything else (the internet, DNS at
# 0.250.250.200) is allowed. Why: README.md, Residual risks.
set -eu
NAMES="host.docker.internal host.orb.internal"

# resolve <ahostsv4|ahostsv6> [always-included address]: unique addresses of NAMES, one per line.
resolve() {
  { for n in $NAMES; do getent "$1" "$n" || true; done | cut -d " " -f 1
    if [ -n "${2:-}" ]; then echo "$2"; fi
  } | sort -u
}

# table <extra accept rule or ""> <target>...: a full filter table, so loading it replaces the
# old one and a rerun never stacks rules.
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
table "" $mac4 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16 224.0.0.0/4 |
  iptables-restore
# ICMPv6 stays open: neighbour discovery needs it, and the ff00::/8 reject would block it.
table "-A OUTPUT -p ipv6-icmp -j ACCEPT" $mac6 fc00::/7 fe80::/10 ff00::/8 | ip6tables-restore
