# Turret Threat Ledger

Standalone smart turret strategy package for the `threat_ledger` behavior.

Witness type:

- `<PACKAGE_ID>::threat_ledger::TurretAuth`

Behavior:

- maintains a persistent on-chain `Table<tribe_id, threat_score>` inside a shared `ThreatLedgerConfig`
- each targeting call first updates the ledger: aggressors increment their tribe's threat by `+1,000`; `STOPPED_ATTACK` decrements by `−500` (forgiveness)
- tribe threat is capped at `max_threat` (default 20,000) to prevent unbounded accumulation
- the weight bonus applied to each candidate equals `tribe_threat ÷ 2`
- tribes that consistently aggress face escalating weight bonuses; de-escalation gradually reduces them
- tribe_id `0` (NPCs) is ignored and never written to the ledger

## Configuration Functions

| Function | Description |
|---|---|
| `create_config(turret, owner_cap, max_threat, ctx)` | Creates and shares a new threat ledger |
| `pardon_tribe(config, turret, owner_cap, tribe_id)` | Resets a tribe's threat to zero |
| `tribe_threat(config, tribe_id)` | Read-only view of a tribe's current threat score |

## Flowchart

```mermaid
flowchart TD
    A([get_target_priority_list]) --> B{receipt.turret_id<br/>== turret.id?}
    B -- No --> ABORT([Abort])
    B -- Yes --> C[Decode BCS candidate list]
    C --> UPD[Pass 1: Update threat ledger]
    UPD --> UA{Each candidate<br/>tribe_id != 0?}
    UA -- aggressor --> UB["tribe_threat += 1,000 (capped)"]
    UA -- STOPPED_ATTACK --> UC["tribe_threat -= 500 (floor 0)"]
    UA -- other --> UD[No change]
    UB --> SCORE
    UC --> SCORE
    UD --> SCORE
    SCORE[Pass 2: Score candidates] --> D{More candidates?}
    D -- No --> DONE([Return BCS-encoded priority list])
    D -- Yes --> E[Next candidate]
    E --> F{Owner OR<br/>stopped attacking?}
    F -- Yes --> EXCLUDE[Exclude]
    F -- No --> G{Same tribe AND<br/>not aggressor?}
    G -- Yes --> EXCLUDE
    G -- No --> H["weight = base + behaviour + aggressor bonuses<br/>+ tribe_threat ÷ 2"]
    H --> INCLUDE[Include with final weight]
    INCLUDE --> D
    EXCLUDE --> D
```

Build and test:

```bash
cd extensions/turret_threat_ledger
sui move build
sui move test
```
