# RUIN Finder

An org-wide Looking For Group board: who in any RUIN guild wants to do what, right now, and which groups still need a player.

Part of the **RUIN Gaming Companion App**. Requires **RUIN Core** (0.3.0 or later); works with or without any other RUIN module. With **RUIN Muster** installed, events that still need players appear on the board.

## The experience
- **Where it lives:** the Finder tab in the RUIN window, `/finder`, two key bindings (open, and toggle "I'm looking"), and a small on-screen badge while you're listed.
- **Look as a player:** tick *I'm looking*, pick your roles and an activity (Dungeon, Raid, PvP, Questing, Professions, Social), optionally say which dungeon or zone and add a note. You appear on everyone's board within a couple of seconds.
- **List your group:** switch *As: Player* to *As: Group* and set how many tanks, healers and DPS you still need. The board shows "Group of 3 · needs 1 healer". When someone joins your group, the role they fill comes off what you still need (and goes back on if they leave): the role the game shows for them, else the role they asked to join as, else their Finder listing's role, else DPS.
- **Matching:** a player who can fill a role a group of the same activity needs is a *match*. Both sides get an alert, matches sort to the top of the board, and the badge counts them.
- **Finding people:** every row has *Ask* (whisper). Players have *Invite*; groups have *Request to join*, which sends the group's leader a prompt with your role, class and level, and one click invites you. Filter by activity and by level range (within 3, 5 or 10 levels of you). Hover a row for zone and guild.
- **Muster events:** upcoming RUIN events with open slots are listed on the board with a *Sign up* button that uses the first role you ticked that is open.
- **From a sighting:** RUIN Muster's sightings (boss, rare, enemy group) have a *Find group* button that fills in your listing as a group for that activity and turns *I'm looking* on.
- **Badge:** just as wide as its text; left-click opens Finder, right-click stops looking, drag to move. Turn it off with the Badge box or `/finder badge`.
- **Where (RUIN Core 0.4.3):** online members of every RUIN guild by continent and zone, with the names in each zone and a whisper button, and a pin on each zone of the world map with how many are there. Only zones are known: nobody's exact position is shared.
- **Layers (RUIN Core 0.4.3):** Finder works out which layer of a zone you're on from the creatures around you (target or mouse over a couple, or let their nameplates show). Two different creatures must agree, and keep agreeing for a few seconds, before Finder says you changed layer, so a pet or a stray creature doesn't fool it. The Layers tab shows who in RUIN is on which layer of each zone.
- **Layer hop:** *Ask for a hop* (or `/finder hop`) asks the members on another layer of your zone; one of them invites you (or Finder does it for them if they ticked *Help hops automatically*), Finder accepts that invite (and only that one), the game moves you to their layer, and *Leave group* (or `/finder leave`) leaves once you're there.
- **Member marks:** players from the org's guilds get a small RUIN mark on their nameplate, and their guild tag under your target frame. Turn it off with *Member marks* on the Where tab.
- **Timers (moved here from RUIN Muster):** world boss kills and world buff drops (`/finder timer songflower`, `/finder timer dragonslayer 5`), shared with the org, with a warning a minute before an announced buff drops. Respawn windows are Classic's, as a guide.
- **Quick commands:** `/finder on dungeon`, `/finder group dungeon`, `/finder off`, `/finder badge`, `/finder where`, `/finder layers`, `/finder hop`, `/finder leave`, `/finder timer <name> [minutes]`.

## What it shares with RUIN
A small beacon (roles, activity, note, level, zone, and for groups the roles still needed) on the org channel when you change it and every 2 minutes. Entries vanish after 5 minutes without a refresh. Your zone and layer number when your layer changes (at most every 30 seconds), hop requests, and timers you report. Timers travel as `Muster:TIMER`, as Muster sent them, so members on older Muster versions still get them.

## Notes
Spec is guessed from talent points and can be typed by hand.
