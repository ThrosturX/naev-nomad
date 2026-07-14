# Maintainer Handoff

- `nomad_active` is the complete campaign boundary. Keep the persistent event
  conditional so non-Nomad pilots receive no hooks, state, capacity override,
  or restrictions.
- The owned mothership is identified only by its `nomad_carrier` ship variable.
  Carrier replacement is out of scope.
- General bays are derived from controls installed in the configured stock
  hull's compatible fighter-bay slots. The command bay is a logical info
  action, never a physical outfit or copied hull slot. The commander's virtual
  shuttle must not be included in `player.ships()` audits.
- Carrier hull changes belong in `config.carrier.hull`. Do not copy a stock
  hull definition to add Nomad capabilities; starter controls that do not fit
  must remain in inventory.
- Assignment state is kept in `naev.cache().nomad_bay_assignments`, keyed by
  physical outfit slot ID. Because Naev has no Lua pre-removal veto, an
  assigned control's `onremove` callback schedules restoration to the same
  slot and balances the inventory copy.
- `fleet_policy.lua` computes assignments on demand. Do not persist them.
- `TXCrewmates` is direct and Joyride is transitive. Use client `nomad` and
  their public APIs/custom lifecycle events; never access Crewmates memory or
  reproduce Joyride's temporary ship handling.
- Vanilla fleet capacity is deliberately generous. Nomad bay matching is the
  authoritative limit.
- `nomad_nojump` marks only restrictions applied by Nomad. Clear `setNoJump`
  only when that marker is present.
- State stays at version 0. There is no prototype migration contract. Parking
  persists only the system, position, direction, and temporary diff name needed
  to regenerate its dynamic spob; deployment, damage, and bay assignments
  remain derived.
- Dynamic diff names must be unique per parking cycle. Naev retains removed
  dynamic definitions until reload and reports duplicate `newDynamic` calls by
  returning `false`, not by raising an error. Never recreate the relocation
  diff from a landed load: the static storage system must resolve the saved
  spob first. After takeoff, synchronously remove the relocation; teleport only
  when leaving the storage system, then restore the recorded transform.
- Start the persistent Nomad handler during scenario initialization so its
  required commander exists before the first save. New-player creation does
  not trigger load events, so start the current pilot's Crewmates event first;
  otherwise the runtime cache can expose a previous pilot's stale provider.
  Crewmates requirements must still be re-registered on every load; that
  operation should find the already persisted commander rather than create one.
- Before destructive enforcement changes, manually test existing/new saves,
  buy/sell/trade/capture, launch/return, death, landing, and commander
  replacement through Crewmates.
