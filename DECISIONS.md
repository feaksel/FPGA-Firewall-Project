# DECISIONS

## D-001
- Date: 2026-04-08
- Decision: Build core firewall around an internal frame interface instead of directly around Ethernet controller signals.
- Reason: Allows simulation, parser, rule engine, and buffering to be developed before hardware arrives.
- Alternatives considered: Direct controller-specific integration from day one.
- Impact: Lower integration risk and easier testing.

## D-002
- Date: 2026-04-08
- Decision: Initial inspection supports Ethernet II + IPv4 + TCP/UDP only.
- Reason: Keeps parser small and testable for the 5-week schedule.
- Alternatives considered: ARP, ICMP, or broader protocol coverage.
- Impact: Simpler MVP. Unsupported packets are dropped by default.

## D-003
- Date: 2026-04-08
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
- Decision: Expand the rule engine to four ordered rules with first-match priority.
- Reason: Lets simulation cover exact match, subnet match, range match, and default-drop behavior early.
- Alternatives considered: Keeping the original single-rule smoke-test engine.
- Impact: Better test coverage before hardware arrives while staying simple enough for BRAM-backed expansion later.

## D-006
- Date: 2026-04-08
- Decision: Use SystemVerilog for verification infrastructure while keeping synthesizable RTL conservative.
- Reason: Packages, stronger typing, and reusable helpers make the benches easier to extend without taking synthesis risk in the datapath and adapter RTL.
- Alternatives considered: Keeping the entire repo in Verilog-2001 only, or moving the synthesizable RTL fully to SystemVerilog.
- Impact: Faster verification development with low FPGA-flow risk.

## D-007
- Date: 2026-04-09
- Decision: Freeze the first hardware target around DE1-SoC plus W5500 using `SPI + RESET + INT`.
- Reason: It gives the project a concrete board/module contract before hardware arrives and keeps the adapter work focused.
- Alternatives considered: Staying controller-agnostic longer or targeting a different SPI Ethernet controller.
- Impact: The adapter, docs, and top-level wiring can now converge on a single bring-up path.

## D-008
- Date: 2026-04-09
- Decision: Use W5500 socket 0 in MACRAW mode for the MVP receive path.
- Reason: It preserves raw Ethernet frames for the parser and firewall core while avoiding transmit-side complexity early.
- Alternatives considered: Using higher-level socket modes or adding forwarding before receive inspection was stable.
- Impact: The adapter can feed the existing internal frame interface without changing parser or firewall architecture.

## D-009
- Date: 2026-04-16
- Decision: Insert a small RX FIFO between the W5500 adapter and the firewall core during pre-hardware hardening.
- Reason: It adds controlled backpressure handling without changing the parser/rule/firewall interfaces and makes the integrated receive path closer to the real hardware behavior.
- Alternatives considered: Keeping the adapter directly connected to the firewall core until hardware arrives, or repurposing the standalone packet buffer for live RX.
- Impact: The live receive path is more robust before board bring-up, while transmit/forwarding complexity remains deferred.

## D-010
- Date: 2026-05-01
- Decision: Keep the hardware W5500 bring-up image polling-based and receive/inspect-only after first live packet success.
- Reason: The board now proves W5500 SPI access, MACRAW initialization, and real packet reception; forwarding would add a second major hardware risk before allow/drop correlation is clean.
- Alternatives considered: Moving directly to a second Ethernet port or transmit path after first RX activity.
- Impact: The next milestone is better observability and repeatable allow/drop validation, not forwarding.

## D-011
- Date: 2026-05-01
- Decision: Treat malformed or oversized W5500 RX frames as discardable receive events instead of fatal adapter initialization errors.
- Reason: Real Ethernet links include background multicast/broadcast traffic and startup frames; one odd frame should not permanently stop the receive path.
- Alternatives considered: Keeping the previous fail-fast behavior for every invalid hardware RX length.
- Impact: Hardware receive remains live and can continue polling after discarding a bad frame.

## D-012
- Date: 2026-05-01
- Decision: Make the final demo a one-way inline firewall with a chunked file-transfer proof before attempting bidirectional forwarding.
- Reason: One-way PC1-to-PC2 forwarding is enough to prove real enforcement, loss/drop visibility, and a compelling final presentation while keeping the hardware state space manageable.
- Alternatives considered: Jumping directly to bidirectional Ethernet forwarding or staying with one-port inspection only.
- Impact: The next RTL work centers on W5500 B TX, a stream forwarder, UART telemetry, and file-demo scripts.

## D-013
- Date: 2026-05-01
- Decision: Use chunked file/video transfer with SHA-256 verification rather than live video streaming.
- Reason: Chunked transfer is robust over W5500-over-SPI and makes policy drops visible without corrupting required file data.
- Alternatives considered: Live streaming, iperf-only throughput, or a synthetic packet counter demo.
- Impact: The final presentation can show a real reconstructed artifact while honestly describing the firewall as packet-policy enforcement, not payload malware detection.
