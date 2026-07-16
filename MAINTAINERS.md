# Maintainer Handoff

- `nomad_active` is the campaign boundary; other pilots must receive no hooks or restrictions.
- The mothership is identified by the `nomad_carrier` ship variable.
- Fleet capacity comes from installed physical bay controls; assignments are derived, not persisted.
- `TXCrewmates` is direct and Joyride is transitive. Use client ID `nomad` and public lifecycle events.
- Persist plain state only. Runtime pilots and hooks are reconstructed after transitions.
- State remains version 0 and prototype saves are not migrated.
- Parking diffs must have unique names and must never be removed from a land hook.
- Run the full manual lifecycle check before enabling destructive enforcement.
