#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <zombiereloaded>
#include <multicolors>
#include <clientprefs>

#undef REQUIRE_PLUGIN
#tryinclude <DynamicChannels>
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
	GrenadeType_HEGrenadeCSGO       = 14,   /** CSGO - HEGrenade slot. */
	GrenadeType_FlashbangCSGO       = 15,   /** CSGO - Flashbang slot. */
	GrenadeType_SmokegrenadeCSGO    = 16,   /** CSGO - Smokegrenade slot. */
	GrenadeType_Incendiary          = 17,   /** CSGO - Incendiary and Molotov slot. */
	GrenadeType_Decoy               = 18,   /** CSGO - Decoy slot. */
	GrenadeType_Tactical            = 22,   /** CSGO - Tactical slot. */
}

#define BELL_SOUND_COMMON	"topinfectors/bell.wav"
#define SKULL_MODEL_CSGO	"models/topdefenders_perk/skull_v2.mdl"
#define SKULL_MODEL_CSS		"models/unloze/skull_v3.mdl"

int g_iEntIndex[MAXPLAYERS + 1] = { -1, ... };

int g_iSkullEntity = -1;

int g_iInfectCount[MAXPLAYERS + 1] = { 0, ... };
int g_iTopInfector[MAXPLAYERS + 1] = { -1, ... };

int g_iPrintColor[3];
float g_fPrintPos[2];

ConVar g_cvHat, g_cvAmount, g_cvHENades, g_cvSmokeNades, g_cvPrint, g_cvPrintPos, g_cvPrintColor, g_cvHUDChannel;

Handle g_hHudSync = INVALID_HANDLE;

bool g_bHideSkull[MAXPLAYERS+1] = { false, ... };
Handle g_hSpawnTimer[MAXPLAYERS + 1];
Handle g_hCookie_HideSkull;

bool g_bIsCSGO = false;

public Plugin myinfo = 
{
	name 			= 		"Top Infectors",
	author 			=		"Nano, maxime1907, .Rushaway",
	description 	= 		"Show top infectors after each round",
	version 		= 		"1.2.1",
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bIsCSGO = (GetEngineVersion() == Engine_CSGO);
	CreateNative("TopInfectors_IsTopInfector", Native_IsTopInfector);
	RegPluginLibrary("TopInfectors");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("topinfectors.phrases");

	g_cvAmount = CreateConVar("sm_topinfectors_players", "3", "Amount of players on the top infectors table", _, true, 0.0, true, 5.0);
	g_cvHENades = CreateConVar("sm_topinfectors_nades", "1", "How much nades are given to top infectors", _, true, 0.0, true, 10.0);
	g_cvSmokeNades = CreateConVar("sm_topinfectors_smokes", "1", "How much smokes are given to top killers", _, true, 0.0, true, 10.0);
	g_cvHat = CreateConVar("sm_topinfectors_hat", "1", "Enable hat on top infectors", _, true, 0.0, true, 1.0);
	g_cvPrint = CreateConVar("sm_topinfectors_print", "0", "2 - Display in hud, 1 - In chat, 0 - Both", _, true, 0.0, true, 2.0);
	g_cvPrintPos = CreateConVar("sm_topinfectors_print_position", "0.02 0.42", "The X and Y position for the hud.");
	g_cvPrintColor = CreateConVar("sm_topinfectors_print_color", "255 0 0", "RGB color value for the hud.");
	g_cvHUDChannel = CreateConVar("sm_topinfectors_hud_channel", "2", "The channel for the hud if using DynamicChannels", _, true, 0.0, true, 6.0);

	g_cvPrint.AddChangeHook(OnConVarChange);
	g_cvPrintPos.AddChangeHook(OnConVarChange);
	g_cvPrintColor.AddChangeHook(OnConVarChange);

	g_hCookie_HideSkull  = RegClientCookie("topinfectors_hide_skull",  "", CookieAccess_Private);

	SetCookieMenuItem(CookieMenu_TopInfectors, INVALID_HANDLE, "TopInfectors Settings");

	RegConsoleCmd("sm_toggleskull", Command_ToggleSkull);

	AutoExecConfig(true);
	GetConVars();

	HookEvent("round_start", Event_OnRoundStart);
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnClientDeath);

	g_hHudSync = CreateHudSynchronizer();
}

public void OnPluginEnd()
{
	Cleanup(true);
}

public void OnAllPluginsLoaded()
{
	g_bNemesis = LibraryExists("Nemesis");
	g_bDynamicChannels = LibraryExists("DynamicChannels");
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "Nemesis", false) == 0)
		g_bNemesis = true;
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bDynamicChannels = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "Nemesis", false) == 0)
		g_bNemesis = false;
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

	if (g_bIsCSGO)
		PrecacheModel(SKULL_MODEL_CSGO);
	else
		PrecacheModel(SKULL_MODEL_CSS);

	AddFilesToDownloadsTable("topinfectors_downloadlist.ini");
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		delete g_hSpawnTimer[i];
	}
}

public void OnClientPutInServer(int client)
{
	if (AreClientCookiesCached(client))
	{
		GetCookies(client);
	}
}

public void GetCookies(int client)
{
	char sBuffer[4];
	GetClientCookie(client, g_hCookie_HideSkull, sBuffer, sizeof(sBuffer));

	if (sBuffer[0])
		g_bHideSkull[client] = true;
	else
		g_bHideSkull[client] = false;
}

public void OnClientCookiesCached(int client)
{
	GetCookies(client);
}

public void OnClientDisconnect(int client)
{
	SetClientCookie(client, g_hCookie_HideSkull, g_bHideSkull[client] ? "1" : "");

	g_bHideSkull[client] = false;
	g_iTopInfector[client] = -1;
	g_iInfectCount[client] = 0;
}

public Action Command_ToggleSkull(int client, int argc)
{
	ToggleSkull(client);
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
			if (!g_bIsCSGO)
				RemoveHat_CSS(i);
			else
				RemoveHat_CSGO(i);
		}

		break;
	}
	if (g_bNemesis)
	{
		int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));
		if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && IsPlayerAlive(attacker) && ZR_IsClientZombie(attacker))
		{
			if (g_iInfectCount[attacker] == 1) g_iInfectCount[attacker]++; // 1st kill is never counted, so tricky fix to display the correct value..

			g_iInfectCount[attacker]++;
		}
	}
}

public void Event_OnRoundStart(Event event, char[] name, bool dontBroadcast) 
{
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
	Cleanup(_, true);

	int iSortedList[MAXPLAYERS+1][2];
	int iSortedCount = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !g_iInfectCount[client])
			continue;

		iSortedList[iSortedCount][0] = client;
		iSortedList[iSortedCount][1] = g_iInfectCount[client];
		iSortedCount++;
	}

	SortCustom2D(iSortedList, iSortedCount, SortInfectorsList);

	for (int rank = 0; rank < iSortedCount; rank++)
	{
		LogMessage("%d - %L (%d)", rank + 1, iSortedList[rank][0], iSortedList[rank][1]);
	}

	if (!iSortedCount)
		return;

	char sBuffer[512];
	if (g_bNemesis)
		Format(sBuffer, sizeof(sBuffer), "TOP NEMESIS:");
	else
		Format(sBuffer, sizeof(sBuffer), "TOP INFECTORS:");

	for (int i = 0; i < g_cvAmount.IntValue; i++)
	{
		if (iSortedList[i][0])
		{
			g_iTopInfector[iSortedList[i][0]] = i;
			if (g_bNemesis)
			{
				Format(sBuffer, sizeof(sBuffer), "%s\n%d. %N - %d KILLS", sBuffer, i + 1, iSortedList[i][0], iSortedList[i][1]);
				LogPlayerEvent(iSortedList[i][0], "triggered", i == 0 ? "top_nemesis" : (i == 1 ? "second_nemesis" : (i == 2 ? "third_nemesis" : "super_nemesis")));
			}
			else
			{
				Format(sBuffer, sizeof(sBuffer), "%s\n%d. %N - %d INFECTED", sBuffer, i + 1, iSortedList[i][0], iSortedList[i][1]);
				LogPlayerEvent(iSortedList[i][0], "triggered", i == 0 ? "top_infector" : (i == 1 ? "second_infector" : (i == 2 ? "third_infector" : "super_infector")));
			}
		}
	}

	if (g_cvPrint.IntValue <= 0 || g_cvPrint.IntValue == 1)
		CPrintToChatAll("{darkred}%s", sBuffer);

	bool bDynamicAvailable = false;
	int iHUDChannel = -1;

#if defined _DynamicChannels_included_
	int iChannel = g_cvHUDChannel.IntValue;
	if (iChannel < 0 || iChannel > 6)
		iChannel = 2;

	bDynamicAvailable = g_bDynamicChannels && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;
	if (bDynamicAvailable)
		iHUDChannel = GetDynamicChannel(iChannel);
#endif

	if (g_cvPrint.IntValue <= 0 || g_cvPrint.IntValue == 2)
	{
		SetHudTextParams(g_fPrintPos[0], g_fPrintPos[1], 5.0, g_iPrintColor[0], g_iPrintColor[1], g_iPrintColor[2], 255, 0, 0.0, 0.1, 0.1);

		for (int client = 1; client <= MaxClients; client++)
		{
			if (!IsValidClient(client))
				continue;

			if (bDynamicAvailable)
				ShowHudText(client, iHUDChannel, "%s", sBuffer);
			else
			{
				ClearSyncHud(client, g_hHudSync);
				ShowSyncHudText(client, g_hHudSync, "%s", sBuffer);
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

	if (g_bNemesis)
		CPrintToChat(client, "{darkred}[TopNemesis] {grey}%s", notifChatMsg);
	else
		CPrintToChat(client, "{darkblue}%t {grey}%s", "Chat Prefix", notifChatMsg);

	GiveGrenadesToClient(client, g_cvHENades.IntValue, g_bIsCSGO ? GrenadeType_HEGrenadeCSGO : GrenadeType_HEGrenade);
	if (g_bNemesis)
		GiveGrenadesToClient(client, g_cvSmokeNades.IntValue, g_bIsCSGO ? GrenadeType_SmokegrenadeCSGO : GrenadeType_Smokegrenade);

	if (g_iTopInfector[client] != 0 || g_bHideSkull[client])
		return;

	EmitSoundToClient(client, BELL_SOUND_COMMON, .volume=1.0);
	if (GetConVarInt(g_cvHat) == 1)
	{
		if (g_bIsCSGO)
		CreateHat_CSGO(client);
		else
		CreateHat_CSS(client);
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

	char sHudMsg[256], sNotifMsg[256];
	FormatEx(sHudMsg, sizeof(sHudMsg), "You have been rewarded grenades\nsince you were the Top %s last round!", g_bNemesis ? "Nemesis" : "Infector");
	FormatEx(sNotifMsg, sizeof(sNotifMsg), "You have been rewarded grenades since you were the Top %s last round!", g_bNemesis ? "Nemesis" : "Infector");
	SetPerks(client, sHudMsg, sNotifMsg);

	return Plugin_Continue;
}

//---------------------------------------
// Purpose: Menus
//---------------------------------------

public void CookieMenu_TopInfectors(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	switch(action)
	{
		case(CookieMenuAction_DisplayOption):
		{
			Format(buffer, maxlen, "%T", "Cookie Menu", client);
		}
		case(CookieMenuAction_SelectOption):
		{
			ShowSettingsMenu(client);
		}
	}
}

public void ShowSettingsMenu(int client)
{
	Menu menu = new Menu(MenuHandler_MainMenu, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);

	menu.SetTitle("%T", "Cookie Menu Title", client);

	AddMenuItemTranslated(menu, "0", "%t: %t", "Skull", g_bHideSkull[client]  ? "Disabled" : "Enabled");

	menu.ExitBackButton = true;
	menu.ExitButton = true;

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MainMenu(Menu menu, MenuAction action, int client, int selection)
{
	switch (action)
	{
		case (MenuAction_Select):
		{
			switch (selection)
			{
				case (0): ToggleSkull(client);
			}

			ShowSettingsMenu(client);
		}
		case (MenuAction_Cancel):
		{
			ShowCookieMenu(client);
		}
		case (MenuAction_End):
		{
			delete menu;
		}
	}
	return 0;
}

//---------------------------------------
// Purpose: Functions
//---------------------------------------

stock void Cleanup(bool bPluginEnd = false, bool bRoundEnd = false)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (bRoundEnd)
			g_iTopInfector[client] = -1;
		else
			g_iInfectCount[client] = 0;
	}

	if (bPluginEnd)
	{
		UnhookEvent("round_start", Event_OnRoundStart);
		UnhookEvent("round_end", Event_OnRoundEnd);
		UnhookEvent("player_spawn", Event_OnPlayerSpawn);
		UnhookEvent("player_death", Event_OnClientDeath);

		if (g_hHudSync != INVALID_HANDLE)
		{
			CloseHandle(g_hHudSync);
			g_hHudSync = INVALID_HANDLE;
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
				OnClientDisconnect(i);
		}
	}
}

stock void ToggleSkull(int client)
{
	g_bHideSkull[client] = !g_bHideSkull[client];
	if (g_bHideSkull[client] && IsValidClient(client) && IsPlayerAlive(client) && g_iTopInfector[client] == 0)
	{
		if (!g_bIsCSGO)
			RemoveHat_CSS(client);
		else
			RemoveHat_CSGO(client);
	}
	else if (!g_bHideSkull[client] && IsValidClient(client) && IsPlayerAlive(client) && g_iTopInfector[client] == 0)
	{
		if (GetConVarInt(g_cvHat) == 1)
		{
			if (g_bIsCSGO)
				CreateHat_CSGO(client);
			else
				CreateHat_CSS(client);
		}
	}

	CPrintToChat(client, "{darkblue}%t {grey}%t", "Chat Prefix", g_bHideSkull[client] ? "Skull Disabled" : "Skull Enabled");
}

stock void RemoveHat_CSS(int client)
{
	if (!g_bIsCSGO && g_iSkullEntity != INVALID_ENT_REFERENCE)
	{
		int iCrownEntity = EntRefToEntIndex(g_iSkullEntity);
		if(IsValidEntity(iCrownEntity))
			AcceptEntityInput(iCrownEntity, "Kill");
		g_iSkullEntity = INVALID_ENT_REFERENCE;
	}
}

stock void RemoveHat_CSGO(int client)
{
	RemoveHat_CSS(client);
}

void CreateHat_CSS(int client) 
{ 
	if ((g_iSkullEntity = EntIndexToEntRef(CreateEntityByName("prop_dynamic"))) == INVALID_ENT_REFERENCE)
		return;
	
	int iCrownEntity = EntRefToEntIndex(g_iSkullEntity);
	SetEntityModel(iCrownEntity, SKULL_MODEL_CSS);

	DispatchKeyValue(iCrownEntity, "solid",                 "0");
	DispatchKeyValue(iCrownEntity, "modelscale",            "1.3");
	DispatchKeyValue(iCrownEntity, "disableshadows",        "1");
	DispatchKeyValue(iCrownEntity, "disablereceiveshadows", "1");
	DispatchKeyValue(iCrownEntity, "disablebonefollowers",  "1");

	float fVector[3];
	float fAngles[3];
	GetClientAbsOrigin(client, fVector);
	GetClientAbsAngles(client, fAngles);

	fVector[2] += 80.0;
	fAngles[0] = 8.0;
	fAngles[2] = 5.5;

	TeleportEntity(iCrownEntity, fVector, fAngles, NULL_VECTOR);

	float fDirection[3];
	fDirection[0] = 0.0;
	fDirection[1] = 0.0;
	fDirection[2] = 1.0;

	TE_SetupSparks(fVector, fDirection, 1000, 200);
	TE_SendToAll();

	SetVariantString("!activator");
	AcceptEntityInput(iCrownEntity, "SetParent", client);
}

void CreateHat_CSGO(int client) 
{ 
	int m_iEnt = CreateEntityByName("prop_dynamic_override"); 
	DispatchKeyValue(m_iEnt, "model", SKULL_MODEL_CSGO); 
	DispatchKeyValue(m_iEnt, "spawnflags", "256"); 
	DispatchKeyValue(m_iEnt, "solid", "0");
	DispatchKeyValue(m_iEnt, "modelscale", "1.3");
	SetEntPropEnt(m_iEnt, Prop_Send, "m_hOwnerEntity", client); 

	float m_flPosition[3];
	float m_flAngles[3], m_flForward[3], m_flRight[3], m_flUp[3];
	GetClientAbsAngles(client, m_flAngles);
	GetAngleVectors(m_flAngles, m_flForward, m_flRight, m_flUp);
	GetClientEyePosition(client, m_flPosition);
	m_flPosition[2] += 7.0;

	DispatchSpawn(m_iEnt); 
	AcceptEntityInput(m_iEnt, "TurnOn", m_iEnt, m_iEnt, 0); 

	g_iEntIndex[client] = m_iEnt; 

	TeleportEntity(m_iEnt, m_flPosition, m_flAngles, NULL_VECTOR); 

	SetVariantString("!activator"); 
	AcceptEntityInput(m_iEnt, "SetParent", client, m_iEnt, 0); 

	SetVariantString(SKULL_MODEL_CSGO); 
	AcceptEntityInput(m_iEnt, "SetParentAttachmentMaintainOffset", m_iEnt, m_iEnt, 0);

	float fVector[3];
	GetClientAbsOrigin(client, fVector);

	fVector[2] += 80.0;

	float fDirection[3];
	fDirection[0] = 0.0;
	fDirection[1] = 0.0;
	fDirection[2] = 1.0;

	TE_SetupSparks(fVector, fDirection, 1000, 200);
	TE_SendToAll();
}

stock void GiveGrenadesToClient(int client, int iAmount, WeaponAmmoGrenadeType type)
{
	int iToolsAmmo = FindSendPropInfo("CBasePlayer", "m_iAmmo");
	if (iToolsAmmo != -1)
	{
		int iGrenadeCount = GetEntData(client, iToolsAmmo + (view_as<int>(type) * 4));
		SetEntData(client, iToolsAmmo + (view_as<int>(type) * 4), iGrenadeCount + iAmount, _, true);
	}
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
	int client = GetNativeCell(1);
	if (client && IsClientInGame(client))
	{
		return g_iTopInfector[client];
	}
	return -1;
}