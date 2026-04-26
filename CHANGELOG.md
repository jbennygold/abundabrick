# AbundaBrick

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
