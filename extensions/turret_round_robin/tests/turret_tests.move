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

// STARTED_ATTACK=10000, AGGRESSOR=4000, ENTERED=1000, HISTORY_PENALTY=15000

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

fun build(
    history: &mut vector<u64>,
    max_size: u64,
    entries: vector<TargetCandidateBcs>,
): vector<ReturnTargetPriorityList> {
    round_robin::build_priority_list_for_owner(
        OWNER_CHARACTER_ID,
        OWNER_TRIBE,
        history,
        max_size,
        bytes(entries),
    )
}

#[test]
fun empty_history_scores_normally() {
    let mut history = vector[];
    // 101 STARTED_ATTACK aggressor: 10000 + 4000 = 14000 (no penalty)
    let result = build(&mut history, 3, vector[
        candidate(101, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 14000);
    // winner recorded in history
    assert_eq!(history, vector[101]);
}

#[test]
fun recent_target_receives_history_penalty() {
    let mut history = vector[101u64];
    // 101 ENTERED aggressor: base = 1000+4000 = 5000; penalty: 5000 < 15000 → floor at 1
    let result = build(&mut history, 3, vector[
        candidate(101, true, BEHAVIOUR_ENTERED),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 1);
    // still in history (moved to end)
    assert_eq!(history, vector[101]);
}

#[test]
fun penalty_floors_at_1_not_excluded() {
    let mut history = vector[101u64];
    // base weight 5000 < penalty 15000 → floors at 1 (not excluded)
    let result = build(&mut history, 3, vector[
        candidate(101, true, BEHAVIOUR_ENTERED),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 1);
}

#[test]
fun fresh_target_outweighs_penalised_history_target() {
    let mut history = vector[101u64];
    // 101: base 5000, penalty → 1
    // 102: base 14000, no penalty
    let result = build(&mut history, 3, vector[
        candidate(101, true, BEHAVIOUR_ENTERED),
        candidate(102, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 2);
    assert_entry(vector::borrow(&result, 0), 101, 1);
    assert_entry(vector::borrow(&result, 1), 102, 14000);
    // winner was 102; history = [101, 102]
    assert_eq!(history, vector[101, 102]);
}

#[test]
fun history_ring_buffer_evicts_oldest() {
    // history full at max_size=2: [101, 102]
    let mut history = vector[101u64, 102u64];
    // new winner 103 → evict oldest (101): history = [102, 103]
    let result = build(&mut history, 2, vector[
        candidate(103, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 103, 14000);
    assert_eq!(history, vector[102, 103]);
}

#[test]
fun repeated_winner_stays_in_history_without_duplication() {
    let mut history = vector[101u64, 102u64];
    // 101 is in history but wins again (only candidate, penalty applied: 14000-15000 = 1)
    // It is moved to end, not duplicated
    build(&mut history, 3, vector[
        candidate(101, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    // history should still have exactly [102, 101] (101 moved to end)
    assert_eq!(history, vector[102, 101]);
}

#[test]
fun standard_exclusions_still_apply() {
    let mut history = vector[];
    let result = build(&mut history, 3, vector[
        // same tribe non-aggressor → excluded
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
        // stopped attack → excluded
        candidate(102, true, BEHAVIOUR_STOPPED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 0);
    // no winner → history unchanged
    assert_eq!(vector::length(&history), 0);
}
