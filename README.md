# Nomad Fleet

Nomad is a carrier campaign for Naev. New Nomad pilots begin in an unarmed
Za'lek Hephaestus which is permanently tagged as their non-landing
mothership. Pilots created by other scenarios are unaffected.

The carrier has four fixed general bays: **XL + L + 2S**. S accepts hull sizes
1–2, L accepts 1–5, and XL accepts 1–6. Ordinary owned ships are audited
largest-first and placed in the smallest compatible remaining bay. The
Crewmates commander's virtual shuttle has a separate S command bay and never
appears in or consumes the ordinary fleet.

Nomad registers one Crewmates commander with an Alpaca shuttle and the
`nomad` Joyride profile. The shuttle can land and use port services while
saving stays disabled. Compatible normal purchases hand control from the
virtual shuttle to the new owned ship; compatible trades replace the virtual
shuttle. Joyride owns all temporary-ship and return lifecycle behavior.

The Nomad Carrier info menu reports live bay usage and launches or recalls
ordinary ships with vanilla fleet AI. Hailing a deployed ship from the carrier
begins an owned Joyride sortie; hailing another deployed owned escort requests
a lateral seat swap. Hailing the mothership returns only the currently
controlled craft while other escorts remain deployed.

The carrier also installs one-shot command, XL, L, and two S outfit controls.
Activating the command control launches the commander's shuttle and transfers
control immediately through Joyride. Activating a general control launches its
assigned owned ship as a vanilla escort, or recalls it when already deployed;
taking control of that ship still requires hailing it. The controls' tooltips
show their live physical-slot assignments without persisting them.

Acquisitions are re-audited after buys, sells, swaps, landing, takeoff, and
system entry. If a hull has no compatible bay, Nomad disables hyperspace only
on the current ship and disables mothership boarding until the fleet fits.
Its per-ship marker ensures Nomad does not clear a no-jump restriction applied
by another system. The generous vanilla fleet capacity is only an AI/capture
enabler; the physical bay audit is the real fleet limit.

State remains version 0 and persists no bay assignments, ship locations,
deployment tree, damage, or loss records. Prototype saves are not migrated.

Run `make check` for Lua syntax, manifest validation, and deterministic tests
under Lua and LuaJIT.
