# Turret Player Screen

Seed contract that filters out NPC candidates and focuses on hostile player pilots.

## Hard-Coded Configuration

- NPCs are excluded when `character_id == 0`
- `PLAYER_TARGET_BONUS = 1000`
- `STARTED_ATTACK_BONUS = 15000`
- `AGGRESSOR_BONUS = 6000`
- `ENTERED_BONUS = 3000`

## Limitations

- The contract cannot whitelist or blacklist specific tribes or pilots.
- All player-screening behaviour is fixed at publish time.
- There is no runtime configuration object.

## Build And Test

```bash
cd extensions/turret_player_screen
sui move build
sui move test
```
