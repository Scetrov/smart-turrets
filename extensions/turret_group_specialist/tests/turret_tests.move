#[test_only]
module turret_group_specialist::group_specialist_tests;

use std::{bcs, unit_test::assert_eq};
use turret_group_specialist::group_specialist;
use world::turret::ReturnTargetPriorityList;

const OWNER_CHARACTER_ID: u32 = 108;
const OWNER_TRIBE: u32 = 100;

const GROUP_SHUTTLE: u64 = 31;
const GROUP_FRIGATE: u64 = 25;
const GROUP_DESTROYER: u64 = 420;

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
    group_id: u64,
    is_aggressor: bool,
    behaviour_change: u8,
): TargetCandidateBcs {
    TargetCandidateBcs {
        item_id,
        type_id: 1,
        group_id,
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
    group_specialist::build_priority_list_for_owner(OWNER_CHARACTER_ID, OWNER_TRIBE, bytes(entries))
}

#[test]
fun configured_frigate_group_receives_hard_coded_bonus() {
    let result = build(vector[candidate(101, GROUP_FRIGATE, true, BEHAVIOUR_STARTED_ATTACK)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 27000);
}

#[test]
fun configured_destroyer_group_receives_secondary_bonus() {
    let result = build(vector[candidate(101, GROUP_DESTROYER, false, BEHAVIOUR_ENTERED)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 9000);
}

#[test]
fun unconfigured_group_gets_no_specialization_bonus() {
    let result = build(vector[candidate(101, GROUP_SHUTTLE, true, BEHAVIOUR_STARTED_ATTACK)]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 15000);
}

#[test]
fun standard_exclusions_still_apply() {
    let result = build(vector[
        TargetCandidateBcs {
            item_id: 101,
            type_id: 1,
            group_id: GROUP_FRIGATE,
            character_id: 900,
            character_tribe: OWNER_TRIBE,
            hp_ratio: 100,
            shield_ratio: 100,
            armor_ratio: 100,
            is_aggressor: false,
            priority_weight: 0,
            behaviour_change: BEHAVIOUR_ENTERED,
        },
        candidate(102, GROUP_DESTROYER, true, BEHAVIOUR_STOPPED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 0);
}
