# Repository Guidelines

## Project Structure

`events/nomad.lua` is the persistent Naev event adapter. Keep gameplay-neutral
state transitions in `scripts/nomad/runtime.lua`, fleet eligibility rules in
`scripts/nomad/fleet_policy.lua`, and placeholder hull choices in
`scripts/nomad/config.lua`. Standalone Lua tests live under `tests/`. Plugin
identity and dependency metadata are in `plugin.toml` and `plugin.xml`.

## Development Commands

- `make check` runs every required local validation.
- `make syntax` parses all Lua files with `luac`.
- `make manifest` parses `plugin.toml` and `start.toml`.
- `make test` runs standalone tests under Lua and LuaJIT when available.

## Style and Architecture

Use three-space indentation in modules and `snake_case` names. Keep the event
adapter thin and isolate Naev globals from pure policy code. Persist plain data
only—never pilots, hooks, ship objects, or other runtime handles. Nomad is
pre-testing: keep the state version at 0 and discard prototype saves when
structures change.

Never shadow the translation function `_`; prefix intentionally unused
variables with `_` instead. Do not use `_G` in production code. Do not add
hooks that run every frame, including `hook.update`. Never assume leftover
state can recover itself: explicitly
validate, clear, or reject every stale state. Do not infer lifecycle ordering
or object validity across hooks, transitions, landing, takeoff, swapping,
loading, or universe diffs; verify the relevant Naev implementation and make
each transition explicit.

Nomad directly depends on `TXCrewmates`; Joyride is transitive. Use Joyride's
public API and custom lifecycle events rather than copying its ship-swap logic.
Use the client ID `nomad` so Crewmates can distinguish Nomad launches.

## Testing and Changes

Tests are proof of failure only, never proof of success. A failing test can
demonstrate a defect, but passing mocks and standalone Lua tests cannot prove
that behaviour works in the Naev engine. Do not report automated checks as
evidence that player-visible engine integration is working; require an in-game
reproduction for that conclusion.

Add deterministic tests for every capacity rule. Before enabling
destructive enforcement, manually test new and existing saves, buying and
selling ships, launch/return, death, landing restrictions, and a commander
replacement through Crewmates. Commits should be focused and imperative. Pull
requests must describe save effects, list automated and in-game checks, and
include reproduction steps for player-visible behavior.
