# Turret Group Specialist

Standalone smart turret strategy package for the `group_specialist` behavior.

Witness type:

- `<PACKAGE_ID>::group_specialist::TurretAuth`

Behavior:

- owner maintains an on-chain `GroupSpecialistConfig` mapping `group_id → weight_bonus`
- each candidate's `group_id` is looked up in the config; a matching entry adds its bonus to the weight
- intended for weapon-class alignment — e.g. an Autocannon turret should have large bonuses for Shuttles (31) and Corvettes (237); a Howitzer for Cruisers (26) and Combat Battlecruisers (419)
- standard aggressor/tribe/owner exclusions still apply

## Configuration Functions

| Function | Description |
|---|---|
| `create_config(turret, owner_cap, ctx)` | Creates and shares an empty specialisation config |
| `set_group_bonus(config, turret, owner_cap, group_id, bonus)` | Adds or replaces a bonus for a group_id |
| `remove_group_bonus(config, turret, owner_cap, group_id)` | Removes a bonus entry |
| `group_bonuses(config)` | Read-only view of all entries |

## Flowchart

```mermaid
flowchart TD
    A([get_target_priority_list]) --> B{receipt.turret_id<br/>== turret.id?}
    B -- No --> ABORT([Abort])
    B -- Yes --> C[Decode BCS candidate list]
    C --> D{More candidates?}
    D -- No --> DONE([Return BCS-encoded priority list])
    D -- Yes --> E[Next candidate]
    E --> F{Owner OR<br/>stopped attacking?}
    F -- Yes --> EXCLUDE[Exclude]
    F -- No --> G{Same tribe AND<br/>not aggressor?}
    G -- Yes --> EXCLUDE
    G -- No --> H[weight = priority_weight]
    H --> I{Behaviour change?}
    I -- STARTED_ATTACK --> J["+10,000"]
    I -- ENTERED --> K["+1,000"]
    I -- Other --> L{Is aggressor?}
    J --> L
    K --> L
    L -- Yes --> M["+5,000 aggressor bonus"]
    L -- No --> N{group_id in<br/>config bonuses?}
    M --> N
    N -- Yes --> O["weight += group bonus"]
    N -- No --> INCLUDE[Include with final weight]
    O --> INCLUDE
    INCLUDE --> D
    EXCLUDE --> D
```

Build and test:

```bash
cd extensions/turret_group_specialist
sui move build
sui move test
```
