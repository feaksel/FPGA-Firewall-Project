# DECISIONS

## D-001
- Date: bootstrap
- Decision: Build core firewall around an internal frame interface instead of directly around Ethernet controller signals.
- Reason: Allows simulation, parser, rule engine, and buffering to be developed before hardware arrives.
- Alternatives considered: Direct controller-specific integration from day one.
- Impact: Lower integration risk and easier testing.

## D-002
- Date: bootstrap
- Decision: Initial inspection supports Ethernet II + IPv4 + TCP/UDP only.
- Reason: Keeps parser small and testable for the 5-week schedule.
- Alternatives considered: ARP, ICMP, or broader protocol coverage.
- Impact: Simpler MVP. Unsupported packets are dropped by default.

## D-003
- Date: bootstrap
- Decision: Rule table starts static and parameterized rather than dynamically programmed.
- Reason: Avoids control-plane complexity early.
- Alternatives considered: UART or software-driven live rule editing in the MVP.
- Impact: Faster path to a demoable firewall core.

## D-004
- Date: 2026-04-08
- Decision: Keep the internal stream interface handshake-oriented with `frame_ready` even when the first firewall core is always-ready.
- Reason: Preserves a stable boundary for the future RX adapter and packet buffer without forcing a later interface change.
- Alternatives considered: Omitting backpressure in the first pass.
- Impact: Slightly more wiring now, lower integration churn later.

## D-005
- Date: 2026-04-08
- Decision: Expand the starter rule engine to four ordered rules with first-match priority.
- Reason: Lets simulation cover exact match, subnet match, range match, and default-drop behavior early.
- Alternatives considered: Keeping the original single-rule smoke-test engine.
- Impact: Better test coverage before hardware arrives while staying simple enough for BRAM-backed expansion later.
