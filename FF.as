CScheduledFunction@ g_npcKillInterval;
CScheduledFunction@ g_trackEntitiesInterval;
CScheduledFunction@ g_MoveNPCInterval;

EHandle friendlyNPCHandle;

array<int> trackedEntities;
array<Vector> trackedEntitiesPosition;
array<int> trackedEntitiesOwner;
array<string> trackedEntitiesType;

CCVar@ cvar_enabled;
CCVar@ cvar_player;
CCVar@ cvar_npc;
CCVar@ cvar_npcToPlayer;
CCVar@ cvar_explosive;

// Damage values for various explosives (from Half-Life Opposing Force source code)
// These values match the Opposing Force multiplayer damage values exactly
dictionary ExplosiveDamges =
{
    { "bolt", 50 },  // Crossbow bolt (sk_plr_xbow_bolt_monster)
	{ "displacer_portal", 300}  // Displacer portal explosion
};


//Init
void PluginInit() {

	float skillValue = g_EngineFuncs.CVarGetFloat("skill");

	// Exact values from Opposing Force multiplayer source (multiplay_gamerules.cpp)
	ExplosiveDamges['snark'] = 10;  // plrDmgHornet (snark explosion uses hornet damage)
	ExplosiveDamges['sporegrenade'] = 50;  // plrDmgSpore
	ExplosiveDamges['rpg_rocket'] = 120;  // plrDmgRPG
	ExplosiveDamges['grenade'] = 100;  // plrDmgHandGrenade
	ExplosiveDamges['monster_tripmine'] = 150;  // plrDmgTripmine
	ExplosiveDamges['monster_satchel'] = 120;  // plrDmgSatchel

	g_Module.ScriptInfo.SetAuthor("Sebastian");
	g_Module.ScriptInfo.SetContactInfo("https://github.com/TreeOfSelf/Sven-FF");

	g_Hooks.RegisterHook(Hooks::Player::PlayerTakeDamage, @PlayerTakeDamage);
	g_Hooks.RegisterHook(Hooks::Weapon::WeaponPrimaryAttack, @WeaponPrimaryAttack);
	g_Hooks.RegisterHook(Hooks::Weapon::WeaponSecondaryAttack, @WeaponSecondaryAttack);
	g_Hooks.RegisterHook(Hooks::PickupObject::Collected, @CollectSatchel);

	g_Hooks.RegisterHook(Hooks::Monster::MonsterTakeDamage, @MonsterTakeDamage);

	@cvar_enabled = CCVar("enabled", 1, "Enable/Disable friendly fire plugin", ConCommandFlag::AdminOnly);

    @cvar_player = CCVar("player", 1.0, "Scale of player to friendly player damage", ConCommandFlag::AdminOnly);
    @cvar_npc = CCVar("npc", 1.0, "Scale of player to friendly npc damage", ConCommandFlag::AdminOnly);
    @cvar_npcToPlayer = CCVar("npcToPlayer", 1.0, "Scale of friendly npc to player damage", ConCommandFlag::AdminOnly);
    @cvar_explosive = CCVar("explosive", 1.0 , "Scale of explosive damage", ConCommandFlag::AdminOnly);
	
	resetGlobals();
}

// Hooks

//Can probably run this on a timer instead 
HookReturnCode WeaponPrimaryAttack( CBasePlayer@ pPlayer, CBasePlayerWeapon@ pWeapon )
{

    if( cvar_enabled.GetInt() != 1 )
        return HOOK_CONTINUE;

    CBaseEntity@ pEntity = null;
    while( (@pEntity = g_EntityFuncs.FindEntityByClassname(pEntity, "*")) !is null )
    {

		CBaseEntity@ owner = g_EntityFuncs.Instance(pEntity.pev.owner);

		if (owner != null && owner.IsPlayer() && owner.entindex() == pPlayer.entindex()) {
			if (trackedEntities.find(pEntity.entindex()) == -1 && pEntity.IsInWorld() && pEntity.GetClassname().Find("weapon_") != 0){

				if (ExplosiveDamges.exists(pEntity.GetClassname())) {

				string className = pEntity.GetClassname();

				if (className == "bolt") {
					if (pWeapon.m_fInZoom) {
						continue;
					}
				}

				trackedEntities.insertLast(pEntity.entindex());
				trackedEntitiesPosition.insertLast(pEntity.GetOrigin());
				trackedEntitiesOwner.insertLast(pPlayer.entindex());
				trackedEntitiesType.insertLast(className);

				} else {
					//g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, pEntity.GetClassname());
				}

			}
		}
    }

    return HOOK_CONTINUE;
}


HookReturnCode WeaponSecondaryAttack( CBasePlayer@ pPlayer, CBasePlayerWeapon@ pWeapon )
{
    WeaponPrimaryAttack(pPlayer, pWeapon);
    return HOOK_CONTINUE;
}

HookReturnCode CollectSatchel( CBaseEntity@ pPickup, CBaseEntity@ pOther )
{
	//if we are not picking up a satchel
	if (pPickup.GetClassname() != "weapon_satchel" || !pOther.IsPlayer()) return HOOK_CONTINUE;

	int index = -1;
	float maxDistance = 100;

	for (int i = int(trackedEntities.length()) - 1; i >= 0; --i) {
		if (i >= int(trackedEntities.length())) continue;
			if (trackedEntitiesOwner[i] == pOther.entindex()) {
			float distance = (trackedEntitiesPosition[i] - pPickup.GetOrigin()).Length();
			if (distance < maxDistance) {
				index = i;
				maxDistance = distance;
			}
		}

	}

	if (index != -1) {
		trackedEntities.removeAt(index);
		trackedEntitiesPosition.removeAt(index);    
		trackedEntitiesOwner.removeAt(index);
		trackedEntitiesType.removeAt(index);
	}
    return HOOK_CONTINUE;
}

HookReturnCode MonsterTakeDamage( DamageInfo@ pDamageInfo ) {

	if (cvar_enabled.GetInt() != 1 || cvar_npc.GetFloat() == 0.0) return HOOK_CONTINUE;

    if (pDamageInfo !is null) {
        CBaseEntity@ attacker = pDamageInfo.pAttacker;
        CBaseEntity@ victim = pDamageInfo.pVictim;

		// If monster is attacked by a player 
        if (attacker !is null && attacker.IsPlayer()) {
			CBasePlayer@ plr = cast<CBasePlayer@>(g_EntityFuncs.Instance(attacker.pev));
			// On the same team
			if ( victim.IsPlayerAlly() ) {
				pDamageInfo.flDamage = pDamageInfo.flDamage * cvar_npc.GetFloat();
			}
            return HOOK_CONTINUE;
        }
    }
    
    return HOOK_CONTINUE;
}

HookReturnCode PlayerTakeDamage( DamageInfo@ pDamageInfo ) {

	if (cvar_enabled.GetInt() != 1) return HOOK_CONTINUE;

	CBasePlayer@ plr = cast<CBasePlayer@>(g_EntityFuncs.Instance(pDamageInfo.pVictim.pev));
	CBaseEntity@ attacker = pDamageInfo.pAttacker;
	CBaseEntity@ inflictor  = pDamageInfo.pInflictor;
	string steamId = g_EngineFuncs.GetPlayerAuthId(plr.edict());
		
	if (attacker.entindex() == plr.entindex() || inflictor.entindex() == plr.entindex()) return HOOK_CONTINUE;

	//Being attacked by another player on the same team
	if(cvar_player.GetFloat() != 0.0 && attacker.IsPlayer() && 
	attacker.Classify() == plr.Classify()){
		CBaseEntity@ friendlyNPCEntity =  getFriendlyNPC(plr.GetOrigin());
		CBaseMonster@ friendlyNPCMonster = cast<CBaseMonster@>(friendlyNPCEntity);
		CBasePlayer@ attackerPlayer = cast<CBasePlayer@>( attacker );

		friendlyNPCMonster.m_FormattedName = "player ("+attackerPlayer.pev.netname+") using "+attackerPlayer.m_hActiveItem.GetEntity().GetClassname();
		plr.TakeDamage(inflictor.pev,friendlyNPCEntity.pev,pDamageInfo.flDamage * cvar_player.GetFloat(),pDamageInfo.bitsDamageType);
		return HOOK_HANDLED;
	
	//Being attacked by a friendly NPC
	} else {
		if(cvar_npcToPlayer.GetFloat() != 0.0 && !attacker.IsPlayer() && attacker.IsPlayerAlly()){
			CBaseEntity@ friendlyNPCEntity =  getFriendlyNPC(plr.GetOrigin());
			CBaseMonster@ friendlyNPCMonster = cast<CBaseMonster@>(friendlyNPCEntity);
			CBaseMonster@ attackerMonster = cast<CBaseMonster@>( attacker );
			friendlyNPCMonster.m_FormattedName = "friendly NPC ("+attackerMonster.m_FormattedName+")";
			plr.TakeDamage(inflictor.pev,friendlyNPCEntity.pev,pDamageInfo.flDamage * cvar_npcToPlayer.GetFloat(),pDamageInfo.bitsDamageType);
			if (!plr.IsAlive()){
				attacker.pev.frags++;
			}
			return HOOK_HANDLED;
		}
	}
	
	return HOOK_CONTINUE;
}


void resetGlobals() {
	if (g_npcKillInterval !is null)  g_Scheduler.RemoveTimer(g_npcKillInterval); 
	@g_npcKillInterval = g_Scheduler.SetInterval("npc_kill", 1);

	if( g_trackEntitiesInterval !is null ) g_Scheduler.RemoveTimer(g_trackEntitiesInterval);
	@g_trackEntitiesInterval = g_Scheduler.SetInterval( "TrackEntities", 0.0, g_Scheduler.REPEAT_INFINITE_TIMES);

	trackedEntities.resize(0);
	trackedEntitiesPosition.resize(0);
	trackedEntitiesOwner.resize(0);	
	trackedEntitiesType.resize(0);	
	
	friendlyNPCHandle = EHandle();
}

void MapInit(){
	g_Game.PrecacheMonster( "monster_gman", true );
	resetGlobals();
}

void AddClassToTrackEntities(string ClassName, string Type){
	CBaseEntity@ foundEntity = null;

	while( ( @foundEntity = g_EntityFuncs.FindEntityByClassname( foundEntity, ClassName ) ) !is null ){
		if (trackedEntities.find(foundEntity.entindex()) == -1) {
			EHandle playerHandle = g_EntityFuncs.Instance(foundEntity.pev.owner);
			CBaseEntity@ ownerEntity = playerHandle.GetEntity();
			// Track explosives from both players AND friendly NPCs
			if (ownerEntity !is null && (ownerEntity.IsPlayer() || ownerEntity.IsPlayerAlly())){

				trackedEntities.insertLast(foundEntity.entindex());
				trackedEntitiesPosition.insertLast(foundEntity.GetOrigin());
				trackedEntitiesOwner.insertLast(ownerEntity.entindex());
				trackedEntitiesType.insertLast(Type);
			}
		}
	}
}


void TrackEntities()
{

	if (cvar_enabled.GetInt() != 1 || cvar_explosive.GetFloat() == 0.0) return;

	//Grenades are tracked seperately as they have a long warmup before throwing after clicking
    AddClassToTrackEntities("grenade", "grenade");
    AddClassToTrackEntities("displacer_portal", "displacer_portal");

    //Work through tracked entities
    for (int i = int(trackedEntities.length()) - 1; i >= 0; --i) {
        // Skip if index is invalid
        if (i >= int(trackedEntities.length())) {
            continue;
        }

        edict_t@ edict = g_EntityFuncs.IndexEnt(trackedEntities[i]);
        if (edict !is null) {
            EHandle entityHandle = g_EntityFuncs.Instance(edict);      
            CBaseEntity@ entity = entityHandle.GetEntity();
            if (i < int(trackedEntitiesPosition.length())) {
                trackedEntitiesPosition[i] = entity.GetOrigin();
            }
        } else {
            Vector explosionPos = trackedEntitiesPosition[i];
            int ownerId = trackedEntitiesOwner[i];
            string entityType = trackedEntitiesType[i];
            
            trackedEntities.removeAt(i);
            trackedEntitiesPosition.removeAt(i);    
            trackedEntitiesOwner.removeAt(i);
            trackedEntitiesType.removeAt(i);

			CBaseEntity@ friendlyNPCEntity = getFriendlyNPC(explosionPos);
			CBaseMonster@ friendlyNPCMonster = cast<CBaseMonster@>(friendlyNPCEntity);
			edict_t@ ownerEdict = g_EntityFuncs.IndexEnt(ownerId);
			if (ownerEdict !is null) {
				EHandle entityOwnerHandle = g_EntityFuncs.Instance(ownerEdict);      
				CBaseEntity@ ownerEntity = entityOwnerHandle.GetEntity();
				CBasePlayer@ plr = cast<CBasePlayer@>(ownerEntity);
				friendlyNPCMonster.m_FormattedName = "player (" + plr.pev.netname + ") using " + entityType;
			} else {
				friendlyNPCMonster.m_FormattedName = "explosion";                    
			}
	
			if (ExplosiveDamges.exists(entityType)) {
				int dmg = int(ExplosiveDamges[entityType]);
				// Spore grenades use DMG_GENERIC (exact Valve implementation from sporegrenade.cpp:283)
				// All other explosives use DMG_BLAST
				int damageType = (entityType == "sporegrenade") ? DMG_GENERIC : DMG_BLAST;
				RadiusDamage (ownerEdict, explosionPos,friendlyNPCEntity.pev, friendlyNPCEntity.pev, dmg , dmg * 2.5, CLASS_NONE, damageType );
			}
        }
    }
}

CBaseEntity@ getFriendlyNPC(Vector pos) {
    if( friendlyNPCHandle.IsValid()) {  
        CBaseEntity@ pEntity = friendlyNPCHandle.GetEntity();
        if( pEntity !is null ) return @pEntity;
    }

    CBaseEntity@ pEntity = g_EntityFuncs.CreateEntity( "monster_gman", {}, true );
	pEntity.pev.solid = SOLID_NOT;
	pEntity.pev.effects |= EF_NODRAW;
	pEntity.pev.takedamage = DAMAGE_NO;
	pEntity.pev.spawnflags = 16;
	pEntity.SetOrigin(pos);
	pEntity.SetPlayerAlly(false);
	pEntity.SetPlayerAllyDirect(false);
	
    if( pEntity !is null ) {
        friendlyNPCHandle = EHandle( pEntity );
        return @pEntity;
    }

	return null;
}

void npc_kill() {

	if (cvar_enabled.GetInt() != 1 || cvar_npc.GetFloat() == 0.0) {
		g_EngineFuncs.ServerCommand( "mp_npckill 2\n");
		g_EngineFuncs.ServerExecute();
		return;
	} 

	g_EngineFuncs.ServerCommand( "mp_npckill 1\n");
	g_EngineFuncs.ServerExecute();
}


void RadiusDamage(edict_t@ ownerEdict, Vector vecSrc, entvars_t@ pevInflictor, entvars_t@ pevAttacker, float flDamage, float flRadius, int iClassIgnore, int bitsDamageType ) {
	
	int classification = -1;
	int ownerIndex = -1;

	if (ownerEdict !is null) {
			EHandle entityOwnerHandle = g_EntityFuncs.Instance(ownerEdict);      
			CBaseEntity@ ownerEntity = entityOwnerHandle.GetEntity();
			classification = ownerEntity.Classify();
			ownerIndex = ownerEntity.entindex();
	}

	CBaseEntity@ pEntity;
	TraceResult	tr;
	float		flAdjustedDamage, falloff;
	Vector		vecSpot;

	if ( flRadius != 0 )
		falloff = flDamage / flRadius;
	else
		falloff = 1.0;


	bool bInWater = (g_EngineFuncs.PointContents( vecSrc ) == CONTENTS_WATER);

	vecSrc.z += 1;// in case grenade is lying on the ground

	// iterate on all entities in the vicinity.
    while( (@pEntity = g_EntityFuncs.FindEntityInSphere(pEntity, vecSrc, flRadius, "player", "classname")) !is null )
	{
	
		if ( !pEntity.IsPlayer() || pEntity.entindex() == ownerIndex || pEntity.Classify() != classification)
		{
			continue;
		}

		// blast's don't tavel into or out of water
		if (bInWater && pEntity.pev.waterlevel == 0)
			continue;
		if (!bInWater && pEntity.pev.waterlevel == 3)
			continue;

		vecSpot = pEntity.BodyTarget( vecSrc );
		
		g_Utility.TraceLine ( vecSrc, vecSpot, dont_ignore_monsters, g_EntityFuncs.Instance(pevInflictor).edict(), tr );

		if ( tr.flFraction == 1.0 || g_EntityFuncs.Instance(tr.pHit).entindex() == pEntity.entindex() )
		{// the explosion can 'see' this entity, so hurt them!
			if (tr.fStartSolid != 0)
			{
				// if we're stuck inside them, fixup the position and distance
				tr.vecEndPos = vecSrc;
				tr.flFraction = 0.0;
			}
			
			// decrease damage for an ent that's farther from the bomb.
			flAdjustedDamage = ( vecSrc - tr.vecEndPos ).Length() * falloff;
			flAdjustedDamage = flDamage - flAdjustedDamage;
		
			if ( flAdjustedDamage < 0 )
				flAdjustedDamage = 0;
			
			
			// ALERT( at_console, "hit %s\n", STRING( pEntity->pev->classname ) );
			if (tr.flFraction != 1.0)
			{
				g_WeaponFuncs.ClearMultiDamage( );
				pEntity.TraceAttack( pevInflictor, flAdjustedDamage, (tr.vecEndPos.opSub(vecSrc)).Normalize( ), tr, bitsDamageType );
				g_WeaponFuncs.ApplyMultiDamage( pevInflictor, pevAttacker );
			}
			else
			{
				pEntity.TakeDamage ( pevInflictor, pevAttacker, flAdjustedDamage, bitsDamageType );
			}			
		}
		
	}
}
