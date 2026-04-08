# Working Rules

## Goal
Keep the project buildable, testable, and hardware-ready with minimal rework.

## Required behavior
Before changing code:
1. Read `docs/interfaces.md`
2. Read `docs/test_plan.md`
3. Read `DECISIONS.md`
4. Read open items in `BUGS.md` and `TODO.md`

After changing code:
1. Update `CHANGELOG.md`
2. Update `DECISIONS.md` if the design choice changed
3. Update `BUGS.md` if a bug was found or fixed
4. Update `TODO.md` task status
5. Add or update relevant testbench notes

## Coding constraints
- Use plain Verilog-2001 compatible style
- Avoid SystemVerilog-only syntax
- Keep module boundaries clean
- No hidden magic constants without comments
- Keep interfaces stable
- Prefer simple FSMs and explicit registers
- Keep all top-level integration Vivado-friendly

## Milestone discipline
Do not move to the next milestone unless current test criteria pass.

Milestones:
1. packet source simulation
2. parser
3. rule engine
4. firewall core integration
5. SPI master
6. controller adapter
7. one-port hardware bring-up
8. second-port forwarding

## Bug logging format
Use:

- ID:
- Title:
- Date:
- Found by:
- Affected files:
- Symptom:
- Root cause:
- Fix:
- Status:
- Verification:

## Decision logging format
Use:

- ID:
- Date:
- Decision:
- Reason:
- Alternatives considered:
- Impact:
