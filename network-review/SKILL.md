---
name: network-review
description: Use when reviewing a network design or its config — addressing, routing, OSPF/BGP, firewall rules, NAT, MTU (e.g. "review my topology", "check these nftables rules", "why is this route asymmetric?", "does this firewall match the flows?"). Reports what will not route, what is open that should not be, and what has no second path.
---

# Network Review

Review a topology file, routing config (FRR, bird, static routes), firewall rules (nftables, iptables), and the sysctls behind them. Report problems. Do not rewrite unless asked.

## 1. Addressing

- Two subnets that overlap, or a host address inside another link's range.
- Point-to-point links using a whole /24. Use /30, or /31 where the kernel and daemon both allow it.
- Loopbacks that are not /32.
- A router id that is not the loopback, or not unique, or that changes on reboot. OSPF and BGP both get strange when it moves.
- Addresses written in more than one place. There should be one source of truth, with everything else generated from it.

## 2. Routing

- **Asymmetric paths.** Traffic going one way and back another. It works until a stateful firewall or `rp_filter` is in the path, then it silently drops. Check `net.ipv4.conf.all.rp_filter` against the design.
- **Forwarding off.** `net.ipv4.ip_forward=1` on anything that routes, and set persistently, not just at runtime.
- **OSPF:** areas make sense; `network point-to-point` on p2p links so no needless DR election; `passive-interface` on everything that must not form a neighbour, ideally `passive-interface default` plus explicit exceptions; MTU equal on both ends or the neighbour sticks in ExStart; timers equal on both ends; authentication on, or a stated reason why not.
- **Redistribution.** What exactly is being redistributed, and can it loop back in. `default-information originate` only where a real default exists.
- **A default route** that points at a gateway which itself has no default.
- Static routes that duplicate or fight what the protocol learns.

## 3. Firewall

- **Default deny** on input and forward, with the policy at the end of the chain, not scattered.
- **State.** An `established,related` accept near the top. Without it you break every reply.
- **Management access** allowed before anything denies it, and not from the whole world.
- **ICMP.** Do not block it wholesale. Type 3 code 4 must pass or path MTU discovery breaks and large transfers hang while ping works.
- **The rules match the documented flows.** Go through the flow list one by one and find the rule. Then go the other way: find a rule that no flow asked for and ask why it is open.
- **Chain confusion.** Traffic through the box hits `forward`, not `input`. A rule in the wrong chain does nothing and looks fine.
- **NAT.** Masquerade scoped to the outbound interface and the intended sources, not `0.0.0.0/0` out of everything.
- Rules in an order where an earlier accept or drop makes a later rule dead.

## 4. MTU and MSS

- An MTU mismatch along a path, especially across a tunnel or a bridge.
- Tunnel overhead not subtracted.
- Where PMTUD cannot work, an MSS clamp on the forward chain.

## 5. Resilience

- Which single link or box, if it goes, splits the network. Say it plainly.
- What happens when the gateway dies: do the others still reach each other.
- After a link drops, does the protocol actually reconverge, and how long does it take.
- A ring or redundant design where one node only has one physical path anyway.

## 6. Verification

Prefer checks that prove it from the data plane, both directions:

```
ip -br addr ; ip route ; ip -br link
vtysh -c "show ip ospf neighbor" ; vtysh -c "show ip route ospf"
ping -c2 -M do -s 1472 <peer>      # also tests MTU
traceroute <peer>                  # and from the other side
nft list ruleset ; conntrack -L
ss -lntp
```

A review that only reads config is half a review. Say which claims you confirmed on a host and which you only read.

## How to report

Most serious first, as a list:

```
<file>:<line or rule> — <blocker | should fix | nit>: <what breaks, and under what condition>
Fix: <the change, one line>
```

For anything intermittent, say what triggers it (a link down, a large packet, a reply coming back a different way). That is the part people cannot work out for themselves.
