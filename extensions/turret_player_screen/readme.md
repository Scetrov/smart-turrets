# Turret Player Screen

Standalone smart turret strategy package for the `player_screen` behavior.

Witness type:

- `<PACKAGE_ID>::player_screen::TurretAuth`

Behavior:

- ignores NPC candidates
- ignores same-tribe non-aggressors
- boosts player attackers and entered-range hostile pilots

## Flowchart

```mermaid
flowchart TD
    A([get_target_priority_list]) --> B{receipt.turret_id<br/>== turret.id?}
    B -- No --> ABORT([Abort])
    B -- Yes --> C[Decode BCS candidate list]
    C --> D{More candidates?}
    D -- No --> DONE([Return BCS-encoded priority list])
    D -- Yes --> E[Next candidate]
    E --> F{Is NPC, is owner,\nOR stopped attacking?}
    F -- Yes --> EXCLUDE[Exclude]
    F -- No --> G{Same tribe\nAND not aggressor?}
    G -- Yes --> EXCLUDE
    G -- No --> H["weight = priority_weight + 1,000"]
    H --> I{Behaviour change?}
    I -- STARTED_ATTACK --> J["+15,000"]
    I -- ENTERED --> K["+3,000"]
    I -- Other --> L{Is aggressor?}
    J --> L
    K --> L
    L -- Yes --> M["+6,000 aggressor bonus"]
    L -- No --> INCLUDE[Include with final weight]
    M --> INCLUDE
    INCLUDE --> D
    EXCLUDE --> D
```

Build and test:

```bash
cd move-contracts/turret_player_screen
sui move build -e testnet
sui move test
```
