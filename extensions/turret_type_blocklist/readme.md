# Turret Type Blocklist

Standalone smart turret strategy package for the `type_blocklist` behavior.

Witness type:

- `<PACKAGE_ID>::type_blocklist::TurretAuth`

Behavior:

- excludes any candidate whose `type_id` appears in the owner-configured blocklist
- excludes the turret owner and same-tribe non-aggressors
- excludes candidates that stopped attacking
- applies standard aggression-based scoring to all remaining candidates

## Configuration Object

The owner deploys a shared `TypeBlocklistConfig` object alongside the turret and passes it into every targeting call. The list can be updated at any time using `OwnerCap<Turret>`:

| Function | Description |
|---|---|
| `create_config(turret, owner_cap, ctx)` | Creates and shares a new empty blocklist |
| `add_blocked_type(config, turret, owner_cap, type_id)` | Adds a type_id to the blocklist |
| `remove_blocked_type(config, turret, owner_cap, type_id)` | Removes a type_id from the blocklist |
| `blocked_type_ids(config)` | Read-only view of current blocked type_ids |

Common ship `type_id` values (from the extension example comments):

| Ship class | type_id |
|---|---|
| Shuttle | 31 |
| Corvette | 237 |
| Frigate | 25 |
| Destroyer | 420 |
| Cruiser | 26 |
| Combat Battlecruiser | 419 |

## Flowchart

```mermaid
flowchart TD
    A([get_target_priority_list]) --> B{receipt.turret_id<br/>== turret.id?}
    B -- No --> ABORT([Abort])
    B -- Yes --> C[Decode BCS candidate list]
    C --> D{More candidates?}
    D -- No --> DONE([Return BCS-encoded priority list])
    D -- Yes --> E[Next candidate]
    E --> F{Is turret owner<br/>OR stopped attacking?}
    F -- Yes --> EXCLUDE[Exclude]
    F -- No --> G{Same tribe<br/>AND not aggressor?}
    G -- Yes --> EXCLUDE
    G -- No --> H{type_id in<br/>blocklist?}
    H -- Yes --> EXCLUDE
    H -- No --> I[weight = priority_weight]
    I --> J{Behaviour change?}
    J -- STARTED_ATTACK --> K["+10,000"]
    J -- ENTERED --> L["+1,000"]
    J -- Other --> M{Is aggressor?}
    K --> M
    L --> M
    M -- Yes --> N["+5,000 aggressor bonus"]
    M -- No --> INCLUDE[Include with final weight]
    N --> INCLUDE
    INCLUDE --> D
    EXCLUDE --> D
```

Build and test:

```bash
cd extensions/turret_type_blocklist
sui move build
sui move test
```
