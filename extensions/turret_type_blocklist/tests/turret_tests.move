#[test_only]
module turret_type_blocklist::type_blocklist_tests;

use std::{bcs, unit_test::assert_eq};
use turret_type_blocklist::type_blocklist;
use world::turret::ReturnTargetPriorityList;

const OWNER_CHARACTER_ID: u32 = 108;
const OWNER_TRIBE: u32 = 100;

// Ship type_ids used across tests
const TYPE_SHUTTLE: u64 = 31;
const TYPE_FRIGATE: u64 = 25;
const TYPE_CRUISER: u64 = 26;

const BEHAVIOUR_ENTERED: u8 = 1;
const BEHAVIOUR_STARTED_ATTACK: u8 = 2;
const BEHAVIOUR_STOPPED_ATTACK: u8 = 3;

public struct TargetCandidateBcs has copy, drop {
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

fun candidate_list_bytes(entries: vector<TargetCandidateBcs>): vector<u8> { bcs::to_bytes(&entries) }

fun candidate(
    item_id: u64,
    type_id: u64,
    character_id: u32,
    character_tribe: u32,
    is_aggressor: bool,
    priority_weight: u64,
    behaviour_change: u8,
): TargetCandidateBcs {
    TargetCandidateBcs {
        item_id,
        type_id,
        group_id: 1,
        character_id,
        character_tribe,
        hp_ratio: 100,
        shield_ratio: 100,
        armor_ratio: 100,
        is_aggressor,
        priority_weight,
        behaviour_change,
    }
}

fun assert_entry(entry: &ReturnTargetPriorityList, expected_item_id: u64, expected_weight: u64) {
    use world::turret;
    assert_eq!(turret::return_target_item_id(entry), expected_item_id);
    assert_eq!(turret::return_priority_weight(entry), expected_weight);
}

// ---------------------------------------------------------------------------
// Helper to call build_priority_list_for_owner with a blocklist vector
// ---------------------------------------------------------------------------

fun build(
    blocked: vector<u64>,
    entries: vector<TargetCandidateBcs>,
): vector<ReturnTargetPriorityList> {
    type_blocklist::build_priority_list_for_owner(
        OWNER_CHARACTER_ID,
        OWNER_TRIBE,
        &blocked,
        candidate_list_bytes(entries),
    )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[test]
fun empty_blocklist_includes_all_hostile_candidates() {
    let result = build(
        vector[],
        vector[
            // hostile, different tribe, entered
            candidate(101, TYPE_FRIGATE, 900, 200, false, 10, BEHAVIOUR_ENTERED),
            // hostile aggressor, started attack
            candidate(102, TYPE_CRUISER, 901, 200, true, 20, BEHAVIOUR_STARTED_ATTACK),
        ],
    );
    assert_eq!(vector::length(&result), 2);
    // 101: 10 + 1000 (ENTERED) = 1010
    assert_entry(vector::borrow(&result, 0), 101, 1010);
    // 102: 20 + 10000 (STARTED_ATTACK) + 5000 (AGGRESSOR) = 15020
    assert_entry(vector::borrow(&result, 1), 102, 15020);
}

#[test]
fun blocklisted_type_id_is_excluded() {
    let result = build(
        vector[TYPE_SHUTTLE],
        vector[
            // shuttle — should be excluded
            candidate(101, TYPE_SHUTTLE, 900, 200, true, 50, BEHAVIOUR_STARTED_ATTACK),
            // frigate — not blocked, should be included
            candidate(102, TYPE_FRIGATE, 901, 200, true, 20, BEHAVIOUR_STARTED_ATTACK),
        ],
    );
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 102, 15020);
}

#[test]
fun multiple_blocked_type_ids_all_excluded() {
    let result = build(
        vector[TYPE_SHUTTLE, TYPE_FRIGATE],
        vector[
            candidate(101, TYPE_SHUTTLE, 900, 200, true, 10, BEHAVIOUR_ENTERED),
            candidate(102, TYPE_FRIGATE, 901, 200, true, 10, BEHAVIOUR_ENTERED),
            // cruiser — not in blocklist
            candidate(103, TYPE_CRUISER, 902, 200, false, 5, BEHAVIOUR_ENTERED),
        ],
    );
    assert_eq!(vector::length(&result), 1);
    // 103: 5 + 1000 (ENTERED) = 1005
    assert_entry(vector::borrow(&result, 0), 103, 1005);
}

#[test]
fun owner_is_always_excluded_regardless_of_blocklist() {
    let result = build(
        vector[], // no blocklist
        vector[
            candidate(101, TYPE_FRIGATE, OWNER_CHARACTER_ID, OWNER_TRIBE, true, 100, BEHAVIOUR_STARTED_ATTACK),
        ],
    );
    assert_eq!(vector::length(&result), 0);
}

#[test]
fun same_tribe_non_aggressor_excluded() {
    let result = build(
        vector[],
        vector[
            candidate(101, TYPE_FRIGATE, 900, OWNER_TRIBE, false, 10, BEHAVIOUR_ENTERED),
        ],
    );
    assert_eq!(vector::length(&result), 0);
}

#[test]
fun same_tribe_aggressor_included() {
    let result = build(
        vector[],
        vector[
            candidate(101, TYPE_FRIGATE, 900, OWNER_TRIBE, true, 10, BEHAVIOUR_ENTERED),
        ],
    );
    assert_eq!(vector::length(&result), 1);
    // 10 + 1000 (ENTERED) + 5000 (AGGRESSOR) = 6010
    assert_entry(vector::borrow(&result, 0), 101, 6010);
}

#[test]
fun stopped_attack_always_excluded() {
    let result = build(
        vector[],
        vector[
            candidate(101, TYPE_FRIGATE, 900, 200, true, 50, BEHAVIOUR_STOPPED_ATTACK),
        ],
    );
    assert_eq!(vector::length(&result), 0);
}

#[test]
fun empty_candidate_list_returns_empty_result() {
    let result = build(vector[TYPE_SHUTTLE], vector[]);
    assert_eq!(vector::length(&result), 0);
}
