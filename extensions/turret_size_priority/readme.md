# Turret Size Priority

Seed contract that assigns each target a fixed size tier based on `group_id` and adds a tier bonus to the weight.

## Hard-Coded Configuration

- group-to-tier mapping:
  - shuttle `31 -> 1`
  - corvette `237 -> 2`
  - frigate `25 -> 3`
  - destroyer `420 -> 4`
  - cruiser `26 -> 5`
  - combat battlecruiser `419 -> 6`
- `TIER_WEIGHT = 3000`
- behaviour bonuses: started attack `10000`, aggressor `4000`, entered `1000`

## Limitations

- Unknown groups default to the minimum tier.
- The size table is fixed in source.
- There is no runtime way to retune the class mapping.

## Build And Test

```bash
cd extensions/turret_size_priority
sui move build
sui move test
```
