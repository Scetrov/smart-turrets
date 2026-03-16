/// Turret strategy that maintains an on-chain threat ledger tracking cumulative aggression
/// per tribe across multiple targeting calls.
///
/// Each time the turret is invoked, aggressors' tribes accumulate threat in a
/// `Table<u32, u64>` (tribe_id → threat score).  Candidates from tribes with higher accumulated
/// threat receive a proportionally larger weight bonus, so repeat offenders are fired upon with
/// escalating priority.  Sending a `STOPPED_ATTACK` event partially forgives a tribe's threat,
/// rewarding de-escalation.
///
/// Threat is capped per tribe at `max_threat` (configured at creation) to prevent indefinite
/// runaway values.
module turret_threat_ledger::threat_ledger;

use sui::{bcs, table::{Self, Table}};
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
/// Added to a tribe's threat score each time one of their members is an aggressor.
const THREAT_INCREMENT: u64 = 1_000;
/// Subtracted from a tribe's threat when a member sends STOPPED_ATTACK (forgiveness).
const THREAT_DECREMENT: u64 = 500;
/// Default per-tribe threat ceiling.
const DEFAULT_MAX_THREAT: u64 = 20_000;
/// Divisor applied to raw threat score before adding to weight (controls sensitivity).
const THREAT_WEIGHT_DIVISOR: u64 = 2;

/// Persistent on-chain threat ledger for each tribe.
public struct ThreatLedgerConfig has key {
    id: UID,
    turret_id: ID,
    /// tribe_id (u32) → accumulated threat score (u64).
    tribe_threats: Table<u32, u64>,
    /// Maximum threat any single tribe can accumulate.
    max_threat: u64,
}

public struct TurretAuth has drop {}

// ---------------------------------------------------------------------------
// Config management
// ---------------------------------------------------------------------------

public fun create_config(
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    max_threat: u64,
    ctx: &mut TxContext,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    let cap = if (max_threat == 0) { DEFAULT_MAX_THREAT } else { max_threat };
    transfer::share_object(ThreatLedgerConfig {
        id: object::new(ctx),
        turret_id: object::id(turret),
        tribe_threats: table::new(ctx),
        max_threat: cap,
    });
}

/// Manually resets a tribe's threat score to zero (owner only).
public fun pardon_tribe(
    config: &mut ThreatLedgerConfig,
    turret: &Turret,
    owner_cap: &OwnerCap<Turret>,
    tribe_id: u32,
) {
    assert!(access::is_authorized(owner_cap, object::id(turret)), ENotTurretOwner);
    if (table::contains(&config.tribe_threats, tribe_id)) {
        *table::borrow_mut(&mut config.tribe_threats, tribe_id) = 0;
    };
}

/// Returns the current threat score for a tribe (0 if never seen).
public fun tribe_threat(config: &ThreatLedgerConfig, tribe_id: u32): u64 {
    if (table::contains(&config.tribe_threats, tribe_id)) {
        *table::borrow(&config.tribe_threats, tribe_id)
    } else {
        0
    }
}

// ---------------------------------------------------------------------------
// Targeting
// ---------------------------------------------------------------------------

public fun get_target_priority_list(
    turret: &Turret,
    owner_character: &Character,
    config: &mut ThreatLedgerConfig,
    target_candidate_list: vector<u8>,
    receipt: OnlineReceipt,
): vector<u8> {
    assert!(receipt.turret_id() == object::id(turret), EInvalidOnlineReceipt);
    let owner_character_id = in_game_id::item_id(&character::key(owner_character)) as u32;
    let return_list = build_priority_list_for_owner(
        owner_character_id,
        character::tribe(owner_character),
        &mut config.tribe_threats,
        config.max_threat,
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
    tribe_threats: &mut Table<u32, u64>,
    max_threat: u64,
    target_candidate_list: vector<u8>,
): vector<ReturnTargetPriorityList> {
    let candidates = unpack_candidate_list(target_candidate_list);
    // Pass 1: update ledger based on this round's behaviour events
    update_threats(tribe_threats, &candidates, max_threat);
    // Pass 2: score candidates using the now-updated threat scores
    let mut return_list = vector::empty();
    let mut index = 0u64;
    let len = vector::length(&candidates);
    while (index < len) {
        let candidate = vector::borrow(&candidates, index);
        let (weight, include) = score_candidate(
            owner_character_id,
            owner_tribe,
            tribe_threats,
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

/// Updates the threat table: aggressors increment their tribe's threat, STOPPED_ATTACK decrements.
/// Skips tribe_id 0 (NPCs have no tribe).
fun update_threats(
    tribe_threats: &mut Table<u32, u64>,
    candidates: &vector<TargetCandidateArg>,
    max_threat: u64,
) {
    let mut i = 0u64;
    let len = vector::length(candidates);
    while (i < len) {
        let candidate = vector::borrow(candidates, i);
        let tribe = candidate.character_tribe;
        if (tribe != 0) {
            if (candidate.behaviour_change == BEHAVIOUR_STOPPED_ATTACK) {
                if (table::contains(tribe_threats, tribe)) {
                    let threat = table::borrow_mut(tribe_threats, tribe);
                    if (*threat >= THREAT_DECREMENT) {
                        *threat = *threat - THREAT_DECREMENT;
                    } else {
                        *threat = 0;
                    };
                };
            } else if (candidate.is_aggressor) {
                if (table::contains(tribe_threats, tribe)) {
                    let threat = table::borrow_mut(tribe_threats, tribe);
                    let new_val = *threat + THREAT_INCREMENT;
                    *threat = if (new_val > max_threat) { max_threat } else { new_val };
                } else {
                    let initial = if (THREAT_INCREMENT > max_threat) {
                        max_threat
                    } else {
                        THREAT_INCREMENT
                    };
                    table::add(tribe_threats, tribe, initial);
                };
            };
        };
        i = i + 1;
    };
}

fun score_candidate(
    owner_character_id: u32,
    owner_tribe: u32,
    tribe_threats: &Table<u32, u64>,
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
    // Threat bonus — capped by max_threat / DIVISOR
    let threat = get_tribe_threat(tribe_threats, candidate.character_tribe);
    weight = weight + (threat / THREAT_WEIGHT_DIVISOR);
    (weight, true)
}

fun get_tribe_threat(tribe_threats: &Table<u32, u64>, tribe: u32): u64 {
    if (table::contains(tribe_threats, tribe)) {
        *table::borrow(tribe_threats, tribe)
    } else {
        0
    }
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
