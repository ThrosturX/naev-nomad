# Nomad Fleet

Nomad is a carrier campaign for Naev. New Nomad pilots begin in the stock
carrier hull selected by `config.carrier.hull`, permanently tagged as their
mothership. Pilots created by other scenarios are unaffected.

The command bay is a logical carrier capability exposed by the
`Launch Shuttle` info action, so it consumes no outfit slot and
requires no hull variant. M and S controls are installed into compatible
fighter-bay slots when available; controls that do not fit are kept in
inventory. New pilots also receive two spare controls of every general size.
S accepts hull sizes 1–2, M accepts 1–4, L accepts 1–5, and XL accepts 1–6.
Ordinary owned ships are audited largest-first against the currently installed
controls and placed in the smallest compatible bay. A control assigned to a
ship cannot be unfitted until that assignment is cleared. The Crewmates
commander's virtual shuttle never appears in or consumes the ordinary fleet.

Nomad registers one Crewmates commander with an Alpaca shuttle and the
`nomad` Joyride profile. The shuttle can land and use port services while
saving stays disabled. Compatible normal purchases hand control from the
virtual shuttle to the new owned ship; compatible trades replace the virtual
shuttle. Joyride owns all temporary-ship and return lifecycle behavior.

The `Park Carrier` info action requires at least 90% shields. It creates a
temporary landable spob at the carrier's exact position, giving access to save
and equipment services plus a mess hall represented by the bar interface.
The spob is uninhabited and tagged `nonpc`, preventing faction traffic and
generic patrons while still allowing the player's own crewmates to appear.
Close the Info window after requesting parking so the landing transition can
begin. Taking off removes the spob after the transition has returned to stable
space and restores the carrier in the recorded system at the stored position.
The spob has a permanent unreachable storage system so landed saves always
resolve safely even though its in-space relocation is temporary.
Hailing a deployed ship from the carrier begins an
owned Joyride sortie; hailing another deployed owned escort requests a lateral
seat swap. Hailing the mothership returns only the currently controlled craft
while other escorts remain deployed.

The command action launches the commander's shuttle and transfers control
immediately through Joyride. Activating a general control launches its
assigned owned ship as a vanilla escort, or recalls it when already deployed;
taking control of that ship still requires hailing it. The controls' tooltips
show their live physical-slot assignments without persisting them.

Acquisitions are re-audited after buys, sells, swaps, landing, takeoff, and
system entry. If a hull has no compatible bay, Nomad disables hyperspace only
on the current ship and disables mothership boarding until the fleet fits.
Its per-ship marker ensures Nomad does not clear a no-jump restriction applied
by another system. The generous vanilla fleet capacity is only an AI/capture
enabler; the physical bay audit is the real fleet limit.

State remains version 0. Only an active parked location is persisted; bay
assignments remain derived from installed controls. Prototype saves are not
migrated.

Run `make check` for Lua syntax, manifest validation, and deterministic tests
under Lua and LuaJIT.
