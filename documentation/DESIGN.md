# THE LAST MOVE — game design

## One sentence

A first-person co-op physics comedy where one to four movers empty houses that do not want
to be emptied, and where the hardest object in the game is always a three-seat sofa going
through a door built for one person.

## The fantasy

You are crew ten of a moving company that has, according to its own internal memos,
dispatched nine previous crews to these addresses. The work is ordinary: catalogue the
contracted items, carry them out, stack them in the truck, clock out before the deadline.
The setting is not ordinary: the addresses are a house that rearranges itself, a manor of
dolls, a house filling with water, a home that tidies itself, a hotel that is both closed
and fully booked, a building that breathes, and a final rotunda holding one crate that is
not furniture.

The comedy comes from the collision between the two: professional, procedural paperwork
against domestic architecture that is actively hostile and, worse, *considerate*.

## Core loop

1. **Headquarters** — read the contract board, buy upgrades from the equipment station,
   check the performance board, walk to the truck.
2. **Contract briefing** — the property code, the contracted items, the deadline, the
   modifiers, dispatch notes, and the company memo for that property.
3. **The move** — survey the property, work out the route, decide the carry order, take
   the item apart from the room at the cost of the route out. Every piece has a weight, a
   grip count, a fragility and a minimum crew.
4. **Loading** — the item is only "delivered" when its entire footprint is inside the
   cargo volume, it has stopped moving, and the rear doors were open when it went in.
5. **Clock out** — the contract resolves into a performance evaluation, a payout, an
   unlocked next property, and a memo nobody asked for.

A contract takes 8–20 minutes depending on how badly the crew plans. Deadline, damage,
unauthorised items and crew losses all feed the payout; the payout is shared.

## Carrying model

Holding an object is a physics problem, not an animation.

- Every item has a set of grip points in local space. A mover can take one; two to four
  movers can share the same object.
- The host applies a PD force toward each holder's grip target. The applied force is
  capped at `mass * 9 * crew_strength * lift_factor`, so an under-crewed lift does not
  just fail — it *drags*, slowly, scraping the floor, making noise.
- Under-crewed lifts run at `DRAG_LIFT_FACTOR = 0.42`: the object stays on the ground and
  the crew makes a noise like a wardrobe learning to walk.
- Player speed scales with carried weight (`lerp(1.0, 0.42, weight/130)`), drops by 28%
  when under-crewed, and rises 18% with the dolly upgrade.
- Rotation is torque, not instant yaw, so turning a sofa in a corridor is a negotiation.
- Damage accumulates from impacts and scrapes; at 100% the item is destroyed, its value is
  lost, and it leaves debris, noise, and a line on the report.

The result: a corridor is a puzzle, a doorway is a boss, and the funniest thing in the game
is three people disagreeing about which end goes first.

## Properties

| # | id | title | difficulty | deadline | base pay | the joke |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | willow | The Willow Residence | Easy | 13:00 | $900 | a normal house with one garage door you are told not to open |
| 2 | endless | The Endless House | Medium | 17:00 | $1450 | four rooms that are not where the floor plan says |
| 3 | dollhouse | The Dollhouse | Medium | 19:00 | $1800 | the dolls move when nobody is looking; one of them follows you home |
| 4 | sinking | The Sinking House | Hard | 21:00 | $2450 | water rises for the whole contract; the valuables are in the basement |
| 5 | perfect | The Perfect Home | Hard | 20:00 | $3100 | the house tidies itself, and it disagrees with you about where things go |
| 6 | hotel | The Grand Meridian | Very Hard | 24:00 | $3900 | three floors, one lying elevator, room numbers that shuffle |
| 7 | breathing | The House That Breathes | Very Hard | 25:00 | $4700 | walls that slide, a floor that inhales, passages that close |
| 8 | last_customer | The Last Customer | Extreme | 29:00 | $12000 | four wings, one vault, one crate, one customer |

All eight are hand-authored layouts in `scripts/levels/level_*.gd`, built from the shared
kit in `level_kit.gd` and furnished from `resources/items.json`.

## Supernatural layer

Creatures are obstacles with opinions, not combat encounters. There are no weapons. The
counterplay is light, silence, numbers, and a well-aimed chair.

| creature | behaviour | counterplay |
| --- | --- | --- |
| **The Tenant** | hunts a mover who is alone; freezes then retreats in a flashlight beam; backs off from a crew of three | stay together, keep the beam on it |
| **The Doll** | perfectly still whenever observed, moves fast when not; lunges when close | watch it, or move it somewhere it does not want to be |
| **The Breather** | blind; hunts noise, not sight; fast, slow to lose a trail | crouch, stop carrying, do not scrape |
| **The Bellhop** | wants the furniture, not the crew: takes a carried item and drags it into the dark | put it down, chase it, hit it |

All four are banished by three solid hits from moving furniture. Banishing is worth
`$45` each in the final payout, which is the game's way of saying *yes, throw the chair*.

The **director** (`creature_manager.gd`) keeps pressure uneven: it never spawns inside
sight, it scales the number of simultaneous creatures with the property's difficulty rank,
it calms down for 12 seconds after the crew is already hurt, and it pushes harder as the
contract approaches completion.

## Scoring

```
payout = base_pay × completion × value_mult
       + optional_value × 0.75
       + base_pay × 0.22 × (time_left / time_total)
       + base_pay × 0.10 × crew_survival
       + 45 × creatures_banished
       − property_damage × 0.55
payout × 0.6 if the deadline was missed, minimum 0
success = completion ≥ 0.999    partial = completion ≥ 0.34
```

Damage is the interesting term: it punishes the exact behaviour (impatience, dragging,
throwing) that the comedy rewards, so a crew has to decide when to be funny and when to
be professional.

## Progression and economy

- Eight properties unlock in order. Credits are shared by the crew.
- 16 upgrades across gloves, straps, dolly, flashlight, helmet, ramp, detector, medkit and
  four truck improvements (capacity, lights, straps, suspension) plus two paint jobs.
- 11 achievements, from *Employee of the Month* (no damage) to *Ten Out Of Ten* (finish the
  campaign).
- The profile stores credits, unlocked properties, upgrades, cosmetics, achievements,
  statistics and how many story memos have been read.

## Campaign ending

The final contract is the crate. If it is delivered, the epilogue plays: the house stops
breathing, dispatch says the crew is clear for the next address, and there is no next
address. If the final contract is only partially completed, the crew gets the other ending
— the house lets them leave, which is worse. Both are in `resources/flavor.json` under
`ending`.

## Teaching the game

There is no tutorial level. A new crew is dropped into a contract and taught one thing at a
time, once, at the moment it becomes relevant: the doors, the grip, the weight, the first
load, damage, the first creature, a downed mover, the clock. Each line fires once per save
profile and is stored in `profile.hints_seen`; Settings has an on/off switch and a
"replay all hints" button, so a returning crew is never lectured and a new one is never
lost. The headquarters likewise introduces itself once.

## Tone rules

1. The horror is domestic and administrative, never gory.
2. The company is the real antagonist; the house is just the venue.
3. Nothing is explained twice. Memos contradict each other; that is the joke.
4. Physical comedy is always legible: if something goes wrong, the player can see why.
5. No cruelty to the crew — downed players are carried, revived, and mocked, in that order.
