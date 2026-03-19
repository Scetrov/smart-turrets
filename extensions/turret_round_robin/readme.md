# Turret Round Robin

Seed contract that approximates round-robin targeting with deterministic item-id lane sharding.

## Hard-Coded Configuration

- `ROTATION_BUCKET_COUNT = 3`
- `preferred_slots = [0]`
- `PREFERRED_SLOT_BONUS = 2000`
- `NON_PREFERRED_SLOT_PENALTY = 3000`

## Limitations

- This is not true round-robin state tracking.
- The contract cannot remember previous targets because the template does not allow persistent mutable strategy state here.
- To spread fire across a battery, FrontierFlow should generate variants with different preferred slots.

## Build And Test

```bash
cd extensions/turret_round_robin
sui move build
sui move test
```
