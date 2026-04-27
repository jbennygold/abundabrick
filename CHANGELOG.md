# AbundaBrick

## v1.0.2 (2026-04-27)

- Track stacks accurately during combat in instances. Blizzard's private-aura system silences the Abundance buff (and returns secret values for some aura fields) while in combat, leaving the bar empty in real 5-mans.
- Adds three layered sources: the player aura API (out-of-combat truth), a scan of Rejuvenation/Germination auras applied to group members, and a cast-event tracker fed by `UNIT_SPELLCAST_SENT`/`UNIT_SPELLCAST_SUCCEEDED`. Authoritative sources seed the tracker, and the tracker carries the bar through silenced windows.
- Hardened against the new secret-value aura fields — no more "attempted to index a table that cannot be indexed with secret keys" in instance combat.
- Auto-trims the cast tracker against authoritative readings when they reappear, eliminating refresh-overcount lag after combat ends.
- Per-target dedup via `UNIT_SPELLCAST_SENT` avoids counting Rejuv refreshes as new stacks.
- Adds diagnostic logging behind `/abrick log on|off` (off by default).

## v1.0.1 (2026-04-26)

- Bar is now hidden on non-Restoration-Druid characters and specs.
- Re-evaluates on `PLAYER_SPECIALIZATION_CHANGED` so it shows/hides correctly when switching specs in-session.

## v1.0.0 (2026-04-25)

- Initial release.
- Tracks Restoration Druid Abundance buff stacks (spell 207640) with 10 colored bricks.
- Red (1–3), yellow (4–7), green (8–10).
- Movable, lockable bar with horizontal or vertical orientation.
- Configurable width, height, brick spacing, and padding.
- Toggle for hiding when inactive and showing dimmed empty bricks.
- Slash commands: `/abrick`, `/abrick lock`, `/abrick unlock`, `/abrick reset`, `/abrick test`.
