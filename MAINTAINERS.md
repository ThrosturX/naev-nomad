# Maintainer Handoff

- `nomad_active` is the campaign boundary; other pilots must receive no hooks or restrictions.
- The mothership is identified by the `nomad_carrier` ship variable.
- Fleet capacity comes from installed physical bay controls; assignments are derived, not persisted.
- Joyride is the direct dependency. `TXCrewmates` is optional; probe its public
  API once during event startup and use client ID `nomad` when it is ready.
- Optional content starts must use quiet engine capability checks such as
  `ship.exists`; do not make their source plugin a hard dependency.
- Persist plain state only. Runtime pilots and hooks are reconstructed after transitions.
- State remains version 0 and prototype saves are not migrated.
- Parking diffs must have unique names and must never be removed from a land hook.
- Run the full manual lifecycle check before enabling destructive enforcement.
