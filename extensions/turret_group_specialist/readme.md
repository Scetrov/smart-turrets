# Turret Group Specialist

Seed contract that applies hard-coded specialization bonuses to selected ship groups.

## Hard-Coded Configuration

- `configured_group_ids = [25, 420]`
- `configured_group_bonuses = [12000, 8000]`
- current seed is tuned like a plasma-style anti-frigate / anti-destroyer profile
- standard behaviour bonuses remain enabled: started attack `10000`, aggressor `5000`, entered `1000`

## Limitations

- Specialization is fixed in source and cannot be edited on-chain.
- There is no owner-managed mapping or shared config object anymore.
- To target different ship groups, edit the arrays in `sources/turret.move` and republish.

## Build And Test

```bash
cd extensions/turret_group_specialist
sui move build
sui move test
```
