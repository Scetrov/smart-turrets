#[test_only]
module turret_group_specialist::group_specialist_tests;

use std::{bcs, unit_test::assert_eq};
use turret_group_specialist::group_specialist::{Self, GroupBonus};
use world::turret::ReturnTargetPriorityList;

const OWNER_CHARACTER_ID: u32 = 108;
const OWNER_TRIBE: u32 = 100;

const GROUP_FRIGATE: u64 = 25;
const GROUP_SHUTTLE: u64 = 31;
const GROUP_BATTLECRUISER: u64 = 419;

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

fun build(
    bonuses: vector<GroupBonus>,
    entries: vector<TargetCandidateBcs>,
): vector<ReturnTargetPriorityList> {
    group_specialist::build_priority_list_for_owner(
        OWNER_CHARACTER_ID,
        OWNER_TRIBE,
        &bonuses,
        bytes(entries),
    )
}

// STARTED_ATTACK=10000, AGGRESSOR=5000, ENTERED=1000

#[test]
fun empty_bonuses_applies_no_group_bonus() {
    // frigate STARTED_ATTACK aggressor: 10000 + 5000 + 0 = 15000
    let result = build(
        vector[],
        vector[candidate(101, GROUP_FRIGATE, true, BEHAVIOUR_STARTED_ATTACK)],
    );
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 15000);
}

#[test]
fun matching_group_id_receives_bonus() {
    // frigate with 8000 bonus, STARTED_ATTACK aggressor: 10000 + 5000 + 8000 = 23000
    let bonuses = vector[group_specialist::new_group_bonus(GROUP_FRIGATE, 8000)];
    let result = build(
        bonuses,
        vector[candidate(101, GROUP_FRIGATE, true, BEHAVIOUR_STARTED_ATTACK)],
    );
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 23000);
}

#[test]
fun non_matching_group_id_gets_no_bonus() {
    // shuttle has no bonus entry; STARTED_ATTACK aggressor: 10000 + 5000 + 0 = 15000
    let bonuses = vector[group_specialist::new_group_bonus(GROUP_FRIGATE, 8000)];
    let result = build(
        bonuses,
        vector[candidate(101, GROUP_SHUTTLE, true, BEHAVIOUR_STARTED_ATTACK)],
    );
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 15000);
}

#[test]
fun specialised_ship_outprioritises_unspecialised_same_behaviour() {
    // frigate bonus 8000: 10000 + 5000 + 8000 = 23000
    // shuttle no bonus:   10000 + 5000 + 0    = 15000
    let bonuses = vector[group_specialist::new_group_bonus(GROUP_FRIGATE, 8000)];
    let result = build(
        bonuses,
        vector[
            candidate(101, GROUP_SHUTTLE, true, BEHAVIOUR_STARTED_ATTACK),
            candidate(102, GROUP_FRIGATE, true, BEHAVIOUR_STARTED_ATTACK),
        ],
    );
    assert_eq!(vector::length(&result), 2);
    assert_entry(vector::borrow(&result, 0), 101, 15000);
    assert_entry(vector::borrow(&result, 1), 102, 23000);
}

#[test]
fun multiple_bonuses_only_matching_applied() {
    // battlecruiser bonus 12000; shuttle bonus 3000; candidate is frigate → gets 0
    let bonuses = vector[
        group_specialist::new_group_bonus(GROUP_BATTLECRUISER, 12000),
        group_specialist::new_group_bonus(GROUP_SHUTTLE, 3000),
    ];
    let result = build(
        bonuses,
        vector[candidate(101, GROUP_FRIGATE, false, BEHAVIOUR_ENTERED)],
    );
    assert_eq!(vector::length(&result), 1);
    // 1000 (ENTERED) + 0 (no group match) = 1000
    assert_entry(vector::borrow(&result, 0), 101, 1000);
}

#[test]
fun standard_exclusions_still_apply() {
    let bonuses = vector[group_specialist::new_group_bonus(GROUP_BATTLECRUISER, 50000)];
    let result = build(
        bonuses,
        vector[
            // same tribe not aggressor — excluded despite huge potential bonus
            TargetCandidateBcs {
                item_id: 101,
                type_id: 1,
                group_id: GROUP_BATTLECRUISER,
                character_id: 900,
                character_tribe: OWNER_TRIBE,
                hp_ratio: 100,
                shield_ratio: 100,
                armor_ratio: 100,
                is_aggressor: false,
                priority_weight: 0,
                behaviour_change: BEHAVIOUR_ENTERED,
            },
            // stopped attack — excluded
            candidate(102, GROUP_BATTLECRUISER, true, BEHAVIOUR_STOPPED_ATTACK),
        ],
    );
    assert_eq!(vector::length(&result), 0);
}
