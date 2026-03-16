# Turret Aggressor First

Standalone smart turret strategy package for the `aggressor_first` behavior.

Witness type:

- `<PACKAGE_ID>::aggressor_first::TurretAuth`

Behavior:

- prioritizes active aggressors
- keeps hostile off-tribe targets eligible
- adds extra weight for damaged targets so the turret tends to finish fights

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
    F -- No --> G{Is aggressor\nOR different tribe?}
    G -- No --> EXCLUDE
    G -- Yes --> H[weight = priority_weight]
    H --> I{Behaviour change?}
    I -- STARTED_ATTACK --> J["+20,000"]
    I -- ENTERED --> K["+2,000"]
    I -- Other --> L{Is aggressor?}
    J --> L
    K --> L
    L -- Yes --> M["+5,000 aggressor bonus"]
    L -- No --> N[Apply damage bonuses]
    M --> N
    N --> O["+shield_damage × 20\n+armor_damage × 10\n+hull_damage × 5"]
    O --> INCLUDE[Include with final weight]
    INCLUDE --> D
    EXCLUDE --> D
```

Build and test:

```bash
cd move-contracts/turret_aggressor_first
sui move build -e testnet
sui move test
```
