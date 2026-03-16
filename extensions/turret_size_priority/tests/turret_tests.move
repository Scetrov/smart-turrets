#[test_only]
module turret_size_priority::size_priority_tests;

use std::{bcs, unit_test::assert_eq};
use turret_size_priority::size_priority;
use world::turret::ReturnTargetPriorityList;

const OWNER_CHARACTER_ID: u32 = 108;
const OWNER_TRIBE: u32 = 100;

// group_ids from extension example
const GROUP_SHUTTLE: u64 = 31;
const GROUP_CORVETTE: u64 = 237;
const GROUP_FRIGATE: u64 = 25;
const GROUP_DESTROYER: u64 = 420;
const GROUP_CRUISER: u64 = 26;
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
    character_tribe: u32,
    is_aggressor: bool,
    behaviour_change: u8,
): TargetCandidateBcs {
    TargetCandidateBcs {
        item_id,
        type_id: 1,
        group_id,
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
    size_priority::build_priority_list_for_owner(OWNER_CHARACTER_ID, OWNER_TRIBE, bytes(entries))
}

// TIER_WEIGHT=3000, STARTED=10000, AGGRESSOR=4000, ENTERED=1000

#[test]
fun battlecruiser_outweighs_frigate_when_both_just_enter() {
    // battlecruiser tier 6: 1000 (ENTERED) + 18000 = 19000
    // frigate tier 3:       1000 (ENTERED) + 9000  = 10000
    let result = build(vector[
        candidate(101, GROUP_BATTLECRUISER, 200, false, BEHAVIOUR_ENTERED),
        candidate(102, GROUP_FRIGATE, 200, false, BEHAVIOUR_ENTERED),
    ]);
    assert_eq!(vector::length(&result), 2);
    assert_entry(vector::borrow(&result, 0), 101, 19000);
    assert_entry(vector::borrow(&result, 1), 102, 10000);
}

#[test]
fun attacking_frigate_beats_passive_battlecruiser() {
    // frigate STARTED_ATTACK + AGGRESSOR: 10000 + 4000 + 9000 = 23000
    // battlecruiser just ENTERED:         1000 + 18000         = 19000
    let result = build(vector[
        candidate(101, GROUP_BATTLECRUISER, 200, false, BEHAVIOUR_ENTERED),
        candidate(102, GROUP_FRIGATE, 200, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 2);
    assert_entry(vector::borrow(&result, 0), 101, 19000);
    assert_entry(vector::borrow(&result, 1), 102, 23000);
}

#[test]
fun all_tiers_produce_correct_base_weights_when_entering() {
    // Only ENTERED bonus (1000) + tier * 3000
    let result = build(vector[
        candidate(1, GROUP_SHUTTLE, 200, false, BEHAVIOUR_ENTERED),      // tier 1: 4000
        candidate(2, GROUP_CORVETTE, 200, false, BEHAVIOUR_ENTERED),     // tier 2: 7000
        candidate(3, GROUP_FRIGATE, 200, false, BEHAVIOUR_ENTERED),      // tier 3: 10000
        candidate(4, GROUP_DESTROYER, 200, false, BEHAVIOUR_ENTERED),    // tier 4: 13000
        candidate(5, GROUP_CRUISER, 200, false, BEHAVIOUR_ENTERED),      // tier 5: 16000
        candidate(6, GROUP_BATTLECRUISER, 200, false, BEHAVIOUR_ENTERED),// tier 6: 19000
    ]);
    assert_eq!(vector::length(&result), 6);
    assert_entry(vector::borrow(&result, 0), 1, 4000);
    assert_entry(vector::borrow(&result, 1), 2, 7000);
    assert_entry(vector::borrow(&result, 2), 3, 10000);
    assert_entry(vector::borrow(&result, 3), 4, 13000);
    assert_entry(vector::borrow(&result, 4), 5, 16000);
    assert_entry(vector::borrow(&result, 5), 6, 19000);
}

#[test]
fun unknown_group_id_defaults_to_tier_1() {
    let result = build(vector[
        candidate(101, 9999, 200, false, BEHAVIOUR_ENTERED), // unknown → tier 1: 4000
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 4000);
}

#[test]
fun standard_exclusions_apply_regardless_of_tier() {
    let result = build(vector[
        // Owner — excluded
        TargetCandidateBcs {
            item_id: 101,
            type_id: 1,
            group_id: GROUP_BATTLECRUISER,
            character_id: OWNER_CHARACTER_ID,
            character_tribe: 200,
            hp_ratio: 100,
            shield_ratio: 100,
            armor_ratio: 100,
            is_aggressor: true,
            priority_weight: 0,
            behaviour_change: BEHAVIOUR_STARTED_ATTACK,
        },
        // Same tribe, not aggressor — excluded
        candidate(102, GROUP_BATTLECRUISER, OWNER_TRIBE, false, BEHAVIOUR_ENTERED),
        // Stopped attack — excluded
        candidate(103, GROUP_BATTLECRUISER, 200, true, BEHAVIOUR_STOPPED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 0);
}

#[test]
fun same_tribe_aggressor_is_included_with_tier_bonus() {
    // same tribe but is aggressor: 10000 (STARTED) + 4000 (AGGRESSOR) + 9000 (FRIGATE tier 3) = 23000
    let result = build(vector[
        candidate(101, GROUP_FRIGATE, OWNER_TRIBE, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 23000);
}
