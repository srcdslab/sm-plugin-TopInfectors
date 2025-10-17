#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <zombiereloaded>
#include <TopInfectors>
#include <multicolors>
#include <smlib>

#undef REQUIRE_PLUGIN
#tryinclude <DynamicChannels>
#tryinclude <nemesis>
#define REQUIRE_PLUGIN

#include "loghelper.inc"
#include "utilshelper.inc"

#pragma semicolon 1
#pragma newdecls required

enum WeaponAmmoGrenadeType
{
	GrenadeType_Invalid             = -1,   /** Invalid grenade slot. */
	GrenadeType_HEGrenade           = 11,   /** CSS - HEGrenade slot */
	GrenadeType_Flashbang           = 12,   /** CSS - Flashbang slot. */
	GrenadeType_Smokegrenade        = 13,   /** CSS - Smokegrenade slot. */
}

#define BELL_SOUND_COMMON   "topinfectors/bell.wav"
#define SKULL_MODEL         "models/unloze/skull_v3.mdl"

int g_iSortedCount = 0;
int g_iSortedList[MAXPLAYERS+1][2];
int g_iInfectCount[MAXPLAYERS + 1] = { 0, ... };
int g_iTopInfector[MAXPLAYERS + 1] = { -1, ... };
int g_iSkullEntities[MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... };

int g_iPrintColor[3];
float g_fPrintPos[2];

ConVar g_cvHat, g_cvAmount, g_cvHENades, g_cvSmokeNades, g_cvPrint, g_cvPrintPos, g_cvPrintColor, g_cvHUDChannel;

Handle g_hHudSync = INVALID_HANDLE;
Handle g_hUpdateTimer = INVALID_HANDLE;

bool g_bHideSkull[MAXPLAYERS+1] = { false, ... };
Handle g_hSpawnTimer[MAXPLAYERS + 1];

bool g_bNemesis = false;
bool g_bDynamicChannels = false;

public Plugin myinfo = 
{
	name            =       "Top Infectors",
	author          =       "Nano, maxime1907, .Rushaway",
	description     =       "Show top infectors after each round",
	version         =       TopInfectors_VERSION,
	url             =       "https://github.com/srcdslab/sm-plugin-TopInfectors"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("TopInfectors_IsTopInfector", Native_IsTopInfector);
	CreateNative("TopInfectors_GetClientRank", Native_GetClientRank);

	RegPluginLibrary("TopInfectors");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("topinfectors.phrases");

	g_cvAmount = CreateConVar("sm_topinfectors_players", "3", "Amount of players on the top infectors table", _, true, 0.0, true, 5.0);
	g_cvHENades = CreateConVar("sm_topinfectors_nades", "1", "How much nades are given to top infectors", _, true, 0.0, true, 10.0);
	g_cvSmokeNades = CreateConVar("sm_topinfectors_smokes", "1", "How much smokes are given to top killers", _, true, 0.0, true, 10.0);
	g_cvHat = CreateConVar("sm_topinfectors_hat", "1", "Enable hat on top infectors", _, true, 0.0, true, 1.0);
	g_cvPrint = CreateConVar("sm_topinfectors_print", "0", "2 - Display in hud, 1 - In chat, 0 - Both", _, true, 0.0, true, 2.0);
	g_cvPrintPos = CreateConVar("sm_topinfectors_print_position", "0.02 0.42", "The X and Y position for the hud.");
	g_cvPrintColor = CreateConVar("sm_topinfectors_print_color", "255 0 0", "RGB color value for the hud.");
	g_cvHUDChannel = CreateConVar("sm_topinfectors_hud_channel", "2", "The channel for the hud if using DynamicChannels", _, true, 0.0, true, 5.0);

	g_cvPrint.AddChangeHook(OnConVarChange);
	g_cvPrintPos.AddChangeHook(OnConVarChange);
	g_cvPrintColor.AddChangeHook(OnConVarChange);

	RegConsoleCmd("sm_toggleskull", Command_ToggleSkull);
	RegConsoleCmd("sm_tistatus", Command_OnToggleStatus, "Show Top Infector status - sm_tistatus <target|#userid>");

	AutoExecConfig(true);
	GetConVars();

	UpdateInfectorsList(INVALID_HANDLE);

	HookEvent("round_start", Event_OnRoundStart);
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnClientDeath);

	g_hHudSync = CreateHudSynchronizer();
}

public void OnPluginEnd()
{
	RemoveAllHats();
}

public void OnAllPluginsLoaded()
{
	g_bDynamicChannels = LibraryExists("DynamicChannels");
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bDynamicChannels = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bDynamicChannels = false;
}

public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	GetConVars();
}

public void OnMapStart()
{
	PrecacheSound(BELL_SOUND_COMMON);
	PrecacheModel(SKULL_MODEL);
	AddFilesToDownloadsTable("topinfectors_downloadlist.ini");

	g_hUpdateTimer = CreateTimer(0.5, UpdateInfectorsList, INVALID_HANDLE, TIMER_REPEAT);
}

public void OnMapEnd()
{
	RemoveAllHats();

	for (int i = 1; i <= MaxClients; i++)
	{
		delete g_hSpawnTimer[i];
	}

	if (g_hUpdateTimer != INVALID_HANDLE)
	{
		KillTimer(g_hUpdateTimer);
		g_hUpdateTimer = INVALID_HANDLE;
	}
}

public void OnClientPutInServer(int client)
{
	g_iSkullEntities[client] = INVALID_ENT_REFERENCE;
}

public void OnClientDisconnect(int client)
{
	RemoveHat(client);
	g_bHideSkull[client] = false;
	g_iTopInfector[client] = -1;
	g_iInfectCount[client] = 0;
}

public Action UpdateInfectorsList(Handle timer)
{
	for (int i = 0; i < sizeof(g_iSortedList); i++)
	{
		g_iSortedList[i][0] = -1;
		g_iSortedList[i][1] = 0;
	}

	g_iSortedCount = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !g_iInfectCount[client])
			continue;

		g_iSortedList[g_iSortedCount][0] = client;
		g_iSortedList[g_iSortedCount][1] = g_iInfectCount[client];
		g_iSortedCount++;
	}

	SortCustom2D(g_iSortedList, g_iSortedCount, SortInfectorsList);

	if (timer == INVALID_HANDLE)
		return Plugin_Stop;

	return Plugin_Continue;
}

public Action Command_ToggleSkull(int client, int argc)
{
	ToggleSkull(client);
	return Plugin_Handled;
}

public Action Command_OnToggleStatus(int client, int args)
{
	int target = -1;

	if (args != 0)
	{
		char sArg[MAX_NAME_LENGTH];
		GetCmdArg(1, sArg, sizeof(sArg));
		target = FindTarget(client, sArg, false, true);
	}
	else
		target = client;

	SetGlobalTransTarget(client);

	if (target == -1)
	{
		CReplyToCommand(client, "{green}%t {white}%t", "Chat Prefix", "Player no longer available");
		return Plugin_Handled;
	}

	if (target > 0 && target <= MaxClients)
	{
		int iDisplayRank = GetClientRank(target);
		int rank = iDisplayRank - 1;

		if (rank < 0 || rank >= g_iSortedCount)
			CReplyToCommand(client, "{green}%t {white}%t", "Chat Prefix", "Not ranked");
		else
		{
			char sType[64];
			if (g_bNemesis)
				FormatEx(sType, sizeof(sType), "%t", "Killed", client);
			else
				FormatEx(sType, sizeof(sType), "%t", "Infected", client);

			CReplyToCommand(client, "{green}%t {white}%t", "Chat Prefix", "TopInfector Position", target, iDisplayRank, g_iSortedList[rank][1], sType);
		}
	}
	return Plugin_Handled;
}

//---------------------------------------
// Purpose: Hooks
//---------------------------------------

public Action ZR_OnClientInfect(int &client, int &attacker, bool &motherInfect, bool &respawnOverride, bool &respawn) 
{
	if (!IsValidZombie(attacker))
	{
		return Plugin_Continue;
	}

	g_iInfectCount[attacker]++;
	return Plugin_Continue;
}

public void Event_OnClientDeath(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != client)
			continue;

		if (g_iTopInfector[i] == 0 && !IsPlayerAlive(i))
		{
			RemoveHat(i);
		}

		break;
	}

	if (g_bNemesis)
	{
		int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));
		if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && IsPlayerAlive(attacker) && ZR_IsClientZombie(attacker))
			g_iInfectCount[attacker]++;
	}
}

public void Event_OnRoundStart(Event event, char[] name, bool dontBroadcast) 
{
	RemoveAllHats();
	Cleanup();
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontbroadcast) 
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsValidClient(client) || !IsPlayerAlive(client) || !ZR_IsClientHuman(client) || g_iTopInfector[client] <= -1)
		return;
	
	delete g_hSpawnTimer[client];
	g_hSpawnTimer[client] = CreateTimer(7.0, Timer_OnClientSpawnPost, client);
}

public void Event_OnRoundEnd(Event event, char[] name, bool dontBroadcast) 
{
	// ZombieReloaded always fire a team win event before the draw event
	// So we can ignore the draw event - Prevent duplicate execution
	if (!IsValidTeamVictory(event))
		return;

	Cleanup(true);
	UpdateInfectorsList(INVALID_HANDLE);

	for (int rank = 0; rank < g_iSortedCount; rank++)
	{
		LogMessage("%d - %L (%d)", rank + 1, g_iSortedList[rank][0], g_iSortedList[rank][1]);
	}

	if (!g_iSortedCount)
		return;

	for (int i = 0; i < g_cvAmount.IntValue; i++)
	{
		if (g_iSortedList[i][0] > 0 && g_iSortedList[i][0] <= MaxClients)
		{
			g_iTopInfector[g_iSortedList[i][0]] = i;

			if (g_bNemesis)
			{
				switch (i)
				{
					case 0: LogPlayerEvent(g_iSortedList[i][0], "triggered", "top_nemesis");
					case 1: LogPlayerEvent(g_iSortedList[i][0], "triggered", "second_nemesis");
					case 2: LogPlayerEvent(g_iSortedList[i][0], "triggered", "third_nemesis");
					case 3: LogPlayerEvent(g_iSortedList[i][0], "triggered", "fourth_nemesis");
					default: LogPlayerEvent(g_iSortedList[i][0], "triggered", "super_nemesis");
				}
			}
			else
			{
				switch (i)
				{
					case 0: LogPlayerEvent(g_iSortedList[i][0], "triggered", "top_infector");
					case 1: LogPlayerEvent(g_iSortedList[i][0], "triggered", "second_infector");
					case 2: LogPlayerEvent(g_iSortedList[i][0], "triggered", "third_infector");
					case 3: LogPlayerEvent(g_iSortedList[i][0], "triggered", "fourth_infector");
					default: LogPlayerEvent(g_iSortedList[i][0], "triggered", "super_infector");
				}
			}
		}
	}

	bool bDynamicAvailable = g_bDynamicChannels && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;

	int iHUDChannel = g_cvHUDChannel.IntValue;
	if (iHUDChannel < 0 || iHUDChannel > 5)
		iHUDChannel = 2;

#if defined _DynamicChannels_included_
	if (bDynamicAvailable)
		iHUDChannel = GetDynamicChannel(iHUDChannel);
#endif

	// Send messages to clients based on g_cvPrint value
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			char sMenuTitle[128], sType[64];
			if (!g_bNemesis)
			{
				Format(sMenuTitle, sizeof(sMenuTitle), "%t:", "Menu Title Infectors", i);
				FormatEx(sType, sizeof(sType), "%t", "Infected", i);
			}
			else
			{
				Format(sMenuTitle, sizeof(sMenuTitle), "%t:", "Menu Title Nemesis", i);
				FormatEx(sType, sizeof(sType), "%t", "Killed", i);
			}

			char sBuffer[512];
			String_ToUpper(sMenuTitle, sBuffer, sizeof(sBuffer));

			for (int rank = 0; rank < g_cvAmount.IntValue && rank < g_iSortedCount; rank++)
			{
				// Create the top infectors list display
				if (g_iSortedList[rank][0] > 0 && g_iSortedList[rank][0] <= MaxClients)
					Format(sBuffer, sizeof(sBuffer), "%s\n%d. %N - %d %s", sBuffer, rank + 1, g_iSortedList[rank][0], g_iSortedList[rank][1], sType);
			}

			bool bPersonal = false;
			char sPersonalBuffer[512];

			int iDisplayRank = GetClientRank(i);
			int rank = iDisplayRank - 1;

			if (iDisplayRank > g_cvAmount.IntValue && iDisplayRank <= g_iSortedCount)
			{
				bPersonal = true;
				Format(sPersonalBuffer, sizeof(sPersonalBuffer), "\n%d. %N - %d %s", iDisplayRank, g_iSortedList[rank][0], g_iSortedList[rank][1], sType);
			}

			if (g_cvPrint.IntValue <= 0 || g_cvPrint.IntValue == 1)
				CPrintToChat(i, "{darkred}%s%s", sBuffer, bPersonal ? sPersonalBuffer : "");

			if (g_cvPrint.IntValue <= 0 || g_cvPrint.IntValue == 2)
			{
				SetHudTextParams(g_fPrintPos[0], g_fPrintPos[1], 5.0, g_iPrintColor[0], g_iPrintColor[1], g_iPrintColor[2], 255, 0, 0.0, 0.1, 0.1);
				if (bDynamicAvailable)
					ShowHudText(i, iHUDChannel, "%s%s", sBuffer, bPersonal ? sPersonalBuffer : "");
				else
				{
					ClearSyncHud(i, g_hHudSync);
					ShowSyncHudText(i, g_hHudSync, "%s%s", sBuffer, bPersonal ? sPersonalBuffer : "");
				}
			}
		}
	}
}

public void SetPerks(int client, char[] notifHudMsg, char[] notifChatMsg)
{
	Handle hMessageInfection = StartMessageOne("HudMsg", client);
	if (hMessageInfection)
	{
		if (GetUserMessageType() == UM_Protobuf)
		{
			PbSetInt(hMessageInfection, "channel", 50);
			PbSetInt(hMessageInfection, "effect", 0);
			PbSetColor(hMessageInfection, "clr1", {255, 255, 255, 255});
			PbSetColor(hMessageInfection, "clr2", {255, 255, 255, 255});
			PbSetVector2D(hMessageInfection, "pos", view_as<float>({-1.0, 0.2}));
			PbSetFloat(hMessageInfection, "fade_in_time", 0.1);
			PbSetFloat(hMessageInfection, "fade_out_time", 0.1);
			PbSetFloat(hMessageInfection, "hold_time", 5.0);
			PbSetFloat(hMessageInfection, "fx_time", 0.0);
			PbSetString(hMessageInfection, "text", notifHudMsg);
			EndMessage();
		}
		else
		{
			BfWriteByte(hMessageInfection, 50);
			BfWriteFloat(hMessageInfection, -1.0);
			BfWriteFloat(hMessageInfection, 0.2);
			BfWriteByte(hMessageInfection, 0);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 0);
			BfWriteFloat(hMessageInfection, 0.1);
			BfWriteFloat(hMessageInfection, 0.1);
			BfWriteFloat(hMessageInfection, 5.0);
			BfWriteFloat(hMessageInfection, 0.0);
			BfWriteString(hMessageInfection, notifHudMsg);
			EndMessage();
		}
	}

	char sPrefix[64];
	FormatEx(sPrefix, sizeof(sPrefix), "%t", "Chat Prefix", client);
	CPrintToChat(client, "{darkblue}%s {grey}%s", sPrefix, notifChatMsg);

	GiveGrenadesToClient(client, g_cvHENades.IntValue, GrenadeType_HEGrenade);
	if (g_bNemesis)
		GiveGrenadesToClient(client, g_cvSmokeNades.IntValue, GrenadeType_Smokegrenade);

	if (g_iTopInfector[client] != 0 || g_bHideSkull[client])
		return;

	EmitSoundToClient(client, BELL_SOUND_COMMON, .volume=1.0);
	if (GetConVarInt(g_cvHat) == 1)
	{
		CreateHat(client);
	}
}

//---------------------------------------
// Purpose: Timers
//---------------------------------------

public Action Timer_OnClientSpawnPost(Handle timer, any client)
{
	g_hSpawnTimer[client] = null;
	if (!IsValidClient(client) || !IsPlayerAlive(client) || g_iTopInfector[client] <= -1 || !ZR_IsClientHuman(client))
		return Plugin_Continue;

	char sType[64];
	if (g_bNemesis)
		FormatEx(sType, sizeof(sType), "%t", "Nemesis", client);
	else
		FormatEx(sType, sizeof(sType), "%t", "Infectors", client);

	char sRewardMsg[128], sTheTop[128];
	FormatEx(sRewardMsg, sizeof(sRewardMsg), "%t", "Reward Msg", client);
	FormatEx(sTheTop, sizeof(sTheTop), "%t", "The top", sType, client);

	char sHudMsg[256], sNotifMsg[256];
	FormatEx(sHudMsg, sizeof(sHudMsg), "%s\n%s", sRewardMsg, sTheTop);
	FormatEx(sNotifMsg, sizeof(sNotifMsg), "%s %s", sRewardMsg, sTheTop);

	SetPerks(client, sHudMsg, sNotifMsg);
	return Plugin_Continue;
}

//---------------------------------------
// Purpose: Functions
//---------------------------------------

stock void Cleanup(bool bRoundEnd = false)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (bRoundEnd)
			g_iTopInfector[client] = -1;
		else
			g_iInfectCount[client] = 0;
	}
}

stock void ToggleSkull(int client)
{
	g_bHideSkull[client] = !g_bHideSkull[client];
	if (g_bHideSkull[client] && IsValidClient(client) && IsPlayerAlive(client) && g_iTopInfector[client] == 0)
	{
		RemoveHat(client);
	}
	else if (!g_bHideSkull[client] && IsValidClient(client) && IsPlayerAlive(client) && g_iTopInfector[client] == 0)
	{
		if (GetConVarInt(g_cvHat) == 1)
		{
			CreateHat(client);
		}
	}

	CPrintToChat(client, "{darkblue}%t {grey}%t", "Chat Prefix", g_bHideSkull[client] ? "Skull Disabled" : "Skull Enabled", client);
}

stock void RemoveHat(int client)
{
	if (g_iSkullEntities[client] != INVALID_ENT_REFERENCE)
	{
		int iSkullEntity = EntRefToEntIndex(g_iSkullEntities[client]);
		if (!IsValidEntity(iSkullEntity))
			return;

		// We always verify the entity we are going to remove
		char sModel[128];
		GetEntPropString(iSkullEntity, Prop_Data, "m_ModelName", sModel, sizeof(sModel));

		// Something went wrong, we should not remove this entity
		if (strcmp(sModel, SKULL_MODEL, false) != 0)
		{
			char sClassName[64];
			GetEntityClassname(iSkullEntity, sClassName, sizeof(sClassName));
			LogError("Blocked attempt to remove invalid entity %d (%s) for %L", iSkullEntity, sClassName, client);
			return;
		}
			AcceptEntityInput(iSkullEntity, "Kill");
		g_iSkullEntities[client] = INVALID_ENT_REFERENCE;
	}
}

stock void RemoveAllHats()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		RemoveHat(client);
	}
}

void CreateHat(int client) 
{ 
	RemoveHat(client);

	if ((g_iSkullEntities[client] = EntIndexToEntRef(CreateEntityByName("prop_dynamic"))) == INVALID_ENT_REFERENCE)
		return;
	
	int iSkullEntity = EntRefToEntIndex(g_iSkullEntities[client]);
	SetEntityModel(iSkullEntity, SKULL_MODEL);

	DispatchKeyValue(iSkullEntity, "solid",                 "0");
	DispatchKeyValue(iSkullEntity, "modelscale",            "1.3");
	DispatchKeyValue(iSkullEntity, "disableshadows",        "1");
	DispatchKeyValue(iSkullEntity, "disablereceiveshadows", "1");
	DispatchKeyValue(iSkullEntity, "disablebonefollowers",  "1");

	float fVector[3];
	float fAngles[3];
	GetClientAbsOrigin(client, fVector);
	GetClientAbsAngles(client, fAngles);

	fVector[2] += 80.0;
	fAngles[0] = 8.0;
	fAngles[2] = 5.5;

	TeleportEntity(iSkullEntity, fVector, fAngles, NULL_VECTOR);

	float fDirection[3];
	fDirection[0] = 0.0;
	fDirection[1] = 0.0;
	fDirection[2] = 1.0;

	TE_SetupSparks(fVector, fDirection, 1000, 200);
	TE_SendToAll();

	SetVariantString("!activator");
	AcceptEntityInput(iSkullEntity, "SetParent", client);
}

stock void GiveGrenadesToClient(int client, int iAmount, WeaponAmmoGrenadeType type)
{
	char sWeapon[32];
	int iAmmo = GetClientGrenades(client, type);
	switch(type)
	{
		case GrenadeType_HEGrenade:
			FormatEx(sWeapon, sizeof(sWeapon), "weapon_hegrenade");
		case GrenadeType_Flashbang:
			FormatEx(sWeapon, sizeof(sWeapon), "weapon_flashbang");
		case GrenadeType_Smokegrenade:
			FormatEx(sWeapon, sizeof(sWeapon), "weapon_smokegrenade");
		default:
			return;
	}

	if (iAmmo > 0)
	{
		int offsNades = FindDataMapInfo(client, "m_iAmmo") + (view_as<int>(type) * 4);
		int count = GetEntData(client, offsNades);
		SetEntData(client, offsNades, count + iAmount);
	}
	else
	{
		GivePlayerItem(client, sWeapon);
		// If the player suppose to get more than 1 grenade, now add them.
		if (iAmount > 1)
		{
			int offsNades = FindDataMapInfo(client, "m_iAmmo") + (view_as<int>(type) * 4);
			int count = GetEntData(client, offsNades);
			SetEntData(client, offsNades, count + iAmount - 1);
		}
	}
}

stock int GetClientGrenades(int client, WeaponAmmoGrenadeType type)
{
    int offsNades = FindDataMapInfo(client, "m_iAmmo") + (view_as<int>(type) * 4);
    return GetEntData(client, offsNades);
}

stock int GetClientRank(int client)
{
	int rank = 0;
	while (rank < g_iSortedCount)
	{
		if (g_iSortedList[rank][0] == client)
			break;
		rank++;
	}
	return rank + 1;
}

public void GetConVars()
{
	char StringPos[2][8];
	char ColorValue[64];
	char PosValue[16];

	g_cvPrintPos.GetString(PosValue, sizeof(PosValue));
	ExplodeString(PosValue, " ", StringPos, sizeof(StringPos), sizeof(StringPos[]));

	g_fPrintPos[0] = StringToFloat(StringPos[0]);
	g_fPrintPos[1] = StringToFloat(StringPos[1]);

	g_cvPrintColor.GetString(ColorValue, sizeof(ColorValue));
	ColorStringToArray(ColorValue, g_iPrintColor);
}

public int SortInfectorsList(int[] elem1, int[] elem2, const int[][] array, Handle hndl)
{
	if (elem1[1] > elem2[1]) return -1;
	if (elem1[1] < elem2[1]) return 1;

	return 0;
}

bool IsValidZombie(int attacker) 
{
	return (0 < attacker <= MaxClients && IsValidEntity(attacker) && IsClientInGame(attacker) && IsPlayerAlive(attacker));
}

//---------------------------------------
// Purpose: Natives
//---------------------------------------

public int Native_IsTopInfector(Handle plugin, int numParams)
{
	LogError("Native IsTopInfector() is deprecated, use TopInfectors_GetClientRank() instead.");
	int client = GetNativeCell(1);
	if (client && IsClientInGame(client))
	{
		return g_iTopInfector[client];
	}
	return -1;
}

public int Native_GetClientRank(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || !IsClientInGame(client))
		return -1;

	return GetClientRank(client);
}

#if defined _nemesis_included
public void Nemesis_OnConfigVerified(bool configExists)
{
	g_bNemesis = configExists;
}
#endif
