#include <clientprefs>
#include <colors>
#include <sdktools>
#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <shop>
#include <vip_core>

#pragma newdecls required
#pragma semicolon 1

#define SKY_MAX 512

#define CPREFIX "{darkred}[{lime}SkyBox{darkred}]{default} "

char
	g_cFeature[] = "Skybox",
	g_sSkybox[SKY_MAX][64],
	g_sSkyboxName[SKY_MAX][128];

Handle
	g_hCookie_Sky,
	g_hCookie_Show;

KeyValues
	g_Kv;

Menu
	g_MenuChoose;

bool
	g_bShopLoaded[MAXPLAYERS + 1],
	g_bVIPLoaded[MAXPLAYERS + 1],
	g_bCookieLoaded[MAXPLAYERS + 1],
	g_bLateLoad,
	g_bVIPCore,
	g_bShopCore,
	g_bDontShow[MAXPLAYERS + 1],
	g_bSkyShop[SKY_MAX];

float g_fPlayerNextPreview[MAXPLAYERS + 1];
int g_iPlayerPreview[MAXPLAYERS + 1] = { -1, ... };
Handle g_hPlayerPreviewTimer[MAXPLAYERS + 1];

int
	g_iSelSB[MAXPLAYERS + 1],
	g_iSelected[MAXPLAYERS + 1],
	g_iPrice[SKY_MAX],
	g_iSellPrice[SKY_MAX],
	g_iDuration[SKY_MAX],
	g_iSkyCount;


ItemId
	g_iID[SKY_MAX] = { INVALID_ITEM, ... };
CategoryId
	g_iCategory_id;

ConVar
	CVARShop,
	CVARVIP,
	CVARPRCD,
	CVARPRTIME,
	g_CvarSkyName;

public Plugin myinfo =
{
	name        = "[VIP+SHOP] Skybox",
	description = "Allow players to choose skyboxes",
	author      = "NF & White Wolf & inklesspen",
	version     = "1.3.0",
	url         = "https://hlmod.ru/resources/shop-vip-skybox.3489/"


}

public APLRes
	AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;

	return APLRes_Success;
}

public void OnMapStart()
{
	char cBuffer[2048];

	// Skybox suffixes.
	static char suffix[][] = {
		"bk",
		"Bk",
		"dn",
		"Dn",
		"ft",
		"Ft",
		"lf",
		"Lf",
		"rt",
		"Rt",
		"up",
		"Up",
	};

	for (int j = 0; j < g_iSkyCount; j++)
	{
		for (int i = 0; i < sizeof(suffix); ++i)
		{
			FormatEx(cBuffer, sizeof(cBuffer), "materials/skybox/%s%s.vtf", g_sSkybox[j], suffix[i]);
			if (FileExists(cBuffer, false)) AddFileToDownloadsTable(cBuffer);

			FormatEx(cBuffer, sizeof(cBuffer), "materials/skybox/%s%s.vmt", g_sSkybox[j], suffix[i]);
			if (FileExists(cBuffer, false)) AddFileToDownloadsTable(cBuffer);
		}
	}
}

public void OnLibraryAdded(const char[] szName)
{
	if (StrEqual(szName, "vip_core") && CVARVIP.IntValue == 1) LoadVIPCore();
}

public void OnLibraryRemoved(const char[] szName)
{
	if (StrEqual(szName, "vip_core")) g_bVIPCore = false;
	if (StrEqual(szName, "shop")) g_bShopCore = false;
}

int GetSpectatorTarget(int client)
{
	int target;
	if (IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
		if (iObserverMode >= 3 && iObserverMode <= 7)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
			if (IsValidEntity(iTarget))
			{
				target = iTarget;
			}
		}
	}
	return target;
}

public void Shop_Started()
{
	LoadShopCore();
}

public void OnPluginStart()
{
	g_hCookie_Sky  = RegClientCookie("skybox_select", "Selected Skybox", CookieAccess_Public);
	g_hCookie_Show = RegClientCookie("skybox_show", "Show others' Skybox", CookieAccess_Public);

	g_CvarSkyName = FindConVar("sv_skyname");

	RegConsoleCmd("sm_sky", CmdSB);

	CVARPRCD = CreateConVar("sm_skybox_shop_preview_cooldown", "10", "Интервал между использованиями превью (0 - отключить)", _, true, 0.0);
	CVARPRTIME = CreateConVar("sm_skybox_shop_preview_time", "5", "Время использования превью (0 - непрерывно)", _, true, 0.0);
	(CVARShop = CreateConVar("sm_skybox_shop_use", "1", "Использовать ядро Shop.", _, true, 0.0, true, 1.0)).AddChangeHook(ChangeCvar_ShopCore);
	(CVARVIP = CreateConVar("sm_skybox_vip_use", "1", "Использовать ядро VIP.", _, true, 0.0, true, 1.0)).AddChangeHook(ChangeCvar_VIPCore);

	g_MenuChoose = new Menu(MenuChoose_Handler, MenuAction_Select | MenuAction_Cancel | MenuAction_DisplayItem | MenuAction_DrawItem);
	g_MenuChoose.SetTitle("Выберите небо");
	g_MenuChoose.AddItem("-1", "Стандартный");
	g_MenuChoose.ExitBackButton = true;

	LoadSkybox();

	AutoExecConfig(true, "skybox", "sourcemod");

	if (GetFeatureStatus(FeatureType_Native, "Shop_IsStarted") == FeatureStatus_Available && Shop_IsStarted()) Shop_Started();

	CreateTimer(0.5, Timer_DelayReload);
}

Action Timer_DelayReload(Handle hTimer)
{
	for (int i = 1; i < MAXPLAYERS + 1; i++)
		if (IsValidClient(i))
		{
			OnClientPostAdminCheck(i);
			g_bCookieLoaded[i] = true;
		}
}

int GetSelected(int iClient)
{
	if (hasRights(iClient, g_iSelected[iClient], true)) return g_iSelected[iClient];
	else return -1;
}

public void OnGameFrame()
{
	static int iClientCounter;
	iClientCounter++;
	if (iClientCounter > MAXPLAYERS) iClientCounter = 1;

	if (IsValidClient(iClientCounter))
	{
		UpdateClientSky(iClientCounter);
	}
}

Action Timer_DelayVIPCore(Handle hTimer)
{
	LoadVIPCore();
}

Action Timer_DelayShopCore(Handle hTimer)
{
	LoadShopCore();
}

void LoadVIPCore()
{
	if (!VIP_IsVIPLoaded()) CreateTimer(1.0, Timer_DelayVIPCore);
	if (g_bVIPCore) return;

	VIP_RegisterFeature(g_cFeature, STRING, SELECTABLE, OnSkyboxItemSelect);

	if (g_bLateLoad)
		for (int i = 1; i < MAXPLAYERS + 1; i++)
			if (IsValidClient(i)) VIP_OnClientLoaded(i, true);

	g_bVIPCore = true;
}

void UnloadVIPCore()
{
	if (!g_bVIPCore) return;

	VIP_UnregisterFeature(g_cFeature);

	g_bVIPCore = false;
}

void LoadShopCore()
{
	if (!Shop_IsStarted()) CreateTimer(1.0, Timer_DelayShopCore);

	if (g_bShopCore || CVARShop.IntValue == 0) return;

	g_iCategory_id = Shop_RegisterCategory("skybox", "Скайбоксы", "");

	for (int i = 0; i < g_iSkyCount; i++)
	{
		if (g_iPrice[i] > -1 && g_bSkyShop[i] && Shop_StartItem(g_iCategory_id, g_sSkybox[i]))
		{
			Shop_SetInfo(g_sSkyboxName[i], "Взгляни на небо по новому!", g_iPrice[i], g_iSellPrice[i], Item_Togglable, g_iDuration[i]);
			Shop_SetCallbacks(OnItemRegistered, OnEquipItem, .preview = Item_Preview);
			Shop_EndItem();
		}
	}
	if (g_bLateLoad)
		for (int i = 1; i < MAXPLAYERS + 1; i++)
			if (IsValidClient(i)) g_bShopLoaded[i] = true;

	g_bShopCore = true;
}

void UnloadShopCore()
{
	if (!g_bShopCore || !Shop_IsStarted()) return;
	Shop_UnregisterMe();
	g_bShopCore = false;
}

public void ChangeCvar_ShopCore(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar.IntValue == 1) LoadShopCore();
	else UnloadShopCore();
}

public void ChangeCvar_VIPCore(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar.IntValue == 1) LoadVIPCore();
	else UnloadVIPCore();
}

public Action CmdSB(int client, int args)
{
	DisplayMainMenu(client);

	char sVip[8192];
	VIP_GetClientFeatureString(client, g_cFeature, sVip, sizeof(sVip));

	PrintToConsole(client, "%s", sVip);
	return Plugin_Handled;
}

public void OnPluginEnd()
{
	UnloadShopCore();
	UnloadVIPCore();
}

bool IsValidClient(int client)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client)) return true;
	else return false;
}

int FindSkyIndex(const char[] sSky)
{
	for (int i; i < g_iSkyCount; i++)
		if (StrEqual(g_sSkybox[i], sSky)) return i;

	return -1;
}

public void OnItemRegistered(CategoryId category_id, const char[] sCategory, const char[] sItem, ItemId item_id)
{
	int index = FindSkyIndex(sItem);

	if (index > -1) g_iID[index] = item_id;
}

public ShopAction OnEquipItem(int iClient, CategoryId category_id, const char[] sCategory, ItemId item_id, const char[] sItem, bool isOn, bool elapsed)
{
	Shop_ToggleClientCategoryOff(iClient, g_iCategory_id);

	if (isOn || elapsed)
	{
		SetSkybox(iClient, -1);
		UpdateClientSky(iClient);
		return Shop_UseOff;
	}

	int index = FindSkyIndex(sItem);
	if (index <= -1)
	{
		LogError("Skybox (%s) registered in shop but is not exists", sItem);
		CPrintToChat(iClient, "{darkred}[{lime}SkyBox{darkred}]{default} Что-то пошло не так.");

		SetSkybox(iClient, -1);
		UpdateClientSky(iClient);
		return Shop_UseOff;
	}

	SetSkybox(iClient, index);
	RequestFrame(RequestUpdateClientSky, GetClientUserId(iClient));

	if (hasRights(iClient, index, false) == 1)
	{
		CPrintToChat(iClient, "{darkred}[{lime}SkyBox{darkred}]{default} Использован VIP-статус.");
		return Shop_UseOff;
	}

	return Shop_UseOn;
}

void RequestUpdateClientSky(int client) {
	client = GetClientOfUserId(client);
	if(client) {
		UpdateClientSky(client);
	}
}

public void PrintMes(int client, const char[] text)
{
	CPrintToChat(client, "{darkred}[{lime}SkyBox{darkred}]{default} %s", text);
}

public int hasRights(int client, int index, bool enabled)
{
	if (index == -1) return 0;

	if (g_bVIPCore)
	{
		char sVip[8192];
		VIP_GetClientFeatureString(client, g_cFeature, sVip, sizeof(sVip));

		if (StrContains(sVip, "SKY_ALL") > -1) return 1;
		if (StrContains(sVip, g_sSkyboxName[index]) > -1) return 1;
	}

	if (g_bShopCore)
	{
		if (Shop_IsClientHasItem(client, g_iID[index]) && (!enabled || Shop_IsClientItemToggled(client, g_iID[index]))) return 2;
	}

	return 0;
}

public Action Timer_Check(Handle timer, any client)
{
	if ((g_bShopLoaded[client] || !g_bShopCore) && (g_bVIPLoaded[client] || !g_bVIPCore)) OnPlayerJoin(client);

	else CreateTimer(2.0, Timer_Check, client);

	return Plugin_Handled;
}

public void OnClientPostAdminCheck(int client)
{
	UpdateClientSky(client);
	CreateTimer(2.0, Timer_Check, client);
}

public void OnClientConnected(int client)
{
	g_fPlayerNextPreview[client] = 0.0;
	g_iPlayerPreview[client]     = -1;
	g_hPlayerPreviewTimer[client] = null;
	g_iSelSB[client] = -2;
}

public void OnClientCookiesCached(int client)
{
	g_bCookieLoaded[client] = true;
}

public void OnClientDisconnect(int client)
{
	g_bShopLoaded[client]   = false;
	g_bCookieLoaded[client] = false;
	g_bVIPLoaded[client]    = false;

	if(g_hPlayerPreviewTimer[client]) {
		KillTimer(g_hPlayerPreviewTimer[client]);
		g_hPlayerPreviewTimer[client] = null;
	}
}

public void OnPlayerJoin(int client)
{
	char cInfo[64];
	GetClientCookie(client, g_hCookie_Sky, cInfo, sizeof(cInfo));
	if (cInfo[0] != NULL_STRING[0])
	{
		SetSkybox(client, StringToInt(cInfo));
	}
	else
	{
		SetClientCookie(client, g_hCookie_Sky, "-1");
		SetSkybox(client, -1);
	}
	GetClientCookie(client, g_hCookie_Show, cInfo, sizeof(cInfo));

	g_bDontShow[client] = view_as<bool>(StringToInt(cInfo));
}

public void Shop_OnAuthorized(int client)
{
	g_bShopLoaded[client] = true;
}

public void VIP_OnClientLoaded(int iClient, bool bIsVIP)
{
	g_bVIPLoaded[iClient] = true;
}

void DisplayChooseMenu(int client)
{
	g_MenuChoose.Display(client, MENU_TIME_FOREVER);
}

void DisplayMainMenu(int client)
{
	Menu g_MenuMain = new Menu(MenuMain_Handler);

	char sSelect[128];

	if (GetSelected(client) == -1) sSelect = "Стандарт";
	else FormatEx(sSelect, sizeof(sSelect), g_sSkyboxName[g_iSelected[client]]);
	Format(sSelect, sizeof(sSelect), "Меню SkyBox\n \nТекущее:\n   %s\n ", sSelect);

	g_MenuMain.SetTitle(sSelect);

	g_MenuMain.AddItem("select", "Выбор неба\n ");

	g_MenuMain.AddItem("shop", "Магазин\n   Приобрети и пользуйся!\n ");

	char sShow[64];

	if (!g_bDontShow[client]) sShow = "✔";
	else sShow = "✘";
	Format(sShow, sizeof(sShow), "Показывать чужое небо [%s]", sShow);

	g_MenuMain.AddItem("show", sShow);

	g_MenuMain.Display(client, MENU_TIME_FOREVER);
}

public bool OnSkyboxItemSelect(int client, const char[] cFeature)
{
	DisplayMainMenu(client);
	return false;
}

public int MenuChoose_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) DisplayMainMenu(param1);
		}
		case MenuAction_Select:
		{
			char cInfo[64];
			menu.GetItem(param2, cInfo, sizeof(cInfo));
			SetClientCookie(param1, g_hCookie_Sky, cInfo);
			int index  = StringToInt(cInfo);
			if(index == -1) {
				SetSkybox(param1, index);
				UpdateClientSky(param1);
			} else {
				int rights = hasRights(param1, index, false);
				if (rights > 0)
				{
					if (rights == 2) // shop
					{
						Shop_ToggleClientCategoryOff(param1, g_iCategory_id);
						Shop_ToggleClientItem(param1, g_iID[index], Toggle_On);
					}
					else { // vip
						SetSkybox(param1, index);
						UpdateClientSky(param1);
					}
				}
			}
			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
		}
		case MenuAction_DisplayItem:
		{
			char cInfo[64], cDisplay[64];
			menu.GetItem(param2, cInfo, sizeof(cInfo), _, cDisplay, sizeof(cDisplay));

			if (g_iSelected[param1] == StringToInt(cInfo))
			{
				StrCat(cDisplay, sizeof(cDisplay), "[X]");
				return RedrawMenuItem(cDisplay);
			}

			return 0;
		}
		case MenuAction_DrawItem:
		{
			char cInfo[64];
			menu.GetItem(param2, cInfo, sizeof(cInfo));
			int iInfo = StringToInt(cInfo);
			if (iInfo == -1 || hasRights(param1, iInfo, false))
				return (g_iSelected[param1] == iInfo) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
			else return ITEMDRAW_RAWLINE;
		}
	}

	return 0;
}

public int MenuMain_Handler(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char cInfo[64];
			bool bShow = true;
			menu.GetItem(param2, cInfo, sizeof(cInfo));

			if (StrEqual(cInfo, "show"))
			{
				g_bDontShow[client] = !g_bDontShow[client];

				if (g_bDontShow[client]) SetClientCookie(client, g_hCookie_Show, "1");
				else SetClientCookie(client, g_hCookie_Show, "0");
			}

			if (StrEqual(cInfo, "select"))
			{
				bShow = false;
				DisplayChooseMenu(client);
			}

			if (StrEqual(cInfo, "shop"))
			{
				bShow = false;
				GoToShop(client);
			}

			if (bShow) DisplayMainMenu(client);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}

	return 0;
}

void GoToShop(int client)
{
	if (g_bShopCore) Shop_ShowItemsOfCategory(client, g_iCategory_id);
}

void UpdateClientSky(int client)
{
	if(!IsValidClient(client))	return;

	if (g_iPlayerPreview[client] != -1)
	{
		ShowSky(client, g_iPlayerPreview[client]);
	}
	else {
		int iSky = GetSelected(client);

		if (!IsPlayerAlive(client) && !g_bDontShow[client])
		{
			int spec = GetSpectatorTarget(client);
			if (IsValidClient(spec))
			{
				iSky = GetSelected(spec);
			}
		}
		ShowSky(client, iSky);
	}
}

void ShowSky(int iClient, int iSky)
{
	if (g_iSelSB[iClient] == iSky || IsFakeClient(iClient)) return;
	g_iSelSB[iClient] = iSky;
	if (iSky == -1)
	{
		char cBuffer[64];
		SetEntProp(iClient, Prop_Send, "m_skybox3d.area", 0);
		g_CvarSkyName.GetString(cBuffer, sizeof(cBuffer));
		g_CvarSkyName.ReplicateToClient(iClient, cBuffer);
	}
	else
	{
		SetEntProp(iClient, Prop_Send, "m_skybox3d.area", 255);
		g_CvarSkyName.ReplicateToClient(iClient, g_sSkybox[iSky]);
	}
}

void SetSkybox(int iClient, int iSky)
{
	g_iSelected[iClient] = iSky;
}

void Item_Preview(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item)
{
	int sky = FindSkyIndex(item);

	if(sky <= -1) {
		LogError("Skybox (%s) registered in shop but is not exists", item);
		CPrintToChat(client, CPREFIX..."Что-то пошло не так.");
		return;
	}

	if(g_iPlayerPreview[client] != -1) {
		g_iPlayerPreview[client] = -1;
		if(g_hPlayerPreviewTimer[client]) {
			KillTimer(g_hPlayerPreviewTimer[client]);
			g_hPlayerPreviewTimer[client] = null;
		}
		g_fPlayerNextPreview[client] = GetGameTime() + CVARPRCD.FloatValue;
		UpdateClientSky(client);
		return;
	}

	if(g_fPlayerNextPreview[client] > GetGameTime()) {
		int timeleft = RoundToCeil(g_fPlayerNextPreview[client] - GetGameTime());
		CPrintToChat(client, CPREFIX..."Функция будет доступна через %d секунд.", timeleft);
		return;
	}

	g_iPlayerPreview[client] = sky;
	float time = CVARPRTIME.FloatValue;
	if(time > 0.0) {
		g_hPlayerPreviewTimer[client] = CreateTimer(time, Timer_ResetPreview, client);
	}
	UpdateClientSky(client);
}

public Action Timer_ResetPreview(Handle plugin, int client) {
	g_hPlayerPreviewTimer[client] = null;
	g_iPlayerPreview[client] = -1;
	g_fPlayerNextPreview[client] = GetGameTime() + CVARPRCD.FloatValue;
	UpdateClientSky(client);
}

void LoadSkybox()
{
	g_Kv = new KeyValues("Skybox");
	char cBuffer[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, cBuffer, sizeof(cBuffer), "configs/skybox.ini");

	if (!g_Kv.ImportFromFile(cBuffer))
	{
		delete g_Kv;
		SetFailState("Failed to read from file \"%s\"", cBuffer);
	}
	g_Kv.Rewind();

	if (g_Kv.GotoFirstSubKey())
	{
		char cPath[64];

		do
		{
			g_Kv.GetSectionName(cBuffer, sizeof(cBuffer));
			g_Kv.GetString("path", cPath, sizeof(cPath));
			char sIndex[8];
			FormatEx(sIndex, sizeof(sIndex), "%u", g_iSkyCount);
			g_MenuChoose.AddItem(sIndex, cBuffer);
			FormatEx(g_sSkybox[g_iSkyCount], 64, "%s", cPath);
			FormatEx(g_sSkyboxName[g_iSkyCount], 128, "%s", cBuffer);

			g_bSkyShop[g_iSkyCount] = !!g_Kv.GetNum("shop", 1);
			g_iPrice[g_iSkyCount]     = g_Kv.GetNum("price");
			g_iSellPrice[g_iSkyCount] = g_Kv.GetNum("sellprice");
			g_iDuration[g_iSkyCount]  = g_Kv.GetNum("duration");

			g_iSkyCount++;
		}
		while (g_Kv.GotoNextKey());
	}

	g_Kv.Rewind();
}