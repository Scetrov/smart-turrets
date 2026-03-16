#[test_only]
module turret_threat_ledger::threat_ledger_tests;

use std::{bcs, unit_test::assert_eq};
use sui::{table::{Self, Table}, tx_context};
use turret_threat_ledger::threat_ledger;
use world::turret::ReturnTargetPriorityList;

const OWNER_CHARACTER_ID: u32 = 108;
const OWNER_TRIBE: u32 = 100;
const TRIBE_A: u32 = 200;
const TRIBE_B: u32 = 300;

const BEHAVIOUR_ENTERED: u8 = 1;
const BEHAVIOUR_STARTED_ATTACK: u8 = 2;
const BEHAVIOUR_STOPPED_ATTACK: u8 = 3;

// THREAT_INCREMENT=1000, THREAT_DECREMENT=500, DEFAULT_MAX_THREAT=20000
// THREAT_WEIGHT_DIVISOR=2
// STARTED_ATTACK=10000, AGGRESSOR=4000, ENTERED=1000

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

fun build(
    threats: &mut Table<u32, u64>,
    entries: vector<TargetCandidateBcs>,
): vector<ReturnTargetPriorityList> {
    threat_ledger::build_priority_list_for_owner(
        OWNER_CHARACTER_ID,
        OWNER_TRIBE,
        threats,
        20_000, // max_threat
        bytes(entries),
    )
}

#[test]
fun fresh_ledger_scores_without_threat_bonus() {
    let ctx = &mut tx_context::dummy();
    let mut threats = table::new<u32, u64>(ctx);
    // STARTED_ATTACK aggressor tribe_a, threat goes 0→1000 this call
    // score: 0 + 10000 + 4000 + 1000/2 = 14500
    let result = build(&mut threats, vector[
        candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 14500);
    table::drop(threats);
}

#[test]
fun threat_accumulates_over_repeated_calls() {
    let ctx = &mut tx_context::dummy();
    let mut threats = table::new<u32, u64>(ctx);
    // Call 1: threat 0→1000; score = 10000+4000+500 = 14500
    build(&mut threats, vector[candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK)]);
    // Call 2: threat 1000→2000; score = 10000+4000+1000 = 15000
    let result = build(&mut threats, vector[
        candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 15000);
    table::drop(threats);
}

#[test]
fun stopped_attack_decrements_tribe_threat() {
    let ctx = &mut tx_context::dummy();
    let mut threats = table::new<u32, u64>(ctx);
    // First call: tribe_a threat → 1000
    build(&mut threats, vector[candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK)]);
    // Second call: STOPPED_ATTACK → tribe_a threat: 1000 - 500 = 500
    // STOPPED_ATTACK is excluded from return list
    let stopped_result = build(&mut threats, vector[
        candidate(101, TRIBE_A, false, BEHAVIOUR_STOPPED_ATTACK),
    ]);
    assert_eq!(vector::length(&stopped_result), 0);
    // Third call: aggressor again — threat 500→1500, score = 10000+4000+1500/2 = 14750
    let result = build(&mut threats, vector[
        candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 14750);
    table::drop(threats);
}

#[test]
fun threat_is_capped_at_max_threat() {
    let ctx = &mut tx_context::dummy();
    let mut threats = table::new<u32, u64>(ctx);
    // Saturate tribe_a's threat (max=20000, increment=1000 → 20 calls)
    let mut i = 0u64;
    while (i < 25) { // call 25 times to ensure cap is hit
        build(&mut threats, vector[candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK)]);
        i = i + 1;
    };
    // Threat is capped: bonus = 20000/2 = 10000
    // score = 10000 (STARTED) + 4000 (AGGRESSOR) + 10000 (threat) = 24000
    let result = build(&mut threats, vector[
        candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK),
    ]);
    assert_eq!(vector::length(&result), 1);
    assert_entry(vector::borrow(&result, 0), 101, 24000);
    table::drop(threats);
}

#[test]
fun different_tribes_tracked_independently() {
    let ctx = &mut tx_context::dummy();
    let mut threats = table::new<u32, u64>(ctx);
    // tribe_a aggresses twice, tribe_b only once
    build(&mut threats, vector[candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK)]);
    build(&mut threats, vector[candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK)]);
    // tribe_b: one call — threat 0→1000
    // Final call: both tribes
    // tribe_a threat after 3rd call = 3000: bonus = 3000/2 = 1500 → 10000+4000+1500 = 15500
    // tribe_b threat after 1st call = 1000: bonus = 1000/2 = 500  → 1000+4000+500  = 5500
    let result = build(&mut threats, vector[
        candidate(101, TRIBE_A, true, BEHAVIOUR_STARTED_ATTACK),
        candidate(102, TRIBE_B, true, BEHAVIOUR_ENTERED),
    ]);
    assert_eq!(vector::length(&result), 2);
    assert_entry(vector::borrow(&result, 0), 101, 15500);
    assert_entry(vector::borrow(&result, 1), 102, 5500);
    table::drop(threats);
}

#[test]
fun npc_tribe_zero_does_not_accumulate_threat() {
    let ctx = &mut tx_context::dummy();
    let mut threats = table::new<u32, u64>(ctx);
    // tribe_id = 0 → NPC, must not be written to the table
    build(&mut threats, vector[candidate(101, 0, true, BEHAVIOUR_STARTED_ATTACK)]);
    // Table should be empty — no entry for tribe 0
    assert_eq!(table::length(&threats), 0);
    table::drop(threats);
}

#[test]
fun standard_exclusions_still_apply() {
    let ctx = &mut tx_context::dummy();
    let mut threats = table::new<u32, u64>(ctx);
    let result = build(&mut threats, vector[
        // same-tribe non-aggressor excluded
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
    ]);
    assert_eq!(vector::length(&result), 0);
    table::drop(threats);
}
