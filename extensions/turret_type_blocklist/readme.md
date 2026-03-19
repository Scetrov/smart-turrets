# Turret Type Blocklist

Seed contract that excludes candidates whose `type_id` appears in a hard-coded blocklist.

## Hard-Coded Configuration

- `blocked_type_ids = [31, 237]`
- behaviour bonuses for allowed targets: started attack `10000`, aggressor `5000`, entered `1000`

## Limitations

- Blocked ids are fixed in source.
- There is no owner-managed config object or on-chain editing path.
- The sample ids are seed values and should be replaced with real deployment-specific `type_id` values.

## Build And Test

```bash
cd extensions/turret_type_blocklist
sui move build
sui move test
```
