#[test_only]
module turret_last_stand::last_stand_tests;

use std::{bcs, unit_test::assert_eq};
use turret_last_stand::last_stand;
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
    character_tribe: u32,
    is_aggressor: bool,
    behaviour_change: u8,
    hp: u64,
    shield: u64,
    armor: u64,
): TargetCandidateBcs {
    TargetCandidateBcs {
        item_id,
        type_id: 1,
        group_id: 1,
        character_id: 900,
        character_tribe,
        hp_ratio: hp,
        shield_ratio: shield,
        armor_ratio: armor,
        is_aggressor,
        priority_weight: 0,
        behaviour_change,
    }
}

fun full_hp(
    item_id: u64,
    character_tribe: u32,
    is_aggressor: bool,
    behaviour_change: u8,
): TargetCandidateBcs {
    candidate(item_id, character_tribe, is_aggressor, behaviour_change, 100, 100, 100)
}

fun bytes(entries: vector<TargetCandidateBcs>): vector<u8> { bcs::to_bytes(&entries) }

fun assert_entry(entry: &ReturnTargetPriorityList, expected_item_id: u64, expected_weight: u64) {
    use world::turret;
    assert_eq!(turret::return_target_item_id(entry), expected_item_id);
    assert_eq!(turret::return_priority_weight(entry), expected_weight);
}

fun build(entries: vector<TargetCandidateBcs>): vector<ReturnTargetPriorityList> {
    last_stand::build_priority_list_for_owner(OWNER_CHARACTER_ID, OWNER_TRIBE, bytes(entries))
}

// ---------------------------------------------------------------------------
// Normal mode (< 3 aggressors)
// NORMAL: STARTED_ATTACK=10000, AGGRESSOR=5000, ENTERED=1000
// ---------------------------------------------------------------------------

#[test]
fun normal_mode_applies_standard_exclusions() {
    // 2 aggressors → normal mode
    let result = build(vector[
        full_hp(101, 200, true, BEHAVIOUR_STARTED_ATTACK),  // 10000+5000 = 15000
        full_hp(102, 200, true, BEHAVIOUR_ENTERED),          // 1000+5000  = 6000
        full_hp(103, OWNER_TRIBE, false, BEHAVIOUR_ENTERED), // same tribe, not aggressor → excluded
    ]);
    assert_eq!(vector::length(&result), 2);
    assert_entry(vector::borrow(&result, 0), 101, 15000);
    assert_entry(vector::borrow(&result, 1), 102, 6000);
}

#[test]
fun normal_mode_excludes_owner() {
    let result = build(vector[
        TargetCandidateBcs {
            item_id: 101,
            type_id: 1,
            group_id: 1,
            character_id: OWNER_CHARACTER_ID,
            character_tribe: 200,
            hp_ratio: 100,
            shield_ratio: 100,
            armor_ratio: 100,
            is_aggressor: true,
            priority_weight: 0,
            behaviour_change: BEHAVIOUR_STARTED_ATTACK,
        },
    ]);
    assert_eq!(vector::length(&result), 0);
}

// ---------------------------------------------------------------------------
// Raid mode (≥ 3 aggressors)
// RAID: STARTED_ATTACK=30000, AGGRESSOR=20000, ENTERED=500, DAMAGE_MULT=150
// ---------------------------------------------------------------------------

#[test]
fun raid_mode_triggered_at_three_aggressors() {
    // 3 aggressors → raid mode; same-tribe non-aggressor IS included
    let result = build(vector[
        full_hp(101, 200, true, BEHAVIOUR_STARTED_ATTACK),   // 30000+20000 = 50000
        full_hp(102, 200, true, BEHAVIOUR_ENTERED),           // 500+20000   = 20500
        full_hp(103, 200, true, BEHAVIOUR_ENTERED),           // 500+20000   = 20500
        full_hp(104, OWNER_TRIBE, false, BEHAVIOUR_ENTERED),  // raid: included! 500+0 = 500
    ]);
    assert_eq!(vector::length(&result), 4);
    assert_entry(vector::borrow(&result, 0), 101, 50000);
    assert_entry(vector::borrow(&result, 1), 102, 20500);
    assert_entry(vector::borrow(&result, 2), 103, 20500);
    assert_entry(vector::borrow(&result, 3), 104, 500);
}

#[test]
fun raid_mode_applies_heavy_damage_bonus_for_wounded_targets() {
    // hp=10, shield=20, armor=30: damage = 300 - 60 = 240; bonus = 240 * 150 = 36000
    // total (STARTED_ATTACK aggressor): 30000 + 20000 + 36000 = 86000
    let result = build(vector[
        candidate(101, 200, true, BEHAVIOUR_STARTED_ATTACK, 100, 100, 100), // full hp: 50000
        candidate(102, 200, true, BEHAVIOUR_STARTED_ATTACK, 10, 20, 30),    // wounded: 86000
        // need a 3rd aggressor to trigger raid
        full_hp(103, 200, true, BEHAVIOUR_ENTERED),
    ]);
    assert_eq!(vector::length(&result), 3);
    assert_entry(vector::borrow(&result, 1), 102, 86000);
}

#[test]
fun raid_mode_still_excludes_owner_and_stopped_attack() {
    let result = build(vector[
        // owner — excluded even in raid
        TargetCandidateBcs {
            item_id: 101,
            type_id: 1,
            group_id: 1,
            character_id: OWNER_CHARACTER_ID,
            character_tribe: 200,
            hp_ratio: 100,
            shield_ratio: 100,
            armor_ratio: 100,
            is_aggressor: true,
            priority_weight: 0,
            behaviour_change: BEHAVIOUR_STARTED_ATTACK,
        },
        // stopped attack — excluded even in raid
        full_hp(102, 200, true, BEHAVIOUR_STOPPED_ATTACK),
        // 3 aggressors needed to trigger raid
        full_hp(103, 200, true, BEHAVIOUR_STARTED_ATTACK),
        full_hp(104, 200, true, BEHAVIOUR_STARTED_ATTACK),
        full_hp(105, 200, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    // Only 103, 104, 105 are included (101 = owner, 102 = stopped)
    assert_eq!(vector::length(&result), 3);
}

#[test]
fun two_aggressors_stays_in_normal_mode() {
    // 2 aggressors — should use NORMAL weights, not RAID
    // same-tribe non-aggressor should be excluded in normal mode
    let result = build(vector[
        full_hp(101, 200, true, BEHAVIOUR_STARTED_ATTACK), // NORMAL: 10000+5000=15000
        full_hp(102, 200, true, BEHAVIOUR_ENTERED),         // NORMAL: 1000+5000=6000
        full_hp(103, OWNER_TRIBE, false, BEHAVIOUR_ENTERED),// NORMAL: excluded
    ]);
    assert_eq!(vector::length(&result), 2);
    assert_entry(vector::borrow(&result, 0), 101, 15000);
    assert_entry(vector::borrow(&result, 1), 102, 6000);
}
