# Smart Turrets

This repository contains standalone Move smart-turret seeds for EVE Frontier.

All contracts now follow the same constraint set:

- the public targeting entrypoint keeps the template-compatible signature from CONTRACT_TEMPLATE.md
- configuration is hard-coded in source as compile-time constants or fixed helper tables
- no contract depends on owner-managed runtime config objects
- every contract documents the limits of that simplification so FrontierFlow can replace the hard-coded values later

## Seed Catalog

| Extension                 | Hard-coded configuration                                 | Main limitation                                       |
| ------------------------- | -------------------------------------------------------- | ----------------------------------------------------- |
| `turret_aggressor_first`  | bonus weights and damage multipliers                     | no runtime tuning per turret                          |
| `turret_group_specialist` | `group_ids = [25, 420]`, `bonuses = [12000, 8000]`       | specialization is fixed at publish time               |
| `turret_last_stand`       | raid threshold and normal/raid bonus constants           | no persistent state between calls                     |
| `turret_low_hp_finisher`  | behaviour bonuses and damage multiplier                  | no deployment-specific weighting without code changes |
| `turret_player_screen`    | player-only filtering and fixed bonuses                  | cannot whitelist specific tribes or pilots            |
| `turret_round_robin`      | preferred `item_id % 3` lane = `[0]`                     | no real history, only deterministic lane sharding     |
| `turret_size_priority`    | ship-size tier mapping and `tier_weight = 3000`          | only known groups get meaningful size tiers           |
| `turret_threat_ledger`    | tracked tribes `[200, 300]`, base bonuses `[2000, 1000]` | no cross-call threat persistence                      |
| `turret_type_blocklist`   | blocked `type_ids = [31, 237]`                           | blocked ids are fixed in source                       |

## Notes For FrontierFlow

These packages are now usable as seed templates rather than final configurable products.

FrontierFlow should treat the hard-coded tables as generation inputs:

- swap constants and fixed arrays during generation
- keep `get_target_priority_list` and receipt destruction aligned with CONTRACT_TEMPLATE.md
- leave strategy-specific helpers and tests in place unless the generated variant needs different semantics

## Build And Test

Each extension is self-contained:

```bash
cd extensions/<extension_name>
sui move build
sui move test
```

The local environment helper mentioned in the repo instructions could not be checked in this shell because `efctl` is not installed here.
