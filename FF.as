CScheduledFunction @g_npcKillInterval;
CScheduledFunction @g_trackEntitiesInterval;
CScheduledFunction @g_MoveNPCInterval;

EHandle friendlyNPCHandle;

array<int> trackedEntities;
array<Vector> trackedEntitiesPosition;
array<int> trackedEntitiesOwner;
array<string> trackedEntitiesType;

// Track last medkit heal time per player (entindex -> timestamp)
dictionary lastMedkitHealTime;

CCVar @cvar_enabled;
CCVar @cvar_player;
CCVar @cvar_npc;
CCVar @cvar_npcToPlayer;
CCVar @cvar_explosive;
CCVar @cvar_npcExplosive;

// Damage values for various explosives - ALL IN ONE PLACE
dictionary ExplosiveDamges = {
    // Player weapons
    {"bolt", 50},
    {"grenade", 100},                    // Hand grenades (player & NPC)
    {"rpg_rocket", 120},
    {"hvr_rocket", 120},                 // Apache rockets
    {"monster_satchel", 120},
    {"monster_tripmine", 150},
    {"snark", 10},
    {"sporegrenade", 50},
    {"displacer_portal", 300},
    {"shock_beam", int(g_EngineFuncs.CVarGetFloat("sk_plr_shockrifle"))},
    
    // NPC projectiles
    {"squidspit", int(g_EngineFuncs.CVarGetFloat("sk_bullsquid_dmg_spit"))},
    {"bmortar", 200},                    // Gonarch spit (Big Momma mortar)
    {"gonomespit", 10},                  // Gonome spit
    {"pitdronespike", 15},
    {"hornet", 7},
    {"playerhornet", 7},
    {"voltigoreshock", 35},
    {"kingpin_plasma_ball", 15},
    {"controller_head_ball", 2},
    {"controller_energy_ball", 10},
    {"nihilanth_energy_ball", 30},
    {"garg_stomp", 50}
};

// Damage types for specific projectiles
dictionary ExplosiveDamageTypes = {
    {"sporegrenade", DMG_ACID | DMG_POISON},
    {"squidspit", DMG_ACID},
    {"gonomespit", DMG_ACID},
    {"shock_beam", DMG_SHOCK | DMG_ALWAYSGIB},
    {"displacer_portal", DMG_ENERGYBEAM | DMG_ALWAYSGIB},
    {"voltigoreshock", DMG_SHOCK},
    {"controller_energy_ball", DMG_ENERGYBEAM},
    {"nihilanth_energy_ball", DMG_ENERGYBEAM}
};

// Init
void PluginInit() {
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
  @cvar_explosive = CCVar("explosive", 1.0, "Scale of player explosive damage", ConCommandFlag::AdminOnly);
  @cvar_npcExplosive = CCVar("npcExplosive", 1.0, "Scale of NPC explosive damage", ConCommandFlag::AdminOnly);

  resetGlobals();
}

// Hooks

HookReturnCode WeaponPrimaryAttack(CBasePlayer @pPlayer, CBasePlayerWeapon @pWeapon) {
  if (cvar_enabled.GetInt() != 1) return HOOK_CONTINUE;

  // Track medkit usage for 2s FF immunity
  if (pWeapon !is null && pWeapon.GetClassname() == "weapon_medkit") {
    lastMedkitHealTime[string(pPlayer.entindex())] = g_Engine.time;
  }

  CBaseEntity @pEntity = null;
  while ((@pEntity = g_EntityFuncs.FindEntityByClassname(pEntity, "*")) !is null) {
    CBaseEntity @owner = g_EntityFuncs.Instance(pEntity.pev.owner);

    if (owner != null && owner.IsPlayer() && owner.entindex() == pPlayer.entindex()) {
      if (trackedEntities.find(pEntity.entindex()) == -1 && pEntity.IsInWorld() && pEntity.GetClassname().Find("weapon_") != 0) {
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
        }
      }
    }
  }

  return HOOK_CONTINUE;
}

HookReturnCode WeaponSecondaryAttack(CBasePlayer @pPlayer, CBasePlayerWeapon @pWeapon) {
  WeaponPrimaryAttack(pPlayer, pWeapon);
  return HOOK_CONTINUE;
}

HookReturnCode CollectSatchel(CBaseEntity @pPickup, CBaseEntity @pOther) {
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

HookReturnCode MonsterTakeDamage(DamageInfo @pDamageInfo) {
  if (cvar_enabled.GetInt() != 1 || cvar_npc.GetFloat() == 0.0) return HOOK_CONTINUE;

  if (pDamageInfo !is null) {
    CBaseEntity @attacker = pDamageInfo.pAttacker;
    CBaseEntity @victim = pDamageInfo.pVictim;

    if (attacker !is null && attacker.IsPlayer()) {
      CBasePlayer @plr = cast<CBasePlayer @>(g_EntityFuncs.Instance(attacker.pev));
      if (victim.IsPlayerAlly()) {
        pDamageInfo.flDamage = pDamageInfo.flDamage * cvar_npc.GetFloat();
      }
      return HOOK_CONTINUE;
    }
  }

  return HOOK_CONTINUE;
}

HookReturnCode PlayerTakeDamage(DamageInfo @pDamageInfo) {
  if (cvar_enabled.GetInt() != 1) return HOOK_CONTINUE;

  CBasePlayer @plr = cast<CBasePlayer @>(g_EntityFuncs.Instance(pDamageInfo.pVictim.pev));
  CBaseEntity @attacker = pDamageInfo.pAttacker;
  CBaseEntity @inflictor = pDamageInfo.pInflictor;
  string steamId = g_EngineFuncs.GetPlayerAuthId(plr.edict());

  if (attacker.entindex() == plr.entindex() || inflictor.entindex() == plr.entindex()) return HOOK_CONTINUE;

  // Being attacked by another player on the same team
  if (cvar_player.GetFloat() != 0.0 && attacker.IsPlayer() && attacker.Classify() == plr.Classify()) {
    CBasePlayer @attackerPlayer = cast<CBasePlayer @>(attacker);

    // Check if attacker used medkit within last 2 seconds - give them FF immunity
    string attackerKey = string(attackerPlayer.entindex());
    if (lastMedkitHealTime.exists(attackerKey)) {
      float lastHealTime = float(lastMedkitHealTime[attackerKey]);
      if (g_Engine.time - lastHealTime < 2.0) {
        return HOOK_CONTINUE;
      }
    }

    CBaseEntity @friendlyNPCEntity = getFriendlyNPC(plr.GetOrigin());
    CBaseMonster @friendlyNPCMonster = cast<CBaseMonster @>(friendlyNPCEntity);

    friendlyNPCMonster.m_FormattedName = "player (" + attackerPlayer.pev.netname + ") using " + attackerPlayer.m_hActiveItem.GetEntity().GetClassname();
    plr.TakeDamage(inflictor.pev, friendlyNPCEntity.pev, pDamageInfo.flDamage * cvar_player.GetFloat(), pDamageInfo.bitsDamageType);
    return HOOK_HANDLED;

  } else {
    if (cvar_npcToPlayer.GetFloat() != 0.0 && !attacker.IsPlayer() && attacker.IsPlayerAlly()) {
      CBaseEntity @friendlyNPCEntity = getFriendlyNPC(plr.GetOrigin());
      CBaseMonster @friendlyNPCMonster = cast<CBaseMonster @>(friendlyNPCEntity);
      CBaseMonster @attackerMonster = cast<CBaseMonster @>(attacker);
      friendlyNPCMonster.m_FormattedName = "friendly NPC (" + attackerMonster.m_FormattedName + ")";
      plr.TakeDamage(inflictor.pev, friendlyNPCEntity.pev, pDamageInfo.flDamage * cvar_npcToPlayer.GetFloat(), pDamageInfo.bitsDamageType);
      if (!plr.IsAlive()) {
        attacker.pev.frags++;
      }
      return HOOK_HANDLED;
    }
  }

  return HOOK_CONTINUE;
}

void resetGlobals() {
  if (g_npcKillInterval !is null) g_Scheduler.RemoveTimer(g_npcKillInterval);
  @g_npcKillInterval = g_Scheduler.SetInterval("npc_kill", 1);

  if (g_trackEntitiesInterval !is null) g_Scheduler.RemoveTimer(g_trackEntitiesInterval);
  @g_trackEntitiesInterval = g_Scheduler.SetInterval("TrackEntities", 0.0, g_Scheduler.REPEAT_INFINITE_TIMES);

  trackedEntities.resize(0);
  trackedEntitiesPosition.resize(0);
  trackedEntitiesOwner.resize(0);
  trackedEntitiesType.resize(0);

  friendlyNPCHandle = EHandle();
}

void MapInit() {
  g_Game.PrecacheMonster("monster_gman", true);
  resetGlobals();
}

void AddClassToTrackEntities(string ClassName, string Type) {
  CBaseEntity @foundEntity = null;

  while ((@foundEntity = g_EntityFuncs.FindEntityByClassname(foundEntity, ClassName)) !is null) {
    if (trackedEntities.find(foundEntity.entindex()) == -1) {
      EHandle ownerHandle = g_EntityFuncs.Instance(foundEntity.pev.owner);
      CBaseEntity @ownerEntity = ownerHandle.GetEntity();
      // Track explosives from both players AND friendly NPCs
      if (ownerEntity !is null && (ownerEntity.IsPlayer() || ownerEntity.IsPlayerAlly())) {
        trackedEntities.insertLast(foundEntity.entindex());
        trackedEntitiesPosition.insertLast(foundEntity.GetOrigin());
        trackedEntitiesOwner.insertLast(ownerEntity.entindex());
        trackedEntitiesType.insertLast(Type);
      }
    }
  }
}

void TrackEntities() {
  if (cvar_enabled.GetInt() != 1) return;

  // Track all projectile types
  AddClassToTrackEntities("grenade", "grenade");
  AddClassToTrackEntities("displacer_portal", "displacer_portal");
  AddClassToTrackEntities("squidspit", "squidspit");
  AddClassToTrackEntities("bmortar", "bmortar");
  AddClassToTrackEntities("gonomespit", "gonomespit");
  AddClassToTrackEntities("pitdronespike", "pitdronespike");
  AddClassToTrackEntities("hornet", "hornet");
  AddClassToTrackEntities("playerhornet", "playerhornet");
  AddClassToTrackEntities("voltigoreshock", "voltigoreshock");
  AddClassToTrackEntities("kingpin_plasma_ball", "kingpin_plasma_ball");
  AddClassToTrackEntities("controller_head_ball", "controller_head_ball");
  AddClassToTrackEntities("controller_energy_ball", "controller_energy_ball");
  AddClassToTrackEntities("nihilanth_energy_ball", "nihilanth_energy_ball");

  // Work through tracked entities
  for (int i = int(trackedEntities.length()) - 1; i >= 0; --i) {
    if (i >= int(trackedEntities.length())) {
      continue;
    }

    edict_t @edict = g_EntityFuncs.IndexEnt(trackedEntities[i]);
    if (edict !is null) {
      EHandle entityHandle = g_EntityFuncs.Instance(edict);
      CBaseEntity @entity = entityHandle.GetEntity();
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

      CBaseEntity @friendlyNPCEntity = getFriendlyNPC(explosionPos);
      CBaseMonster @friendlyNPCMonster = cast<CBaseMonster @>(friendlyNPCEntity);
      edict_t @ownerEdict = g_EntityFuncs.IndexEnt(ownerId);
      
      bool isNPCExplosive = false;
      
      if (ownerEdict !is null) {
        EHandle entityOwnerHandle = g_EntityFuncs.Instance(ownerEdict);
        CBaseEntity @ownerEntity = entityOwnerHandle.GetEntity();

        if (ownerEntity !is null && ownerEntity.IsPlayer()) {
          CBasePlayer @plr = cast<CBasePlayer @>(ownerEntity);
          friendlyNPCMonster.m_FormattedName = "player (" + plr.pev.netname + ") using " + entityType;
          isNPCExplosive = false;
        } else if (ownerEntity !is null && ownerEntity.IsPlayerAlly()) {
          CBaseMonster @npc = cast<CBaseMonster @>(ownerEntity);
          friendlyNPCMonster.m_FormattedName = "friendly NPC (" + npc.m_FormattedName + ") using " + entityType;
          isNPCExplosive = true;
        } else {
          friendlyNPCMonster.m_FormattedName = "explosion";
        }
      } else {
        friendlyNPCMonster.m_FormattedName = "explosion";
      }

      if (ExplosiveDamges.exists(entityType)) {
        // Apply appropriate scaling based on who threw it
        float damageScale = isNPCExplosive ? cvar_npcExplosive.GetFloat() : cvar_explosive.GetFloat();
        
        if (damageScale == 0.0) continue;
        
        int dmg = int(ExplosiveDamges[entityType]);
        
        // Get damage type - default to DMG_BLAST if not specified
        int damageType = DMG_BLAST;
        if (ExplosiveDamageTypes.exists(entityType)) {
          damageType = int(ExplosiveDamageTypes[entityType]);
        }
        
        RadiusDamage(ownerEdict, explosionPos, friendlyNPCEntity.pev, friendlyNPCEntity.pev, dmg * damageScale, (dmg * damageScale) * 2.5, CLASS_NONE, damageType);
      }
    }
  }
}

CBaseEntity @getFriendlyNPC(Vector pos) {
  if (friendlyNPCHandle.IsValid()) {
    CBaseEntity @pEntity = friendlyNPCHandle.GetEntity();
    if (pEntity !is null) return @pEntity;
  }

  CBaseEntity @pEntity = g_EntityFuncs.CreateEntity("monster_gman", {}, true);
  pEntity.pev.solid = SOLID_NOT;
  pEntity.pev.effects |= EF_NODRAW;
  pEntity.pev.takedamage = DAMAGE_NO;
  pEntity.pev.spawnflags = 16;
  pEntity.SetOrigin(pos);
  pEntity.SetPlayerAlly(false);
  pEntity.SetPlayerAllyDirect(false);

  if (pEntity !is null) {
    friendlyNPCHandle = EHandle(pEntity);
    return @pEntity;
  }

  return null;
}

void npc_kill() {
  if (cvar_enabled.GetInt() != 1 || cvar_npc.GetFloat() == 0.0) {
    g_EngineFuncs.ServerCommand("mp_npckill 2\n");
    g_EngineFuncs.ServerExecute();
    return;
  }

  g_EngineFuncs.ServerCommand("mp_npckill 1\n");
  g_EngineFuncs.ServerExecute();
}

void RadiusDamage(edict_t @ownerEdict, Vector vecSrc, entvars_t @pevInflictor, entvars_t @pevAttacker, float flDamage, float flRadius, int iClassIgnore, int bitsDamageType) {
  int classification = -1;
  int ownerIndex = -1;

  if (ownerEdict !is null) {
    EHandle entityOwnerHandle = g_EntityFuncs.Instance(ownerEdict);
    CBaseEntity @ownerEntity = entityOwnerHandle.GetEntity();
    classification = ownerEntity.Classify();
    ownerIndex = ownerEntity.entindex();
  }

  CBaseEntity @pEntity;
  TraceResult tr;
  float flAdjustedDamage, falloff;
  Vector vecSpot;

  if (flRadius != 0)
    falloff = flDamage / flRadius;
  else
    falloff = 1.0;

  bool bInWater = (g_EngineFuncs.PointContents(vecSrc) == CONTENTS_WATER);
  vecSrc.z += 1;

  while ((@pEntity = g_EntityFuncs.FindEntityInSphere(pEntity, vecSrc, flRadius, "player", "classname")) !is null) {
    // For NPC owners, damage all players. For player owners, check classification match
    CBaseEntity @ownerEntity = null;
    if (ownerEdict !is null) {
      EHandle entityOwnerHandle = g_EntityFuncs.Instance(ownerEdict);
      @ownerEntity = entityOwnerHandle.GetEntity();
    }

    bool shouldDamage = false;
    if (ownerEntity !is null && ownerEntity.IsPlayerAlly()) {
      // NPC threw it - damage all players
      shouldDamage = true;
    } else if (ownerEntity !is null && ownerEntity.IsPlayer()) {
      // Player threw it - damage players on same team
      shouldDamage = (pEntity.Classify() == classification);
    }

    if (!pEntity.IsPlayer() || pEntity.entindex() == ownerIndex || !shouldDamage) {
      continue;
    }

    if (bInWater && pEntity.pev.waterlevel == 0) continue;
    if (!bInWater && pEntity.pev.waterlevel == 3) continue;

    vecSpot = pEntity.BodyTarget(vecSrc);
    g_Utility.TraceLine(vecSrc, vecSpot, dont_ignore_monsters, g_EntityFuncs.Instance(pevInflictor).edict(), tr);

    if (tr.flFraction == 1.0 || g_EntityFuncs.Instance(tr.pHit).entindex() == pEntity.entindex()) {
      if (tr.fStartSolid != 0) {
        tr.vecEndPos = vecSrc;
        tr.flFraction = 0.0;
      }

      flAdjustedDamage = (vecSrc - tr.vecEndPos).Length() * falloff;
      flAdjustedDamage = flDamage - flAdjustedDamage;

      if (flAdjustedDamage < 0) flAdjustedDamage = 0;

      if (tr.flFraction != 1.0) {
        g_WeaponFuncs.ClearMultiDamage();
        pEntity.TraceAttack(pevInflictor, flAdjustedDamage, (tr.vecEndPos.opSub(vecSrc)).Normalize(), tr, bitsDamageType);
        g_WeaponFuncs.ApplyMultiDamage(pevInflictor, pevAttacker);
      } else {
        pEntity.TakeDamage(pevInflictor, pevAttacker, flAdjustedDamage, bitsDamageType);
      }
    }
  }
}
