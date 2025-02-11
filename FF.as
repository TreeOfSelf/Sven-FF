CScheduledFunction@ g_npcKillInterval;
CScheduledFunction@ g_trackEntitiesInterval;

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

const array<string> PROJECTILE_ENTS =
{
    "rpg_rocket",
    "sporegrenade"
};

//Init
void PluginInit() {
	g_Module.ScriptInfo.SetAuthor("Sebastian");
	g_Module.ScriptInfo.SetContactInfo("https://github.com/TreeOfSelf/Sven-FF");

	g_Hooks.RegisterHook(Hooks::Player::PlayerTakeDamage, @PlayerTakeDamage);
	g_Hooks.RegisterHook(Hooks::Monster::MonsterTakeDamage, @MonsterTakeDamage);
	g_Hooks.RegisterHook(Hooks::Weapon::WeaponPrimaryAttack, @WeaponPrimaryAttack);
	g_Hooks.RegisterHook( Hooks::Weapon::WeaponSecondaryAttack, @WeaponSecondaryAttack );

	@cvar_enabled = CCVar("enabled", 1, "Enable/Disable friendly fire plugin", ConCommandFlag::AdminOnly);

    @cvar_player = CCVar("player", 1.0, "Scale of player to friendly player damage", ConCommandFlag::AdminOnly);
    @cvar_npc = CCVar("npc", 1.0, "Scale of player to friendly npc damage", ConCommandFlag::AdminOnly);
    @cvar_npcToPlayer = CCVar("npcToPlayer", 1.0, "Scale of friendly npc to player damage", ConCommandFlag::AdminOnly);
    @cvar_explosive = CCVar("explosive", 1.0 , "Scale of explosive damage", ConCommandFlag::AdminOnly);
	
	resetGlobals();
}

// Hooks
HookReturnCode WeaponPrimaryAttack( CBasePlayer@ pPlayer, CBasePlayerWeapon@ pWeapon )
{
    if( cvar_enabled.GetInt() != 1 )
        return HOOK_CONTINUE;

    CBaseEntity@ pEntity = null;
    while( (@pEntity = g_EntityFuncs.FindEntityByClassname(pEntity, "*")) !is null )
    {
        if( PROJECTILE_ENTS.find(pEntity.GetClassname()) == -1 )
            continue;

        trackedEntities.insertLast(pEntity.entindex());
        trackedEntitiesPosition.insertLast(pEntity.GetOrigin());
        trackedEntitiesOwner.insertLast(pPlayer.entindex());
        trackedEntitiesType.insertLast("RPG");
    }

    return HOOK_CONTINUE;
}

HookReturnCode WeaponSecondaryAttack( CBasePlayer@ pPlayer, CBasePlayerWeapon@ pWeapon )
{
    WeaponPrimaryAttack(pPlayer, pWeapon);
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


// Main Functions
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
		bool add = true;
		for (uint i = 0; i < trackedEntities.length(); ++i) {
			if (trackedEntities[i] == foundEntity.entindex()) {
				add = false;
				break;
			}
		}
		
		if (add) {
			EHandle playerHandle = g_EntityFuncs.Instance(foundEntity.pev.owner);
			CBaseEntity@ ownerEntity = playerHandle.GetEntity();
			if (ownerEntity !is null && ownerEntity.IsPlayer()){
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

    AddClassToTrackEntities("grenade", "grenade");
    AddClassToTrackEntities("monster_satchel", "satchel");
    AddClassToTrackEntities("monster_tripmine", "tripmine");

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

            CBaseEntity@ pEntity = null;
            while((@pEntity = g_EntityFuncs.FindEntityInSphere(pEntity, explosionPos, 1000, "*", "classname")) !is null) {
                //Another Player
                if ((pEntity.IsPlayer() && pEntity.entindex() != ownerId) 
                    //Player NPC Ally
                    || (!pEntity.IsPlayer() && pEntity.IsPlayerAlly())) {

                    float distance = pEntity.GetOrigin().opSub(explosionPos).Length();
                    distance = distance * distance;
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
                    
                    TraceResult tr;
                    float dmg = 1000000 / distance;
                    g_Utility.TraceLine(explosionPos, pEntity.GetOrigin(), dont_ignore_monsters, pEntity.edict(), tr);
					dmg = dmg * tr.flFraction * cvar_explosive.GetFloat();

					if (!pEntity.IsPlayer()) {
						dmg = dmg * cvar_npc.GetFloat();
					} else {
						dmg = dmg * cvar_player.GetFloat();
					}

                    pEntity.TakeDamage(friendlyNPCEntity.pev, friendlyNPCEntity.pev, dmg, DMG_BLAST);
                }
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
