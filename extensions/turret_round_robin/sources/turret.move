/// Turret strategy that spreads fire evenly across multiple targets instead of permanently
/// focusing the same ship.
///
/// A mutable shared `RoundRobinConfig` tracks the `item_id`s of recently targeted ships in a
/// bounded ring-buffer.  Any candidate whose `item_id` appears in that history receives a large
/// weight penalty.  After each call the item most likely to be fired at (highest weight) is
/// recorded in the history, so the next call naturally de-prioritises it.
///
/// This is useful when you want to disable multiple attackers' shields in parallel rather than
/// destroying one ship at a time, or when you want to discourage a single player from tanking
/// the turret indefinitely.
module turret_round_robin::round_robin;

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
const AGGRESSOR_BONUS: u64 = 4_000;
const ENTERED_BONUS: u64 = 1_000;
/// Weight subtracted from a recently-targeted ship. Floored at 1 so it remains in the list.
const HISTORY_PENALTY: u64 = 15_000;
/// Default ring-buffer capacity if the owner does not specify one.
const DEFAULT_HISTORY_MAX_SIZE: u64 = 3;

/// Mutable shared state that records which ships were recently targeted.
public struct RoundRobinConfig has key {
    id: UID,
    turret_id: ID,
    /// Ring-buffer of recently targeted item_ids (oldest at index 0).
    history: vector<u64>,
    /// Maximum number of item_ids to keep in history.
    history_max_size: u64,
}

public struct TurretAuth has drop {}

// ---------------------------------------------------------------------------
// Config management
// ---------------------------------------------------------------------------

public fun create_config(
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    history_max_size: u64,
    ctx: &mut TxContext,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    let max = if (history_max_size == 0) { DEFAULT_HISTORY_MAX_SIZE } else { history_max_size };
    transfer::share_object(RoundRobinConfig {
        id: object::new(ctx),
        turret_id: object::id(turret),
        history: vector::empty(),
        history_max_size: max,
    });
}

/// Clears the targeting history (e.g. after a battle ends).
public fun reset_history(
    config: &mut RoundRobinConfig,
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    config.history = vector::empty();
}

public fun history(config: &RoundRobinConfig): vector<u64> { config.history }

// ---------------------------------------------------------------------------
// Targeting
// ---------------------------------------------------------------------------

public fun get_target_priority_list(
    turret: &Turret,
    owner_character: &Character,
    config: &mut RoundRobinConfig,
    target_candidate_list: vector<u8>,
    receipt: OnlineReceipt,
): vector<u8> {
    assert!(receipt.turret_id() == object::id(turret), EInvalidOnlineReceipt);
    let owner_character_id = in_game_id::item_id(&character::key(owner_character)) as u32;
    let return_list = build_priority_list_for_owner(
        owner_character_id,
        character::tribe(owner_character),
        &mut config.history,
        config.history_max_size,
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
    history: &mut vector<u64>,
    history_max_size: u64,
    target_candidate_list: vector<u8>,
): vector<ReturnTargetPriorityList> {
    let candidates = unpack_candidate_list(target_candidate_list);
    let mut return_list = vector::empty();
    let mut winner_item_id: Option<u64> = option::none();
    let mut winner_weight: u64 = 0;

    let mut index = 0u64;
    let len = vector::length(&candidates);
    while (index < len) {
        let candidate = vector::borrow(&candidates, index);
        let (weight, include) = score_candidate(
            owner_character_id,
            owner_tribe,
            history,
            candidate,
        );
        if (include) {
            // Track the highest-weight candidate to record in history
            if (weight > winner_weight || option::is_none(&winner_item_id)) {
                winner_weight = weight;
                winner_item_id = option::some(candidate.item_id);
            };
            vector::push_back(
                &mut return_list,
                world_turret::new_return_target_priority_list(candidate.item_id, weight),
            );
        };
        index = index + 1;
    };

    // Record the predicted target so it gets penalised next call
    if (option::is_some(&winner_item_id)) {
        push_to_history(history, *option::borrow(&winner_item_id), history_max_size);
    };
    return_list
}

fun score_candidate(
    owner_character_id: u32,
    owner_tribe: u32,
    history: &vector<u64>,
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

    // Apply history penalty — floor at 1 to keep the candidate in the list
    if (vector::contains(history, &candidate.item_id)) {
        weight = if (weight > HISTORY_PENALTY) { weight - HISTORY_PENALTY } else { 1 };
    };
    (weight, true)
}

/// Adds `item_id` to the history ring-buffer.
/// If the item is already present it is moved to the most-recent position.
/// The oldest entry is evicted when the buffer exceeds `max_size`.
fun push_to_history(history: &mut vector<u64>, item_id: u64, max_size: u64) {
    let (found, idx) = vector::index_of(history, &item_id);
    if (found) {
        vector::remove(history, idx);
    };
    vector::push_back(history, item_id);
    while (vector::length(history) > max_size) {
        vector::remove(history, 0);
    };
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
