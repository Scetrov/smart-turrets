# Turret Last Stand

Seed contract that switches between normal mode and raid mode based on how many aggressors are present in the current candidate list.

## Hard-Coded Configuration

- `RAID_THRESHOLD = 3`
- normal mode bonuses: started attack `10000`, aggressor `5000`, entered `1000`
- raid mode bonuses: started attack `30000`, aggressor `20000`, entered `500`
- `RAID_DAMAGE_MULTIPLIER = 150`

## Limitations

- Raid mode is recalculated fresh each call.
- There is no persistent alert level or battle memory.
- Thresholds and weights can only be changed by editing source and republishing.

## Build And Test

```bash
cd extensions/turret_last_stand
sui move build
sui move test
```
