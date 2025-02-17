bool survivalActive = false;
bool resetTimerStopped = true;
int currentTime = 0;

array<string> trackedSpawned;

CCVar@ cvar_enabled;
CCVar@ cvar_timer;
CCVar@ cvar_resetTime;
CCVar@ cvar_lateSpawn;

CScheduledFunction@ g_pThinkFunc;

//Init
void PluginInit() {
	g_Module.ScriptInfo.SetAuthor("Sebastian");
	g_Module.ScriptInfo.SetContactInfo("https://github.com/TreeOfSelf/Sven-Survival");
    g_Hooks.RegisterHook( Hooks::Game::MapChange, @MapChange );
    g_Hooks.RegisterHook(Hooks::Player::PlayerSpawn, @PlayerSpawn);
	
    g_Hooks.RegisterHook(Hooks::Player::PlayerKilled, @PlayerKilled);
    g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientPutInServer);
    g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientDisconnect);



    @cvar_enabled = CCVar("enabled", 1, "Enable/Disable forced survival mode", ConCommandFlag::AdminOnly);
    @cvar_timer = CCVar("timer", 60, "Amount of time to count down to survival mode", ConCommandFlag::AdminOnly);
    @cvar_resetTime = CCVar("resetTime", 5, "Amount of time to reset map after last player dying", ConCommandFlag::AdminOnly);
    @cvar_lateSpawn = CCVar("lateSpawn", 1, "Enable/Disable late joining players to still spawn in", ConCommandFlag::AdminOnly);

    if (g_pThinkFunc !is null) {
		g_Scheduler.RemoveTimer(g_pThinkFunc);
		resetTimerStopped = true;
	}

    @g_pThinkFunc = g_Scheduler.SetInterval("displaySurvival", 1);

	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		if (plr !is null ) {
			Observer@ obs = plr.GetObserver();
			obs.StopObserver(true);
		} 
	}

    trackedSpawned.resize(0);
}

// Hooks
HookReturnCode MapChange( const string& in szNextMap ) {
	survivalActive = false;
	currentTime = 0;
	return HOOK_CONTINUE;
}

HookReturnCode PlayerSpawn( CBasePlayer@ pPlayer) {
    string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
    
    if(survivalActive && g_SurvivalMode.IsEnabled()==false && cvar_enabled.GetInt() == 1) {
        if (cvar_lateSpawn.GetInt() == 1 && trackedSpawned.find(steamId) < 0) {
            trackedSpawned.insertLast(steamId);        
            return HOOK_CONTINUE;        
        }
        
        Observer@ obs = pPlayer.GetObserver();
        obs.SetObserverModeControlEnabled( true );
        obs.StartObserver(pPlayer.GetOrigin(), pPlayer.pev.angles, true);
        obs.SetObserverModeControlEnabled( true );
        pPlayer.pev.nextthink = 10000000.0;
        return HOOK_HANDLED;
    }
    
    return HOOK_CONTINUE;
}

HookReturnCode PlayerKilled( CBasePlayer@ pPlayer, CBaseEntity@ pAttacker, int iGib ) {
	if (resetTimerStopped && survivalActive  && checkPlayersDead()) {
		@g_pThinkFunc = g_Scheduler.SetInterval("mapChanger", cvar_resetTime.GetInt());
	}
	return HOOK_HANDLED;
}

HookReturnCode ClientPutInServer(CBasePlayer@ plr) {
	if (resetTimerStopped && survivalActive && checkPlayersDead()) {
		@g_pThinkFunc = g_Scheduler.SetInterval("mapChanger", cvar_resetTime.GetInt());
	}
	return HOOK_CONTINUE;
}

HookReturnCode ClientDisconnect(CBasePlayer@ plr) {
    if (resetTimerStopped && survivalActive && checkPlayersDead()) {
        @g_pThinkFunc = g_Scheduler.SetInterval("mapChanger", cvar_resetTime.GetInt());
    }
    return HOOK_CONTINUE;
}


// Main Functions
void MapInit() {
	g_Game.PrecacheMonster( "monster_gman", true );
	trackedSpawned.resize(0);
}

void displaySurvival() {
	if(g_SurvivalMode.IsEnabled()==false &&  cvar_enabled.GetInt() == 1) {
		if(currentTime<cvar_timer.GetInt()) {
			int oucurrentTime = cvar_timer.GetInt() - currentTime;
			for (int i = 1; i <= g_Engine.maxClients; i++) {
				CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
				if (plr !is null) {
					g_EngineFuncs.ClientPrintf(plr, print_center, "Survival mode starting in "+string(oucurrentTime)+" seconds");
				} 
			}
		}
		if(currentTime == cvar_timer.GetInt()) {
			g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "Survival mode now active. No more respawning allowed.");
			survivalActive = true;
			if (resetTimerStopped && survivalActive  && checkPlayersDead()) {
				@g_pThinkFunc = g_Scheduler.SetInterval("mapChanger", cvar_resetTime.GetInt());
			}
			for (int i = 1; i <= g_Engine.maxClients; i++) {
				CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
				if (plr !is null && plr.IsAlive()==true && plr.IsConnected()) {
					string steamId = g_EngineFuncs.GetPlayerAuthId(plr.edict());
					if (cvar_lateSpawn.GetInt() == 1 && trackedSpawned.find(steamId) < 0) {
						trackedSpawned.insertLast(steamId);        
					}
				}
			}
		}
	}
	currentTime+=1;
}

void mapChanger() {
	if(g_SurvivalMode.IsEnabled()==false &&  cvar_enabled.GetInt() == 1 && currentTime >= cvar_timer.GetInt()) {
		if(checkPlayersDead()) {
			g_EngineFuncs.ChangeLevel(string(g_Engine.mapname));
		}
	}
	g_Scheduler.RemoveTimer(g_pThinkFunc);
	resetTimerStopped = true;
}

bool checkPlayersDead() {
	int reset = 1;
	int playerHit = 0;
		for (int i = 1; i <= g_Engine.maxClients; i++) {
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			if (plr !is null && plr.IsAlive()==true && plr.IsConnected()) {
				reset=0;
			} 
			if (plr !is null) {
				playerHit=1;
			}
		}
	if(reset==1 && playerHit==1) {
		return(true);
	}
	return(false);
}
