# Turret Low HP Finisher

Seed contract that prefers hostile targets that are already heavily damaged.

## Hard-Coded Configuration

- `STARTED_ATTACK_BONUS = 8000`
- `AGGRESSOR_BONUS = 4000`
- `ENTERED_BONUS = 1500`
- `EHP_DAMAGE_MULTIPLIER = 100`

## Limitations

- The finisher bias is fixed in source.
- There is no runtime control over how strongly damage is weighted.
- The contract does not keep history across calls.

## Build And Test

```bash
cd extensions/turret_low_hp_finisher
sui move build
sui move test
```
