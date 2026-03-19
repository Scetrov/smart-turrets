/// Turret strategy that applies hard-coded weight bonuses to specific ship groups.
///
/// This seed keeps specialization entirely in source code. To change which ship groups are
/// preferred, edit the configured group-id and bonus tables below and republish the package.
module turret_group_specialist::group_specialist;

use sui::{bcs, event};
use world::{
    character::{Self, Character},
    in_game_id,
    turret::{OnlineReceipt, ReturnTargetPriorityList, Turret},
};

use world::turret as world_turret;

#[error(code = 0)]
const EInvalidOnlineReceipt: vector<u8> = b"Invalid online receipt";

// ---------------------------------------------------------------------------
// Compile-time configuration
// ---------------------------------------------------------------------------

const BEHAVIOUR_ENTERED: u8 = 1;
const BEHAVIOUR_STARTED_ATTACK: u8 = 2;
const BEHAVIOUR_STOPPED_ATTACK: u8 = 3;
const STARTED_ATTACK_BONUS: u64 = 10_000;
const AGGRESSOR_BONUS: u64 = 5_000;
const ENTERED_BONUS: u64 = 1_000;

// Hard-coded specialization seed: plasma-style anti-frigate / anti-destroyer tuning.
const GROUP_FRIGATE: u64 = 25;
const GROUP_DESTROYER: u64 = 420;

public struct PriorityListUpdatedEvent has copy, drop {
    turret_id: ID,
    priority_list: vector<u8>,
}

public struct TurretAuth has drop {}

public struct TargetCandidateArg has copy, drop, store {
    item_id: u64,
    type_id: u64,
    group_id: u64,
    character_id: u32,
    character_tribe: u32,
    hp_ratio: u64,
    shield_ratio: u64,
    armor_ratio: u64,
    is_aggressor: bool,
    priority_weight: u64,
    behaviour_change: u8,
}

// ---------------------------------------------------------------------------
// Targeting
// ---------------------------------------------------------------------------

public fun get_target_priority_list(
    turret: &Turret,
    owner_character: &Character,
    target_candidate_list: vector<u8>,
    receipt: OnlineReceipt,
): vector<u8> {
    assert!(receipt.turret_id() == object::id(turret), EInvalidOnlineReceipt);
    let owner_character_id = in_game_id::item_id(&character::key(owner_character)) as u32;
    let return_list = build_priority_list_for_owner(
        owner_character_id,
        character::tribe(owner_character),
        target_candidate_list,
    );
    let result = bcs::to_bytes(&return_list);
    world_turret::destroy_online_receipt(receipt, TurretAuth {});
    event::emit(PriorityListUpdatedEvent {
        turret_id: object::id(turret),
        priority_list: result,
    });
    result
}

// ---------------------------------------------------------------------------
// Internal scoring helpers
// ---------------------------------------------------------------------------

public(package) fun build_priority_list_for_owner(
    owner_character_id: u32,
    owner_tribe: u32,
    target_candidate_list: vector<u8>,
): vector<ReturnTargetPriorityList> {
    let candidates = unpack_candidate_list(target_candidate_list);
    let configured_group_ids = configured_group_ids();
    let configured_group_bonuses = configured_group_bonuses();
    let mut return_list = vector::empty();
    let mut index = 0u64;
    let len = vector::length(&candidates);
    while (index < len) {
        let candidate = vector::borrow(&candidates, index);
        let (weight, include) = score_candidate(
            owner_character_id,
            owner_tribe,
            &configured_group_ids,
            &configured_group_bonuses,
            candidate,
        );
        if (include) {
            vector::push_back(
                &mut return_list,
                world_turret::new_return_target_priority_list(candidate.item_id, weight),
            );
        };
        index = index + 1;
    };
    return_list
}

fun configured_group_ids(): vector<u64> {
    vector[GROUP_FRIGATE, GROUP_DESTROYER]
}

fun configured_group_bonuses(): vector<u64> {
    vector[12_000u64, 8_000u64]
}

fun score_candidate(
    owner_character_id: u32,
    owner_tribe: u32,
    configured_group_ids: &vector<u64>,
    configured_group_bonuses: &vector<u64>,
    candidate: &TargetCandidateArg,
): (u64, bool) {
    let is_owner = candidate.character_id == owner_character_id;
    let same_tribe = candidate.character_tribe == owner_tribe;
    let aggressor = candidate.is_aggressor;
    let reason = candidate.behaviour_change;

    if (is_owner || reason == BEHAVIOUR_STOPPED_ATTACK) {
        return (0, false)
    };
    if (same_tribe && !aggressor) {
        return (0, false)
    };

    let mut weight = candidate.priority_weight;
    if (reason == BEHAVIOUR_STARTED_ATTACK) {
        weight = weight + STARTED_ATTACK_BONUS;
    } else if (reason == BEHAVIOUR_ENTERED) {
        weight = weight + ENTERED_BONUS;
    };
    if (aggressor) {
        weight = weight + AGGRESSOR_BONUS;
    };
    weight = weight + lookup_group_bonus(
        configured_group_ids,
        configured_group_bonuses,
        candidate.group_id,
    );
    (weight, true)
}

fun lookup_group_bonus(
    configured_group_ids: &vector<u64>,
    configured_group_bonuses: &vector<u64>,
    group_id: u64,
): u64 {
    let mut index = 0u64;
    while (index < vector::length(configured_group_ids)) {
        if (*vector::borrow(configured_group_ids, index) == group_id) {
            return *vector::borrow(configured_group_bonuses, index)
        };
        index = index + 1;
    };
    0
}

// ---------------------------------------------------------------------------
// BCS decoding
// ---------------------------------------------------------------------------

fun unpack_candidate_list(candidate_list_bytes: vector<u8>): vector<TargetCandidateArg> {
    if (vector::length(&candidate_list_bytes) == 0) {
        return vector::empty()
    };
    let mut bcs_data = bcs::new(candidate_list_bytes);
    bcs_data.peel_vec!(|candidate_bcs| peel_target_candidate_from_bcs(candidate_bcs))
}

fun peel_target_candidate_from_bcs(bcs_data: &mut bcs::BCS): TargetCandidateArg {
    let item_id = bcs_data.peel_u64();
    let type_id = bcs_data.peel_u64();
    let group_id = bcs_data.peel_u64();
    let character_id = bcs_data.peel_u32();
    let character_tribe = bcs_data.peel_u32();
    let hp_ratio = bcs_data.peel_u64();
    let shield_ratio = bcs_data.peel_u64();
    let armor_ratio = bcs_data.peel_u64();
    let is_aggressor = bcs_data.peel_bool();
    let priority_weight = bcs_data.peel_u64();
    let behaviour_change = bcs_data.peel_u8();
    TargetCandidateArg {
        item_id,
        type_id,
        group_id,
        character_id,
        character_tribe,
        hp_ratio,
        shield_ratio,
        armor_ratio,
        is_aggressor,
        priority_weight,
        behaviour_change,
    }
}
