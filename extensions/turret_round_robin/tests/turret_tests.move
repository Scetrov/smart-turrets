#[test_only]
module turret_round_robin::round_robin_tests;

use std::{bcs, unit_test::assert_eq};
use turret_round_robin::round_robin;
use world::turret::ReturnTargetPriorityList;

const OWNER_CHARACTER_ID: u32 = 108;
const OWNER_TRIBE: u32 = 100;

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
    is_aggressor: bool,
    behaviour_change: u8,
): TargetCandidateBcs {
    TargetCandidateBcs {
        item_id,
        type_id: 1,
        group_id: 1,
        character_id: 900,
        character_tribe: 200,
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
    round_robin::build_priority_list_for_owner(OWNER_CHARACTER_ID, OWNER_TRIBE, bytes(entries))
}

#[test]
fun preferred_lane_receives_bonus() {
    let result = build(vector[candidate(102, true, BEHAVIOUR_STARTED_ATTACK)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 102, 16000);
}

#[test]
fun non_preferred_lane_receives_penalty() {
    let result = build(vector[candidate(101, true, BEHAVIOUR_ENTERED)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 2000);
}

#[test]
fun penalty_floors_at_one() {
    let result = build(vector[candidate(100, false, BEHAVIOUR_ENTERED)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 100, 1);
}

#[test]
fun standard_exclusions_still_apply() {
    let result = build(vector[
        TargetCandidateBcs {
            item_id: 102,
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
        candidate(105, true, BEHAVIOUR_STOPPED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 0);
}
