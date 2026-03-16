# Turret Round Robin

Standalone smart turret strategy package for the `round_robin` behavior.

Witness type:

- `<PACKAGE_ID>::round_robin::TurretAuth`

Behavior:

- maintains a mutable on-chain `RoundRobinConfig` tracking the `item_id`s of recently targeted ships in a bounded ring-buffer
- any candidate whose `item_id` appears in the history receives a `−15,000` weight penalty (floored at 1 so it stays in the list)
- after each call the highest-weight candidate (likely the next target) is recorded in the history
- once the buffer reaches `history_max_size`, the oldest entry is evicted

Use this strategy to spread fire across multiple attackers rather than permanently focusing a single ship.

## Configuration Functions

| Function | Description |
|---|---|
| `create_config(turret, owner_cap, history_max_size, ctx)` | Creates and shares a new history config |
| `reset_history(config, turret, owner_cap)` | Clears the target history |
| `history(config)` | Read-only view of current history |

## Flowchart

```mermaid
flowchart TD
    A([get_target_priority_list]) --> B{receipt.turret_id<br/>== turret.id?}
    B -- No --> ABORT([Abort])
    B -- Yes --> C[Decode BCS candidate list]
    C --> D{More candidates?}
    D -- No --> REC[Record winner in history<br/>ring-buffer]
    REC --> DONE([Return BCS-encoded priority list])
    D -- Yes --> E[Next candidate]
    E --> F{Owner OR<br/>stopped attacking?}
    F -- Yes --> EXCLUDE[Exclude]
    F -- No --> G{Same tribe AND<br/>not aggressor?}
    G -- Yes --> EXCLUDE
    G -- No --> H[weight = base + behaviour + aggressor bonuses]
    H --> I{item_id in<br/>recent history?}
    I -- Yes --> J["weight = max(1, weight − 15,000)"]
    I -- No --> INCLUDE[Include with final weight]
    J --> INCLUDE
    INCLUDE --> D
    EXCLUDE --> D
```

Build and test:

```bash
cd extensions/turret_round_robin
sui move build
sui move test
```
