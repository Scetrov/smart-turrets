# Turret Aggressor First

Seed contract that prioritizes active aggressors first and then leans toward damaged hostile targets.

## Hard-Coded Configuration

- `STARTED_ATTACK_BONUS = 20000`
- `AGGRESSOR_BONUS = 5000`
- `ENTERED_BONUS = 2000`
- damage multipliers: shield `20`, armor `10`, hull `5`

## Limitations

- All weighting is fixed at publish time.
- There is no per-turret config object or runtime override.
- The contract only looks at the current candidate list; it does not keep history.

## Build And Test

```bash
cd extensions/turret_aggressor_first
sui move build
sui move test
```
