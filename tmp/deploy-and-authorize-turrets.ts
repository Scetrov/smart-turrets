/**
 * Batch script: deploy turrets 6001-6009 and authorize each extension on its turret.
 *
 * Run from the world-contracts directory:
 *   cd /home/scetrov/source/smart-turrets/world-contracts
 *   tsx ../tmp/deploy-and-authorize-turrets.ts
 */
import "dotenv/config";
import { Transaction } from "@mysten/sui/transactions";
import { bcs } from "@mysten/sui/bcs";
import { HydratedWorldConfig, MODULES } from "./ts-scripts/utils/config";
import {
    initializeContext,
    handleError,
    extractEvent,
    hexToBytes,
    requireEnv,
    getEnvConfig,
    hydrateWorldConfig,
    shareHydratedConfig,
} from "./ts-scripts/utils/helper";
import {
    LOCATION_HASH,
    GAME_CHARACTER_ID,
    NWN_ITEM_ID,
} from "./ts-scripts/utils/constants";
import { deriveObjectId } from "./ts-scripts/utils/derive-object-id";
import { getOwnerCap } from "./ts-scripts/turret/helper";

// ---------------------------------------------------------------------------
// Extension manifest
// Each entry defines the efctl-deployed package, Move module name, and turret
// item ID that will host that extension.
// ---------------------------------------------------------------------------
const EXTENSIONS = [
    {
        name: "turret_aggressor_first",
        turretItemId: 6001n,
        builderPackageId: "0x508add124ecc100440d85e21cca5cdf0af3d898acac3b57f48d2249371728dcc",
        moduleName: "aggressor_first",
    },
    {
        name: "turret_low_hp_finisher",
        turretItemId: 6002n,
        builderPackageId: "0x982b0f693d54e3ad380b9c5dd36e73ebe7cd39c6e4a4b688ace9ad23145bc1f1",
        moduleName: "low_hp_finisher",
    },
    {
        name: "turret_player_screen",
        turretItemId: 6003n,
        builderPackageId: "0x3a3a32a52e74ca6066134a515cca2b6935c385f44bb7660eddb8a9b0bdcf3c2f",
        moduleName: "player_screen",
    },
    {
        name: "turret_type_blocklist",
        turretItemId: 6004n,
        builderPackageId: "0xc648c5977980e09e586645c5e48f0a3aee38c53bef3ff610891dddc36bb0fbcb",
        moduleName: "type_blocklist",
    },
    {
        name: "turret_size_priority",
        turretItemId: 6005n,
        builderPackageId: "0x6039c3f1e65a9466335345b2b7437946d0b07a8b1fe49906c7d0d7f07137e7c1",
        moduleName: "size_priority",
    },
    {
        name: "turret_last_stand",
        turretItemId: 6006n,
        builderPackageId: "0x146810c8988451c44152ae45a5d5d24eac90c0008b800f9bc630f9d37b514f68",
        moduleName: "last_stand",
    },
    {
        name: "turret_group_specialist",
        turretItemId: 6007n,
        builderPackageId: "0x166400bb00f38d642fbbefc484863c2b809c64267e146c3c5ab7dcb3c88be5b8",
        moduleName: "group_specialist",
    },
    {
        name: "turret_round_robin",
        turretItemId: 6008n,
        builderPackageId: "0x6185066d5ae40e802ee4ab96b47bed2899eefafecab8cd85d4da8e2044a26264",
        moduleName: "round_robin",
    },
    {
        name: "turret_threat_ledger",
        turretItemId: 6009n,
        builderPackageId: "0x04f0914732b2bff8334bba6aca667a79dc56eb56540e0fd1d0c919d8e91c6513",
        moduleName: "threat_ledger",
    },
] as const;

// All turrets in the game use the same type ID as defined in test-resources.json
const TURRET_TYPE_ID = 5555n;

// ---------------------------------------------------------------------------
// Anchor + share a new turret (mirrors ts-scripts/turret/anchor.ts exactly)
// Uses the admin context so it runs under ADMIN_PRIVATE_KEY.
// ---------------------------------------------------------------------------
async function anchorTurret(
    characterObjectId: string,
    networkNodeObjectId: string,
    typeId: bigint,
    itemId: bigint,
    adminCtx: ReturnType<typeof initializeContext>
): Promise<string> {
    const { client, keypair } = adminCtx;
    const config = adminCtx.config as HydratedWorldConfig;
    const tx = new Transaction();

    const [turret] = tx.moveCall({
        target: `${config.packageId}::${MODULES.TURRET}::anchor`,
        arguments: [
            tx.object(config.objectRegistry),
            tx.object(networkNodeObjectId),
            tx.object(characterObjectId),
            tx.object(config.adminAcl),
            tx.pure.u64(itemId),
            tx.pure.u64(typeId),
            tx.pure(bcs.vector(bcs.u8()).serialize(hexToBytes(LOCATION_HASH))),
        ],
    });

    tx.moveCall({
        target: `${config.packageId}::${MODULES.TURRET}::share_turret`,
        arguments: [turret, tx.object(config.adminAcl)],
    });

    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEvents: true },
    });

    const event = extractEvent<{ turret_id: string; owner_cap_id: string }>(
        result,
        "::turret::TurretCreatedEvent"
    );
    if (!event) throw new Error("TurretCreatedEvent not found in result");
    console.log(`  Turret ID:   ${event.turret_id}`);
    console.log(`  OwnerCap ID: ${event.owner_cap_id}`);
    return event.turret_id;
}

// ---------------------------------------------------------------------------
// Bring turret online (mirrors ts-scripts/turret/online.ts exactly)
// Uses the player context so it runs under PLAYER_A_PRIVATE_KEY.
// ---------------------------------------------------------------------------
async function onlineTurret(
    turretId: string,
    networkNodeId: string,
    playerCtx: ReturnType<typeof initializeContext>
): Promise<void> {
    const { client, keypair } = playerCtx;
    const config = playerCtx.config as HydratedWorldConfig;

    const ownerCapId = await getOwnerCap(turretId, client, config, playerCtx.address);
    if (!ownerCapId) throw new Error(`OwnerCap not found for turret ${turretId}`);

    const characterId = deriveObjectId(config.objectRegistry, GAME_CHARACTER_ID, config.packageId);
    const tx = new Transaction();

    const [ownerCap, receipt] = tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::borrow_owner_cap`,
        typeArguments: [`${config.packageId}::${MODULES.TURRET}::Turret`],
        arguments: [tx.object(characterId), tx.object(ownerCapId)],
    });

    tx.moveCall({
        target: `${config.packageId}::${MODULES.TURRET}::online`,
        arguments: [
            tx.object(turretId),
            tx.object(networkNodeId),
            tx.object(config.energyConfig),
            ownerCap,
        ],
    });

    tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::return_owner_cap`,
        typeArguments: [`${config.packageId}::${MODULES.TURRET}::Turret`],
        arguments: [tx.object(characterId), ownerCap, receipt],
    });

    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEffects: true },
    });
    console.log(`  Turret online. Digest: ${result.digest}`);
}

// ---------------------------------------------------------------------------
// Authorize an extension (mirrors ts-scripts/builder_extension/authorize-turret.ts)
// Uses the player context so it runs under PLAYER_A_PRIVATE_KEY.
// ---------------------------------------------------------------------------
async function authorizeExtension(
    turretId: string,
    authType: string,
    playerCtx: ReturnType<typeof initializeContext>
): Promise<void> {
    const { client, keypair } = playerCtx;
    const config = playerCtx.config as HydratedWorldConfig;

    const ownerCapId = await getOwnerCap(turretId, client, config, playerCtx.address);
    if (!ownerCapId) throw new Error(`OwnerCap not found for turret ${turretId}`);

    const characterId = deriveObjectId(config.objectRegistry, GAME_CHARACTER_ID, config.packageId);
    const tx = new Transaction();

    const [ownerCap, receipt] = tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::borrow_owner_cap`,
        typeArguments: [`${config.packageId}::${MODULES.TURRET}::Turret`],
        arguments: [tx.object(characterId), tx.object(ownerCapId)],
    });

    tx.moveCall({
        target: `${config.packageId}::${MODULES.TURRET}::authorize_extension`,
        typeArguments: [authType],
        arguments: [tx.object(turretId), ownerCap],
    });

    tx.moveCall({
        target: `${config.packageId}::${MODULES.CHARACTER}::return_owner_cap`,
        typeArguments: [`${config.packageId}::${MODULES.TURRET}::Turret`],
        arguments: [tx.object(characterId), ownerCap, receipt],
    });

    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEffects: true, showObjectChanges: true, showEvents: true },
    });
    console.log(`  Extension authorized. Auth type: ${authType}`);
    console.log(`  Transaction digest: ${result.digest}`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
    const env = getEnvConfig();

    // Admin context for anchoring turrets
    const adminCtx = initializeContext(env.network, env.adminExportedKey);
    await hydrateWorldConfig(adminCtx);

    // Player context for online + authorize
    const playerCtx = initializeContext(env.network, requireEnv("PLAYER_A_PRIVATE_KEY"));
    shareHydratedConfig(adminCtx, playerCtx);

    const config = adminCtx.config as HydratedWorldConfig;
    const networkNodeId = deriveObjectId(config.objectRegistry, NWN_ITEM_ID, config.packageId);
    const characterId = deriveObjectId(config.objectRegistry, GAME_CHARACTER_ID, config.packageId);

    console.log(`World Package:  ${config.packageId}`);
    console.log(`Object Registry: ${config.objectRegistry}`);
    console.log(`Network Node:    ${networkNodeId}`);
    console.log(`Character:       ${characterId}`);
    console.log();

    for (const ext of EXTENSIONS) {
        console.log(`=== ${ext.name} (item ${ext.turretItemId}) ===`);

        // --- Step 1: Anchor turret if it doesn't exist yet ---
        const turretId = deriveObjectId(config.objectRegistry, ext.turretItemId, config.packageId);
        console.log(`  Derived turret ID: ${turretId}`);

        try {
            const obj = await adminCtx.client.getObject({ id: turretId, options: { showType: true } });
            if (obj.error) {
                throw new Error(`Not found: ${JSON.stringify(obj.error)}`);
            }
            console.log(`  Turret already exists on-chain.`);
        } catch {
            console.log(`  Turret not found – anchoring now...`);
            try {
                await anchorTurret(characterId, networkNodeId, TURRET_TYPE_ID, ext.turretItemId, adminCtx);
            } catch (e) {
                console.error(`  ERROR anchoring: ${(e as Error).message}`);
                console.log(`  Skipping remaining steps for this extension.`);
                console.log();
                continue;
            }
        }

        // --- Step 2: Bring turret online ---
        try {
            await onlineTurret(turretId, networkNodeId, playerCtx);
        } catch (e) {
            console.log(`  Online step skipped (${(e as Error).message})`);
        }

        // --- Step 3: Authorize the extension ---
        const authType = `${ext.builderPackageId}::${ext.moduleName}::TurretAuth`;
        console.log(`  Authorizing: ${authType}`);
        try {
            await authorizeExtension(turretId, authType, playerCtx);
        } catch (e) {
            console.error(`  ERROR authorizing: ${(e as Error).message}`);
        }

        console.log();
    }

    console.log("Batch complete.");
}

main().catch(handleError);
