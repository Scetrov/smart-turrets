# Turret Low HP Finisher

Standalone smart turret strategy package for the `low_hp_finisher` behavior.

Witness type:

- `<PACKAGE_ID>::low_hp_finisher::TurretAuth`

Behavior:

- excludes owner and same-tribe non-aggressors
- favors already damaged hostile targets
- still rewards active aggression and attack starts

## Flowchart

```mermaid
flowchart TD
    A([get_target_priority_list]) --> B{receipt.turret_id<br/>== turret.id?}
    B -- No --> ABORT([Abort])
    B -- Yes --> C[Decode BCS candidate list]
    C --> D{More candidates?}
    D -- No --> DONE([Return BCS-encoded priority list])
    D -- Yes --> E[Next candidate]
    E --> F{Is turret owner\nOR stopped attacking?}
    F -- Yes --> EXCLUDE[Exclude]
    F -- No --> G{Same tribe\nAND not aggressor?}
    G -- Yes --> EXCLUDE
    G -- No --> H[weight = priority_weight]
    H --> I{Behaviour change?}
    I -- STARTED_ATTACK --> J["+8,000"]
    I -- ENTERED --> K["+1,500"]
    I -- Other --> L{Is aggressor?}
    J --> L
    K --> L
    L -- Yes --> M["+4,000 aggressor bonus"]
    L -- No --> N[Apply EHP damage bonus]
    M --> N
    N --> O["total_damage = 300 - hp - shield - armor\nweight += total_damage × 100"]
    O --> INCLUDE[Include with final weight]
    INCLUDE --> D
    EXCLUDE --> D
```

Build and test:

```bash
cd move-contracts/turret_low_hp_finisher
sui move build -e testnet
sui move test
```
