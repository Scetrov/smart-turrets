/// Turret strategy that lets the owner assign custom weight bonuses per ship `group_id`.
///
/// The owner deploys a shared `GroupSpecialistConfig` object and populates it with
/// `GroupBonus` entries that map a `group_id` to an additional weight bonus.  On each
/// targeting call the turret looks up the candidate's `group_id` in the config and adds
/// the matching bonus before returning the priority list.
///
/// Typical use-case: align the bonus table with the weapon's intended target class.
/// For example an Autocannon turret (specialised against Shuttles group=31 and Corvettes group=237)
/// would give those group_ids a large bonus, while a Howitzer (Cruiser=26 / BattleCruiser=419)
/// would boost those instead.  Standard aggression bonuses still apply on top.
module turret_group_specialist::group_specialist;

use sui::bcs;
use world::{
    access::{Self, OwnerCap},
    character::{Self, Character},
    in_game_id,
    turret::{OnlineReceipt, ReturnTargetPriorityList, Turret},
};

use world::turret as world_turret;

#[error(code = 0)]
const EInvalidOnlineReceipt: vector<u8> = b"Invalid online receipt";
#[error(code = 1)]
const ENotTurretOwner: vector<u8> = b"Caller is not the turret owner";

const BEHAVIOUR_ENTERED: u8 = 1;
const BEHAVIOUR_STARTED_ATTACK: u8 = 2;
const BEHAVIOUR_STOPPED_ATTACK: u8 = 3;
const STARTED_ATTACK_BONUS: u64 = 10_000;
const AGGRESSOR_BONUS: u64 = 5_000;
const ENTERED_BONUS: u64 = 1_000;

/// A group_id → weight-bonus mapping entry.
public struct GroupBonus has copy, drop, store {
    group_id: u64,
    weight_bonus: u64,
}

/// Shared configuration for the group specialist strategy.
/// Keyed to a specific turret; the owner manages entries via `OwnerCap<Turret>`.
public struct GroupSpecialistConfig has key {
    id: UID,
    /// The Turret object ID this config belongs to.
    turret_id: ID,
    /// List of group_id → bonus mappings.  Lookup is linear; typically short.
    group_bonuses: vector<GroupBonus>,
}

public struct TurretAuth has drop {}

// ---------------------------------------------------------------------------
// Config management
// ---------------------------------------------------------------------------

public fun create_config(
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    ctx: &mut TxContext,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    transfer::share_object(GroupSpecialistConfig {
        id: object::new(ctx),
        turret_id: object::id(turret),
        group_bonuses: vector::empty(),
    });
}

/// Adds or replaces the weight bonus for a given `group_id`.
public fun set_group_bonus(
    config: &mut GroupSpecialistConfig,
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    group_id: u64,
    weight_bonus: u64,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    // Remove existing entry for this group_id if present
    let mut i = 0u64;
    while (i < vector::length(&config.group_bonuses)) {
        if (vector::borrow(&config.group_bonuses, i).group_id == group_id) {
            vector::remove(&mut config.group_bonuses, i);
            break
        };
        i = i + 1;
    };
    vector::push_back(&mut config.group_bonuses, GroupBonus { group_id, weight_bonus });
}

/// Removes the weight bonus entry for a `group_id`. No-op if not present.
public fun remove_group_bonus(
    config: &mut GroupSpecialistConfig,
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    group_id: u64,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    let mut i = 0u64;
    while (i < vector::length(&config.group_bonuses)) {
        if (vector::borrow(&config.group_bonuses, i).group_id == group_id) {
            vector::remove(&mut config.group_bonuses, i);
            return
        };
        i = i + 1;
    };
}

/// Returns a copy of the current group bonuses.
public fun group_bonuses(config: &GroupSpecialistConfig): vector<GroupBonus> {
    config.group_bonuses
}

/// Constructs a GroupBonus entry (for extensions and tests).
public fun new_group_bonus(group_id: u64, weight_bonus: u64): GroupBonus {
    GroupBonus { group_id, weight_bonus }
}

// ---------------------------------------------------------------------------
// Targeting
// ---------------------------------------------------------------------------

public fun get_target_priority_list(
    turret: &Turret,
    owner_character: &Character,
    config: &GroupSpecialistConfig,
    target_candidate_list: vector<u8>,
    receipt: OnlineReceipt,
): vector<u8> {
    assert!(receipt.turret_id() == object::id(turret), EInvalidOnlineReceipt);
    let owner_character_id = in_game_id::item_id(&character::key(owner_character)) as u32;
    let return_list = build_priority_list_for_owner(
        owner_character_id,
        character::tribe(owner_character),
        &config.group_bonuses,
        target_candidate_list,
    );
    world_turret::destroy_online_receipt(receipt, TurretAuth {});
    bcs::to_bytes(&return_list)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

public(package) fun build_priority_list_for_owner(
    owner_character_id: u32,
    owner_tribe: u32,
    group_bonuses: &vector<GroupBonus>,
    target_candidate_list: vector<u8>,
): vector<ReturnTargetPriorityList> {
    let candidates = unpack_candidate_list(target_candidate_list);
    let mut return_list = vector::empty();
    let mut index = 0u64;
    let len = vector::length(&candidates);
    while (index < len) {
        let candidate = vector::borrow(&candidates, index);
        let (weight, include) = score_candidate(
            owner_character_id,
            owner_tribe,
            group_bonuses,
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

fun score_candidate(
    owner_character_id: u32,
    owner_tribe: u32,
    group_bonuses: &vector<GroupBonus>,
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
    weight = weight + lookup_group_bonus(group_bonuses, candidate.group_id);
    (weight, true)
}

fun lookup_group_bonus(group_bonuses: &vector<GroupBonus>, group_id: u64): u64 {
    let mut i = 0u64;
    while (i < vector::length(group_bonuses)) {
        let entry = vector::borrow(group_bonuses, i);
        if (entry.group_id == group_id) {
            return entry.weight_bonus
        };
        i = i + 1;
    };
    0
}

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

fun unpack_candidate_list(candidate_list_bytes: vector<u8>): vector<TargetCandidateArg> {
    if (vector::length(&candidate_list_bytes) == 0) {
        return vector::empty()
    };
    let mut bcs_data = bcs::new(candidate_list_bytes);
    bcs_data.peel_vec!(|bcs| peel_target_candidate_from_bcs(bcs))
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
