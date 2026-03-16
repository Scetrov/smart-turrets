/// Turret strategy that uses an owner-managed on-chain blocklist to permanently exclude specific
/// ship type_ids from being targeted, while applying standard aggression-based scoring to everyone
/// else.
///
/// The owner creates a shared `TypeBlocklistConfig` object (via `create_config`), then calls
/// `add_blocked_type` / `remove_blocked_type` with their `OwnerCap<Turret>` at any time to update
/// the list. The turret's `get_target_priority_list` reads the config and skips any candidate whose
/// `type_id` appears in it.
module turret_type_blocklist::type_blocklist;

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

/// Shared configuration object. Owned logically by the turret owner via their `OwnerCap<Turret>`.
/// Pass a reference to this when calling `get_target_priority_list`.
public struct TypeBlocklistConfig has key {
    id: UID,
    /// The Turret object ID this config belongs to. Enforced on every targeting call.
    turret_id: ID,
    /// type_ids that must never be targeted.
    blocked_type_ids: vector<u64>,
}

public struct TurretAuth has drop {}

// ---------------------------------------------------------------------------
// Config management
// ---------------------------------------------------------------------------

/// Creates and shares a new empty blocklist config for the given turret.
/// Must be called by the turret owner.
public fun create_config(
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    ctx: &mut TxContext,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    let config = TypeBlocklistConfig {
        id: object::new(ctx),
        turret_id: object::id(turret),
        blocked_type_ids: vector::empty(),
    };
    transfer::share_object(config);
}

/// Adds a type_id to the blocklist. No-op if already present.
public fun add_blocked_type(
    config: &mut TypeBlocklistConfig,
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    type_id: u64,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    if (!vector::contains(&config.blocked_type_ids, &type_id)) {
        vector::push_back(&mut config.blocked_type_ids, type_id);
    };
}

/// Removes a type_id from the blocklist. No-op if not present.
public fun remove_blocked_type(
    config: &mut TypeBlocklistConfig,
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    type_id: u64,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    let (found, index) = vector::index_of(&config.blocked_type_ids, &type_id);
    if (found) {
        vector::remove(&mut config.blocked_type_ids, index);
    };
}

/// Returns a copy of the currently blocked type_ids.
public fun blocked_type_ids(config: &TypeBlocklistConfig): vector<u64> {
    config.blocked_type_ids
}

// ---------------------------------------------------------------------------
// Targeting
// ---------------------------------------------------------------------------

public fun get_target_priority_list(
    turret: &Turret,
    owner_character: &Character,
    config: &TypeBlocklistConfig,
    target_candidate_list: vector<u8>,
    receipt: OnlineReceipt,
): vector<u8> {
    assert!(receipt.turret_id() == object::id(turret), EInvalidOnlineReceipt);
    let owner_character_id = in_game_id::item_id(&character::key(owner_character)) as u32;
    let return_list = build_priority_list_for_owner(
        owner_character_id,
        character::tribe(owner_character),
        &config.blocked_type_ids,
        target_candidate_list,
    );
    world_turret::destroy_online_receipt(receipt, TurretAuth {});
    bcs::to_bytes(&return_list)
}

// ---------------------------------------------------------------------------
// Internal helpers (public(package) for unit tests)
// ---------------------------------------------------------------------------

public(package) fun build_priority_list_for_owner(
    owner_character_id: u32,
    owner_tribe: u32,
    blocked_type_ids: &vector<u64>,
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
            blocked_type_ids,
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
    blocked_type_ids: &vector<u64>,
    candidate: &TargetCandidateArg,
): (u64, bool) {
    let is_owner = candidate.character_id == owner_character_id;
    let same_tribe = candidate.character_tribe == owner_tribe;
    let aggressor = candidate.is_aggressor;
    let reason = candidate.behaviour_change;

    // Hard excludes
    if (is_owner || reason == BEHAVIOUR_STOPPED_ATTACK) {
        return (0, false)
    };
    if (same_tribe && !aggressor) {
        return (0, false)
    };
    if (vector::contains(blocked_type_ids, &candidate.type_id)) {
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
    (weight, true)
}

// ---------------------------------------------------------------------------
// BCS deserialization (mirrors world::turret's encoding)
// ---------------------------------------------------------------------------

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
