# Contract Template

This is the default example contract:

```move
module extension_examples::turret;

use sui::{bcs, event};
use world::{character::Character, turret::{Self, Turret, OnlineReceipt}};

#[error(code = 0)]
const EInvalidOnlineReceipt: vector<u8> = b"Invalid online receipt";

public struct PriorityListUpdatedEvent has copy, drop {
    turret_id: ID,
    priority_list: vector<u8>,
}

public struct TurretAuth has drop {}

// More details to make decisions
// The below are the groupIDs for the different ship types and the turrets that are specialized against them
// This can help the turret to prioritize the targets based on the ship type and the turret that is specialized against it
// Shuttle - groupID: 31
// Corvette - groupID: 237
// Frigate - groupID: 25
// Destroyer - groupID: 420
// Cruiser - groupID: 26
// Combat Battlecruiser - groupID: 419
// Turret - Autocannon (92402)
//   - Specialized against: Shuttle(31), Corvette(237)
// Turret - Plasma (92403)
//   - Specialized against: Frigate(25), Destroyer(420)
// Turret - Howitzer (92484)
//   - Specialized against: Cruiser(26), Combat Battlecruiser(419)
// Regardless of the target, add it to the priority list as a example
// Example: build return list (target_item_id, priority_weight) from the priority list.
// Extension uses turret::unpack_candidate_list(target_candidate_list) to get vector<TargetCandidate>.
public fun get_target_priority_list(
    turret: &Turret,
    _: &Character,
    target_candidate_list: vector<u8>,
    receipt: OnlineReceipt,
): vector<u8> {
    assert!(receipt.turret_id() == object::id(turret), EInvalidOnlineReceipt);

    let _ = turret::unpack_candidate_list(target_candidate_list);
    // Return empty priority list for this example; extension can build return_list from candidates.
    // TODO: The return list is mutable expecting the extension to mutate it.
    let mut return_list = vector::empty<turret::ReturnTargetPriorityList>();
    let result = bcs::to_bytes(&return_list);

    turret::destroy_online_receipt(receipt, TurretAuth {});
    event::emit(PriorityListUpdatedEvent {
        turret_id: object::id(turret),
        priority_list: result,
    });
    result
}
```

## Template

The template for all extensions must conform to the following signatures:

```move
// this must not be turret to avoid conflict with the turret module in world
module extension_examples::{extension_name}; 

use sui::{bcs, event}; // required to encode/decode bcs and emit events
use world::{character::Character, turret::{Self, Turret, OnlineReceipt}};

#[error(code = 0)]
const EInvalidOnlineReceipt: vector<u8> = b"Invalid online receipt";

// emit this event after the priority list is updated
public struct PriorityListUpdatedEvent has copy, drop {
    turret_id: ID,
    priority_list: vector<u8>,
}

public struct TurretAuth has drop {}

public fun get_target_priority_list(
    turret: &Turret,
    _: &Character,
    target_candidate_list: vector<u8>,
    receipt: OnlineReceipt,
): vector<u8> {
    assert!(receipt.turret_id() == object::id(turret), EInvalidOnlineReceipt);

    // extract the type from BCS encoding    
    let _ = turret::unpack_candidate_list(target_candidate_list);
    
    // Return empty priority list for this example; extension can build return_list from candidates.
    // TODO: The return list is mutable expecting the extension to mutate it.
    let mut return_list = vector::empty<turret::ReturnTargetPriorityList>();

    // Example: build return list (target_item_id, priority_weight) from the priority list.
    let result = bcs::to_bytes(&return_list);

    // We have to destroy the receipt at the end of the function
    turret::destroy_online_receipt(receipt, TurretAuth {});

    // Emit an event so that this can be tracked
    event::emit(PriorityListUpdatedEvent {
        turret_id: object::id(turret),
        priority_list: result,
    });

    // return the result
    result
}
```
