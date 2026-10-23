# RUIN Finder changelog

Versioning: the third number counts the meaningful changes made since the second number last went up.

## Unreleased

(nothing yet)

## 0.4.0 — 2026-10-23 · Beta 1

The RUIN Gaming Companion App enters beta: every addon is now 0.4.0. Nothing changed since 0.3.6 apart from the version number. Report what you find under Settings → Feedback.

## 0.3.6 — 2026-10-23

3 changes since 0.3.5:

1. **Ask, Invite and Request to join.** Every row has *Ask* (whisper); players also have *Invite*, groups *Request to join*: the group's leader gets a prompt with your role, class and level and invites you with one click.
2. **Your group listing keeps count.** When someone joins your group, the role they fill comes off what the group still needs (and goes back on if they leave): the game's role for them, else the role they asked to join as, else their Finder listing's, else DPS. Finder says when the group is full.
3. The on-screen badge is only as wide as its text.

## 0.3.5 — 2026-10-19

1 change since 0.3.4 (needs RUIN Core 0.3.12):

1. **A clearer listing card, in Finder's color.** "Your listing" reads left to right: I'm looking, As (player or group), the roles you can play, then Activity, which dungeon or zone, a note and your spec, each box with a hint inside it. Alerts and the on-screen badge moved to the card's corner, away from your roles. The card is shorter for player listings, and the status message points to the Options page for the org key.

## 0.3.4 — 2026-10-19

1 change since 0.3.3:

1. Back to the original name (Finder) in the RUIN window and addon list, after 0.3.3's short-lived rename. Its tab now sits in the order Guild, Finder, Muster, Pathfinder, Codex, Exchange, Options.

## 0.3.3 — 2026-10-19

1 change since 0.3.2:

1. **New display name** (Groups tab, Group Finder page), to match the RUIN Gaming Companion App brief and RUIN Core 0.3.10's new tab order. The addon list shows it as "Groups (Finder)". The tabs now read in the brief's plain language. Only what players see changed: the addon folder, repository, command and saved-data names stay the same, so nothing needs reinstalling or re-setting.

## 0.3.2 — 2026-10-19

1 change since 0.3.1:

1. New `QuickList` so another RUIN module can start a group listing in one call. RUIN Muster's *Find group* button on a boss, rare or enemy sighting uses it (RUIN Intel's sightings moved to Muster).

## 0.3.1 — 2026-10-18

1 change since 0.3.0:

1. Picks up the new RUIN look from Core 0.3.7 and joins the RUIN Gaming Companion App (navy window, tabs across the top, the Finder tab), and the TOC lists Retail's interface number next to WoW Forever's. Works with RUIN Core 0.3.0 or later.

## 0.3.0 — 2026-10-18

- Suite release: every RUIN addon moves to 0.3.0 together, bringing everything from the 0.2.x entries below. No further code changes.
- Needs RUIN Core 0.3.0.
- From now on a RUIN addon's 0.3.x number counts its own changes since this release.

## 0.2.5 — 2026-10-18

5 changes since 0.2.0:

Needs RUIN Core 0.2.6 or later.

1. Group listings: list your group with the tanks, healers and DPS it still needs ("As: Group" or `/finder group dungeon`).
2. Automatic matching: a player who can fill a role a group of the same activity needs is a match. Both get an alert, and matches sort to the top.
3. On-screen Looking badge with your activity and match count. Left-click opens Finder, right-click stops looking, and you can drag it (`/finder badge`).
4. Level-range filter: all levels, or within 3, 5 or 10 levels of you.
5. RUIN Muster events with open slots appear on the board with a Sign up button. The page is redesigned with role icons, a status card and row tooltips.

## 0.2.0 — 2026-10-18

- Suite milestone: every RUIN addon moves to 0.2.0 together. No code changes since the last 0.1 release.
- With RUIN Core 0.2.0, this module's page opens in the new RUIN window with its own themed header: notes pinned to a board.

## 0.1.2 — 2026-10-18

- Fixed: "Binding header RUIN was attempted to be loaded more than once". Each module now has its own section under Key Bindings, and all of its bindings load.
- Your own listing now shows at the top of the board (marked "You"), so you can see exactly what others see.
- A status line says whether your listing is live, or that you're not connected to the RUIN org channel yet.

## 0.1.0 — 2026-10-18

First proof of concept.
