# Maintainer Handoff

- `nomad_active` is the complete campaign boundary. Keep the persistent event
  conditional so non-Nomad pilots receive no hooks, state, capacity override,
  or restrictions.
- The owned mothership is identified only by its `nomad_carrier` ship variable.
  Carrier replacement is out of scope.
- General bays are configured as XL + L + 2S. The commander's virtual shuttle
  uses the separate S command bay and must not be included in `player.ships()`
  audits.
- `fleet_policy.lua` computes assignments on demand. Do not persist them.
- `TXCrewmates` is direct and Joyride is transitive. Use client `nomad` and
  their public APIs/custom lifecycle events; never access Crewmates memory or
  reproduce Joyride's temporary ship handling.
- Vanilla fleet capacity is deliberately generous. Nomad bay matching is the
  authoritative limit.
- `nomad_nojump` marks only restrictions applied by Nomad. Clear `setNoJump`
  only when that marker is present.
- State stays at version 0. There is no prototype migration contract and no
  persisted location, deployment, damage, or loss model.
- Before destructive enforcement changes, manually test existing/new saves,
  buy/sell/trade/capture, launch/return, death, landing, and commander
  replacement through Crewmates.
