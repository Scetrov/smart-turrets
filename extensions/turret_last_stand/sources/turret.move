/// Adaptive turret strategy that switches scoring mode based on the intensity of the current
/// engagement.
///
/// **Normal mode** (< 3 active aggressors in the candidate list):
///   - Applies standard tribe/owner exclusions with modest behaviour bonuses.
///
/// **Raid mode** (≥ 3 active aggressors detected):
///   - Removes tribe-based exclusion — every non-owner, non-stopped candidate is eligible.
///   - Applies massive bonuses for active attackers and damage-based weight for wounded targets,
///     ensuring the turret focuses fire to eliminate threats rapidly.
///
/// The threshold is evaluated fresh each call from the live candidate list, so the mode
/// automatically drops back to normal once aggressors stop appearing.
///
/// Compile-time configuration is limited to the threshold and bonus constants below. There is no
/// persistent mode state in this seed.
module turret_last_stand::last_stand;

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

/// Number of simultaneous aggressors required to enter raid mode.
const RAID_THRESHOLD: u64 = 3;

// Normal-mode weight bonuses
const NORMAL_STARTED_ATTACK_BONUS: u64 = 10_000;
const NORMAL_AGGRESSOR_BONUS: u64 = 5_000;
const NORMAL_ENTERED_BONUS: u64 = 1_000;

// Raid-mode weight bonuses — significantly larger to reflect emergency priority
const RAID_STARTED_ATTACK_BONUS: u64 = 30_000;
const RAID_AGGRESSOR_BONUS: u64 = 20_000;
const RAID_ENTERED_BONUS: u64 = 500;
/// Per combined-damage-percent bonus (sum of shield + armor + hull damage %).
const RAID_DAMAGE_MULTIPLIER: u64 = 150;

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
    let is_raid = count_aggressors(&candidates) >= RAID_THRESHOLD;
    let mut return_list = vector::empty();
    let mut index = 0u64;
    let len = vector::length(&candidates);
    while (index < len) {
        let candidate = vector::borrow(&candidates, index);
        let (weight, include) = if (is_raid) {
            score_raid(owner_character_id, candidate)
        } else {
            score_normal(owner_character_id, owner_tribe, candidate)
        };
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

fun count_aggressors(candidates: &vector<TargetCandidateArg>): u64 {
    let mut count = 0u64;
    let mut i = 0u64;
    let len = vector::length(candidates);
    while (i < len) {
        if (vector::borrow(candidates, i).is_aggressor) {
            count = count + 1;
        };
        i = i + 1;
    };
    count
}

/// Conservative scoring: standard tribe/owner exclusions with modest bonuses.
fun score_normal(
    owner_character_id: u32,
    owner_tribe: u32,
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
        weight = weight + NORMAL_STARTED_ATTACK_BONUS;
    } else if (reason == BEHAVIOUR_ENTERED) {
        weight = weight + NORMAL_ENTERED_BONUS;
    };
    if (aggressor) {
        weight = weight + NORMAL_AGGRESSOR_BONUS;
    };
    (weight, true)
}

/// Raid scoring: includes everyone except owner and stopped-attackers, applies heavy damage
/// multipliers to focus fire on already-wounded targets.
fun score_raid(
    owner_character_id: u32,
    candidate: &TargetCandidateArg,
): (u64, bool) {
    let is_owner = candidate.character_id == owner_character_id;
    let reason = candidate.behaviour_change;

    if (is_owner || reason == BEHAVIOUR_STOPPED_ATTACK) {
        return (0, false)
    };

    let mut weight = candidate.priority_weight;
    if (reason == BEHAVIOUR_STARTED_ATTACK) {
        weight = weight + RAID_STARTED_ATTACK_BONUS;
    } else if (reason == BEHAVIOUR_ENTERED) {
        weight = weight + RAID_ENTERED_BONUS;
    };
    if (candidate.is_aggressor) {
        weight = weight + RAID_AGGRESSOR_BONUS;
    };
    // Combined damage bonus: higher the more the target's total HP has been reduced
    let total_remaining = candidate.hp_ratio + candidate.shield_ratio + candidate.armor_ratio;
    let damage_taken = if (total_remaining <= 300) { 300 - total_remaining } else { 0 };
    weight = weight + (damage_taken * RAID_DAMAGE_MULTIPLIER);
    (weight, true)
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
