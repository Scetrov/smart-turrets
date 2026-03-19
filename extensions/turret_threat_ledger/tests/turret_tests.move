#[test_only]
module turret_threat_ledger::threat_ledger_tests;

use std::{bcs, unit_test::assert_eq};
use turret_threat_ledger::threat_ledger;
use world::turret::ReturnTargetPriorityList;

const OWNER_CHARACTER_ID: u32 = 108;
const OWNER_TRIBE: u32 = 100;
const TRIBE_A: u32 = 200;
const TRIBE_B: u32 = 300;
const TRIBE_C: u32 = 400;

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

fun candidate(
    item_id: u64,
    character_tribe: u32,
    is_aggressor: bool,
    behaviour_change: u8,
): TargetCandidateBcs {
    TargetCandidateBcs {
        item_id,
        type_id: 1,
        group_id: 1,
        character_id: 900,
        character_tribe,
        hp_ratio: 100,
        shield_ratio: 100,
        armor_ratio: 100,
        is_aggressor,
        priority_weight: 0,
        behaviour_change,
    }
}

fun bytes(entries: vector<TargetCandidateBcs>): vector<u8> { bcs::to_bytes(&entries) }

fun assert_entry(entry: &ReturnTargetPriorityList, expected_item_id: u64, expected_weight: u64) {
    use world::turret;
    assert_eq!(turret::return_target_item_id(entry), expected_item_id);
    assert_eq!(turret::return_priority_weight(entry), expected_weight);
}

fun build(entries: vector<TargetCandidateBcs>): vector<ReturnTargetPriorityList> {
    threat_ledger::build_priority_list_for_owner(OWNER_CHARACTER_ID, OWNER_TRIBE, bytes(entries))
}

#[test]
fun tracked_tribe_a_gets_base_and_pressure_bonus() {
    let result = build(vector[candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 17500);
}

#[test]
fun multiple_aggressors_from_same_tracked_tribe_raise_bonus() {
    let result = build(vector[
        candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK),
        candidate(102, TRIBE_A, true, BEHAVIOUR_ENTERED),
    ]);
    assert_eq!(vector::length(&result), 2);
    assert_entry(vector::borrow(&result, 0), 101, 19000);
    assert_entry(vector::borrow(&result, 1), 102, 10000);
}

#[test]
fun tracked_tribe_b_uses_its_own_base_bonus() {
    let result = build(vector[candidate(101, TRIBE_B, true, BEHAVIOUR_ENTERED)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 7500);
}

#[test]
fun untracked_tribe_gets_no_threat_bonus() {
    let result = build(vector[candidate(101, TRIBE_C, true, BEHAVIOUR_STARTED_ATTACK)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 14000);
}

#[test]
fun output_is_stateless_across_calls() {
    let first = build(vector[candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK)]);
    let second = build(vector[candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK)]);
    assert_entry(vector::borrow(&first, 0), 101, 17500);
    assert_entry(vector::borrow(&second, 0), 101, 17500);
}

#[test]
fun standard_exclusions_still_apply() {
    let result = build(vector[
        TargetCandidateBcs {
            item_id: 101,
            type_id: 1,
            group_id: 1,
            character_id: 900,
            character_tribe: OWNER_TRIBE,
            hp_ratio: 100,
            shield_ratio: 100,
            armor_ratio: 100,
            is_aggressor: false,
            priority_weight: 0,
            behaviour_change: BEHAVIOUR_ENTERED,
        },
        candidate(102, TRIBE_A, true, BEHAVIOUR_STOPPED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 0);
}
