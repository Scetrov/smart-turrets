# Turret Threat Ledger

Seed contract that approximates a threat ledger using only the current candidate list.

## Hard-Coded Configuration

- `tracked_tribe_ids = [200, 300]`
- `tracked_tribe_base_bonuses = [2000, 1000]`
- `THREAT_PER_ACTIVE_AGGRESSOR = 1500`
- behaviour bonuses: started attack `10000`, aggressor `4000`, entered `1000`

## Limitations

- There is no persistent ledger between calls.
- Threat is derived only from aggressors visible in the current candidate list.
- To track different tribes, edit the hard-coded arrays and republish.

## Build And Test

```bash
cd extensions/turret_threat_ledger
sui move build
sui move test
```
