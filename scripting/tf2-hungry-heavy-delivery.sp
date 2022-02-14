/*
////////////////////////////////////////////////
TODO LIST:

* Add chat messages and center messages stating new users who are in the lead or users who are catching up to your score.
* Figure out a method for a catchup mechanic for players.
* Add code to remove any inputs on all trigger_multiple entities with 'pizza_delivery_' as the starting prefix as a safety check.
* Fix the mutations format having a comma at the start if only one mutation is active.

*/

//Pragma
#pragma semicolon 1
#pragma newdecls required

//Defines
#define PLUGIN_DESCRIPTION "A new gamemode revolved around delivering pizzas."
#define PLUGIN_VERSION "1.1.3"
#define PLUGIN_TAG "[HHD]"
#define PLUGIN_TAG_COLORED "{crimson}[HHD]{beige}"

#define PIZZA_MODEL "models/pizza_bag/pizzabag.mdl"

#define GAMEMODE_TYPES 5
#define GAMEMODE_TYPE_NONE -1
#define GAMEMODE_TYPE_RANDOM 0
#define GAMEMODE_TYPE_NORMAL 1
#define GAMEMODE_TYPE_ELIMINATION 2
#define GAMEMODE_TYPE_TEAMS 3
#define GAMEMODE_TYPE_RESETONDEATH 4
#define GAMEMODE_TYPE_BUNNYHOPPING 5

#define MUTATION_DOUBLEVELOCITY 0
#define MUTATION_SUPREMEPIZZAS 1
#define MUTATION_GPSMALFUNCTION 2
#define MUTATIONS_TOTAL 3

#define OVERLAY_TUTORIAL_01 "overlays/HHD/tutorial_01"
#define OVERLAY_TUTORIAL_02 "overlays/HHD/tutorial_02"
#define OVERLAY_TUTORIAL_03 "overlays/HHD/tutorial_03"
#define OVERLAY_TUTORIAL_04 "overlays/HHD/tutorial_04"
#define OVERLAY_TUTORIAL_05 "overlays/HHD/tutorial_05"

#define TUTORIAL_STEP_NONE		0
#define TUTORIAL_STEP_PISTOL	1
#define TUTORIAL_STEP_FAN		2
#define TUTORIAL_STEP_CLIMB		3
#define TUTORIAL_STEP_DELIVERY	4
#define TUTORIAL_STEP_FINISH	5

//Flag Info
#define TF_FLAGINFO_NONE 0
#define TF_FLAGINFO_STOLEN (1<<0)
#define TF_FLAGINFO_DROPPED (1<<1)

//Sourcemod Includes
#include <sourcemod>

#include <misc-sm>
#include <misc-colors>
#include <misc-tf>

#include <clientprefs>
#include <tf2items>

//ConVars
ConVar convar_Default_Time;
ConVar convar_Velocity_Primary;
ConVar convar_Velocity_Primary_Double;
ConVar convar_Velocity_Melee;
ConVar convar_Velocity_Melee_Double;
ConVar convar_Velocity_Melee_Climb;
ConVar convar_Velocity_Melee_Climb_Double;

//Cookies
Handle g_hCookie_ToggleMusic;
Handle g_hCookie_Tutorial;
Handle g_hCookie_TutorialPlayed;
Handle g_hCookie_IsFemale;

//Globals
Database g_Database;
char sCurrentMap[32];
bool g_bLate;
bool g_bBetweenRounds;
bool g_bPlayersFrozen;
bool g_bWaitingForPlayers;
Handle g_hSecondsTimer;
Handle g_hMillisecondsTimer;

enum struct Player
{
	int client;

	bool connected;
	int triggerdelay;
	bool isfemale;

	bool backgroundmusic;
	Handle backgroundmusictimer;

	bool supreme;

	int pizza;
	int destination;
	int laststop;

	int totalpizzas;
	int climbs;

	void Init(int client)
	{
		this.client = client;

		this.connected = false;
		this.triggerdelay = -1;
		this.isfemale = false;

		this.backgroundmusic = false;
		this.backgroundmusictimer = null;

		this.supreme = false;

		this.pizza = -1;
		this.destination = -1;
		this.laststop = -1;

		this.totalpizzas = -1;
		this.climbs = -1;
	}
}

Player g_Player[MAXPLAYERS + 1];

enum struct Airtime
{
	int secondaryshots;
	float starttime;
	float topspeed;
	bool timing;
	int offgrounddelay;
	float currentairtimerecord;
	float roundairtimerecord;
	int currentdeliveriesrecord;
	int rounddeliveriesrecord;
	int lastpositivemessage;
	int lastnegativemessage;
	int spritetrail;
	Handle airtimesound;
	bool recordcache;
}

Airtime g_Airtime[MAXPLAYERS + 1];

enum struct Tutorial
{
	int tutorialstep;
	int climbamount;
	Handle tutorialtimer;
	bool tutorialplayed;
	int flashtext;
}

Tutorial g_Tutorial[MAXPLAYERS + 1];

//Background Music
ArrayList g_BackgroundMusic;
ArrayList g_BackgroundMusicSeconds;

//Gamemode Rules
int g_iGamemodeType;
int g_iQueuedGamemode;
Handle g_hSync_Mode;

//Mutations
bool g_bMutations[MUTATIONS_TOTAL];	//Mutations are random gameplay elements.

//Timer
int g_iRemainingTime;
Handle g_hSync_RemainingTime;

//Pizza Delivery
Handle g_hSDKPickup;
Handle g_hSync_Score;

//Delivery Stops
Handle g_hSync_Destination;

//Beam tempent materials
int g_iLaserMaterial;
int g_iHaloMaterial;

//Weapons
Handle wep_primary;
Handle wep_secondary;
Handle wep_melee;

//Ledge Grabbing
bool g_bHanging[MAXPLAYERS + 1];
float g_vecClimbPos[MAXPLAYERS + 1][3];

public Plugin myinfo =
{
	name = "Hungry Heavy Delivery",
	author = "Keith Warren (Drixevel)",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://www.vertexheights.com/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	convar_Default_Time = CreateConVar("sm_hhd_default_time", "300");
	convar_Velocity_Primary = CreateConVar("sm_hhd_primary_vel", "3250");
	convar_Velocity_Primary_Double = CreateConVar("sm_hhd_primary_vel_double", "3500");
	convar_Velocity_Melee = CreateConVar("sm_hhd_melee_vel", "1750.0");
	convar_Velocity_Melee_Double = CreateConVar("sm_hhd_melee_vel_double", "1500.0");
	convar_Velocity_Melee_Climb = CreateConVar("sm_hhd_melee_vel_climb", "4000.0");
	convar_Velocity_Melee_Climb_Double = CreateConVar("sm_hhd_melee_vel_climb_double", "5000.0");

	RegConsoleCmd("sm_mainmenu", Command_MainMenu, "Open the main menu for Hungry Heavy Delivery.");
	RegConsoleCmd("sm_menu", Command_MainMenu, "Open the main menu for Hungry Heavy Delivery.");
	RegConsoleCmd("sm_gender", Command_ToggleGender, "Toggle gender to male or female.");
	RegConsoleCmd("sm_togglegender", Command_ToggleGender, "Toggle gender to male or female.");
	RegConsoleCmd("sm_credits", Command_ShowCredits, "Show the credits for the mod as a whole.");
	RegConsoleCmd("sm_records", Command_Records, "Opens and displays top records.");
	RegConsoleCmd("sm_topairtime", Command_TopAirtimes, "Open and displays the top airtimes for this map.");
	RegConsoleCmd("sm_topdeliveries", Command_TopDeliveries, "Open and displays the top deliveries for this map.");
	RegConsoleCmd("sm_music", Command_ToggleMusic, "Toggle music on and off.");
	RegConsoleCmd("sm_togglemusic", Command_ToggleMusic, "Toggle music on and off.");
	RegConsoleCmd("sm_resetairtime", Command_ResetAirtimeRecord, "Resets your top record for this map.");
	RegConsoleCmd("sm_resetdeliveries", Command_ResetDeliveryRecord, "Resets your top deliveries for this map.");
	RegConsoleCmd("sm_tutorial", Command_Tutorial, "A tutorial to show you how to play.");

	RegAdminCmd("sm_setgamemode", Command_SetGamemode, ADMFLAG_SLAY, "Queue the gamemode for next round.");
	RegAdminCmd("sm_queuegamemode", Command_SetGamemode, ADMFLAG_SLAY, "Queue the gamemode for next round.");
	RegAdminCmd("sm_setmutation", Command_SetMutations, ADMFLAG_SLAY, "Toggle any mutations for the current round.");
	RegAdminCmd("sm_setmutations", Command_SetMutations, ADMFLAG_SLAY, "Toggle any mutations for the current round.");
	RegAdminCmd("sm_endgame", Command_EndGame, ADMFLAG_SLAY, "Ends the current round.");

	g_BackgroundMusic = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_BackgroundMusicSeconds = new ArrayList();

	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("post_inventory_application", Event_OnResupply);
	HookEvent("teamplay_round_start", Event_OnTeamplayRoundStart);
	HookEvent("teamplay_round_active", Event_OnTeamplayRoundActive);
	HookEvent("teamplay_waiting_ends", Event_OnTeamplayWaitingEnds);
	HookEvent("teamplay_round_win", Event_OnTeamplayRoundWin);
	HookEvent("teamplay_flag_event", Event_OnTeamplayFlagEvent, EventHookMode_Pre);

	AddCommandListener(Listener_DropIntel, "dropitem");
	AddCommandListener(Listener_ChangeClass, "changeclass");
	AddCommandListener(Listener_ChangeClass, "join_class");

	AddNormalSoundHook(OnSoundPlay);

	g_hCookie_ToggleMusic = RegClientCookie("hhd_toggle_music", "Whether they want music to play or not.", CookieAccess_Public);
	g_hCookie_Tutorial = RegClientCookie("hhd_shown_tutorial", "Whether to show the tutorial menu to the client.", CookieAccess_Public);
	g_hCookie_TutorialPlayed = RegClientCookie("hhd_shown_tutorial_played", "Whether or not this player has played the tutorial.", CookieAccess_Protected);
	g_hCookie_IsFemale = RegClientCookie("hhd_is_female", "Whether or not the player is female.", CookieAccess_Public);

	g_hSync_Mode = CreateHudSynchronizer();
	g_hSync_RemainingTime = CreateHudSynchronizer();
	g_hSync_Score = CreateHudSynchronizer();
	g_hSync_Destination = CreateHudSynchronizer();

	//We create the weapon handles here for multi-usage later.
	wep_primary = TF2Items_CreateItem(OVERRIDE_ALL);
	TF2Items_SetClassname(wep_primary, "tf_weapon_scattergun");
	TF2Items_SetItemIndex(wep_primary, 45);
	TF2Items_SetNumAttributes(wep_primary, 10);					//JESUS
	TF2Items_SetAttribute(wep_primary, 0, 44, 0.0);				//FUCKME
	TF2Items_SetAttribute(wep_primary, 1, 6, 0.5);				//FUCKME
	TF2Items_SetAttribute(wep_primary, 2, 45, 1.2);				//FUCKME
	TF2Items_SetAttribute(wep_primary, 3, 1, 0.9);				//FUCKME
	TF2Items_SetAttribute(wep_primary, 4, 3, 0.34);				//FUCKME
	TF2Items_SetAttribute(wep_primary, 5, 43, 1.0);				//FUCKME
	TF2Items_SetAttribute(wep_primary, 6, 328, 1.0);			//FUCKME
	TF2Items_SetAttribute(wep_primary, 7, 4, 1.50);				//FUCKME
	TF2Items_SetAttribute(wep_primary, 8, 76, 4.0);				//FUCKME
	TF2Items_SetAttribute(wep_primary, 9, 318, 0.75);			//FUCKME

	wep_secondary = TF2Items_CreateItem(OVERRIDE_ALL);
	TF2Items_SetClassname(wep_secondary, "tf_weapon_pistol");
	TF2Items_SetItemIndex(wep_secondary, 23);
	TF2Items_SetNumAttributes(wep_secondary, 3);					//JESUS
	TF2Items_SetAttribute(wep_secondary, 0, 4, 3.0);				//FUCKME
	TF2Items_SetAttribute(wep_secondary, 1, 78, 5.0);				//FUCKME
	TF2Items_SetAttribute(wep_secondary, 2, 318, 1.50);				//FUCKME

	wep_melee = TF2Items_CreateItem(OVERRIDE_ALL);
	TF2Items_SetClassname(wep_melee, "tf_weapon_bat");
	TF2Items_SetItemIndex(wep_melee, 0);

	Handle hConf = LoadGameConfigFile("hhd.gamedata");

	if (hConf != null)
	{
		//Due to how we have to use the 'item_teamflag' entity for the pizza model to work, we have to force them to pick it up with this.
		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CCaptureFlag::PickUp");
		PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
		PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
		g_hSDKPickup = EndPrepSDKCall();

		delete hConf;
	}
	else
		LogError("Error parsing file: hhd.gamedata.txt");
	
	//It'd probably be better to setup code to get the seconds of a track automatically instead of caching that as well but I have yet to find a method that doesn't crash.
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_electric_tooth_brush.mp3");
	g_BackgroundMusicSeconds.Push(256.0);
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_everybody_jump_around.mp3");
	g_BackgroundMusicSeconds.Push(249.0);
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_funky_radio.mp3");
	g_BackgroundMusicSeconds.Push(207.0);
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_jet_grind_radio.mp3");
	g_BackgroundMusicSeconds.Push(250.0);
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_moodys_shuffle.mp3");
	g_BackgroundMusicSeconds.Push(78.8);
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_ok_house.mp3");
	g_BackgroundMusicSeconds.Push(318.0);
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_sneakman.mp3");
	g_BackgroundMusicSeconds.Push(233.0);
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_super_brothers.mp3");
	g_BackgroundMusicSeconds.Push(179.0);
	g_BackgroundMusic.PushString("hungryheavydelivery/music/jsr_thats_enough.mp3");
	g_BackgroundMusicSeconds.Push(225.0);

	Database.Connect(OnSQLConnect, "default");
}

public void OnConfigsExecuted()
{
	FindConVar("tf_scout_air_dash_count").IntValue = 1;	//Setting it to three allows for pizza deliveries while maintaining airtime.
	FindConVar("sv_airaccelerate").IntValue = 100;		//Turning in midair or bunnyhopping properly basically requires this to be high.

	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
				OnClientConnected(i);
			
			if (!IsClientInGame(i))
				continue;
			
			OnClientPutInServer(i);

			if (IsPlayerAlive(i))
				SetSpawnFunctions(i);

			if (AreClientCookiesCached(i))
				OnClientCookiesCached(i);
		}

		int entity = -1; char classname[64];
		while ((entity = FindEntityByClassname(entity, "*")) != -1)
			if (GetEntityClassname(entity, classname, sizeof(classname)))
				OnEntityCreated(entity, classname);

		g_bLate = false;
	}
}

public void OnSQLConnect(Database db, const char[] error, any data)
{
	if (db == null)
		ThrowError("Error connecting to database: %s", error);

	g_Database = db;
	LogMessage("Connected to database successfully.");

	g_Database.Query(onCreateTable, "CREATE TABLE IF NOT EXISTS `hungry_heavy_delivery_records` ( `id` INT NOT NULL AUTO_INCREMENT , `name` VARCHAR(64) NOT NULL DEFAULT '' , `steamid` VARCHAR(32) NOT NULL DEFAULT '' , `record_airtime` FLOAT NOT NULL DEFAULT '0.0' , `record_deliveries` INT(12) NOT NULL DEFAULT '0' , `map` VARCHAR(32) NOT NULL DEFAULT '', PRIMARY KEY (`id`), UNIQUE KEY `unique_index` ( `steamid`, `map`)) ENGINE = InnoDB;");

	char sSteamID[32];
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientAuthorized(i) && GetClientAuthId(i, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
			OnClientAuthorized(i, sSteamID);
}

public void onCreateTable(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
		ThrowError("Error while creating table: %s", error);
}

public void OnMapStart()
{
	GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));
	GetMapDisplayName(sCurrentMap, sCurrentMap, sizeof(sCurrentMap));	//Required to work with workshop maps properly.

	PrecacheSound("ambient/desert_wind.wav");		//While flying through the air.
	PrecacheSound("coach/coach_student_died.wav");	//If you die while airtime is active.
	PrecacheSound("ui/hitsound_beepo.wav");			//Plays when you climb with your melee.
	PrecacheSound("ui/duel_score_behind.wav");		//Plays when you complete the climbing segment of the tutorial.

	//TempEnt Files
	g_iLaserMaterial = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloMaterial = PrecacheModel("materials/sprites/halo01.vmt");

	//Pizza Bag Model
	PrecacheModel(PIZZA_MODEL);
	AddFileToDownloadsTable(PIZZA_MODEL);
	AddFileToDownloadsTable("models/pizza_bag/pizzabag.dx80.vtx");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag.dx90.vtx");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag.phy");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag.sw.vtx");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag.vvd");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag01.vmt");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag01.vtf");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag01_phongexponent.vtf");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag02.vmt");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag02.vtf");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag03.vmt");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag03.vtf");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag04.vmt");
	AddFileToDownloadsTable("materials/models/pizza_bag/pizza_bag04.vtf");
	//Neutral pizza model, not much of a need for it but just in case.
	/* AddFileToDownloadsTable("models/pizza_bag/pizzabag_ntr.dx80.vtx");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag_ntr.dx90.vtx");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag_ntr.mdl");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag_ntr.phy");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag_ntr.sw.vtx");
	AddFileToDownloadsTable("models/pizza_bag/pizzabag_ntr.vvd"); */

	//This sound plays on join.
	PrecacheSound("hungryheavydelivery/jsr_groove_2.mp3");
	AddFileToDownloadsTable("sound/hungryheavydelivery/jsr_groove_2.mp3");

	//Background Music
	char sMusic[PLATFORM_MAX_PATH];
	for (int i = 0; i < g_BackgroundMusic.Length; i++)
	{
		g_BackgroundMusic.GetString(i, sMusic, sizeof(sMusic));
		PrecacheSound(sMusic);
		Format(sMusic, sizeof(sMusic), "sound/%s", sMusic);
		AddFileToDownloadsTable(sMusic);
	}

	//Tutorial Files
	PrecacheDecalAnyDownload(OVERLAY_TUTORIAL_01);
	PrecacheDecalAnyDownload(OVERLAY_TUTORIAL_02);
	PrecacheDecalAnyDownload(OVERLAY_TUTORIAL_03);
	PrecacheDecalAnyDownload(OVERLAY_TUTORIAL_04);
	PrecacheDecalAnyDownload(OVERLAY_TUTORIAL_05);

	//Female Model
	PrecacheModel("models/player/scout_female.mdl");
	AddFileToDownloadsTable("models/player/scout_female.mdl");
	AddFileToDownloadsTable("models/player/scout_female.dx80.vtx");
	AddFileToDownloadsTable("models/player/scout_female.dx90.vtx");
	AddFileToDownloadsTable("models/player/scout_female.phy");
	AddFileToDownloadsTable("models/player/scout_female.sw.vtx");
	AddFileToDownloadsTable("models/player/scout_female.vvd");
	AddFileToDownloadsTable("materials/models/player/female_scout/eyeball_invun.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/eyeball_l.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/eyeball_r.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/eyeball_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/necklace_blue.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/necklace_red.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_gib.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_gib.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_invun.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_invun.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_invun_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_zombie.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_zombie_alphatest.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_blue_zombie_orig.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_hands.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_hands.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_hands_normal.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_hands_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head_blue_invun.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head_blue_invun.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head_blue_invun_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head_red_invun.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head_red_invun.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head_red_invun_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_head_zombie.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_normal.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_normal_gib.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_gib.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_gib.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_invun.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_invun.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_invun_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_zombie.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_zombie.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_zombie_alphatest.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_red_zombie_orig.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_shirt_blu.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_shirt_blu.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_shirt_red.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_shirt_red.vtf");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_tats.vmt");
	AddFileToDownloadsTable("materials/models/player/female_scout/scout_tats.vtf");

	//female_scout sounds
	char sFile[PLATFORM_MAX_PATH];
	FileType type;

	DirectoryListing dir = OpenDirectory("sound/vo/female_scout/", true);

	if (dir != null)
	{
		while (dir.GetNext(sFile, sizeof(sFile), type))
		{
			if (StrEqual(sFile, ".") || StrEqual(sFile, "..") || type == FileType_Directory)
				continue;
			
			TrimString(sFile);

			Format(sFile, sizeof(sFile), "vo/female_scout/%s", sFile);
			PrecacheSound(sFile);

			Format(sFile, sizeof(sFile), "sound/%s", sFile);
			AddFileToDownloadsTable(sFile);
		}

		delete dir;
	}
	else
		LogError("Directory not found: sound/vo/female_scout/");

	dir = OpenDirectory("sound/vo/female_scout/taunts/", true);

	if (dir != null)
	{
		while (dir.GetNext(sFile, sizeof(sFile), type))
		{
			if (StrEqual(sFile, ".") || StrEqual(sFile, "..") || type == FileType_Directory)
				continue;

			TrimString(sFile);

			Format(sFile, sizeof(sFile), "vo/female_scout/taunts/%s", sFile);
			PrecacheSound(sFile);

			Format(sFile, sizeof(sFile), "sound/%s", sFile);
			AddFileToDownloadsTable(sFile);
		}

		delete dir;
	}
	else
		LogError("Directory not found: sound/vo/female_scout/taunts/");
}

void PrecacheDecalAnyDownload(char[] sOverlay)
{
	char sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "%s.vmt", sOverlay);
	PrecacheDecal(sBuffer, true);
	Format(sBuffer, sizeof(sBuffer), "materials/%s.vmt", sOverlay);
	AddFileToDownloadsTable(sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%s.vtf", sOverlay);
	PrecacheDecal(sBuffer, true);
	Format(sBuffer, sizeof(sBuffer), "materials/%s.vtf", sOverlay);
	AddFileToDownloadsTable(sBuffer);
}

public Action Listener_DropIntel(int client, const char[] command, int argc)
{
	return Plugin_Handled;
}

public Action Listener_ChangeClass(int client, const char[] command, int argc)
{
	//We make sure they're alive here otherwise spawn problems occur.
	return IsPlayerAlive(client) ? Plugin_Handled : Plugin_Continue;
}

public Action OnSoundPlay(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	//They aren't picking up the intel, no need for this.
	if (StrContains(sample, "vo/intel_") != -1)
		return Plugin_Stop;

	if (IsPlayerIndex(entity) && StrContains(sample, "vo/scout_") == 0 && g_Player[entity].isfemale)
	{
		char sBuffer[2][512];
		ExplodeString(sample, "/", sBuffer, 2, 512);
		strtolower(sBuffer[1], sBuffer[1], 512);

		FormatEx(sample, PLATFORM_MAX_PATH, "vo/female_scout/%s", sBuffer[1]);
		ReplaceString(sample, PLATFORM_MAX_PATH, ".mp3", ".wav");

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		KillPizzaBackpack(i);
		ClearSyncHud(i, g_hSync_Mode);
		ClearSyncHud(i, g_hSync_RemainingTime);
		ClearSyncHud(i, g_hSync_Score);
		ClearSyncHud(i, g_hSync_Destination);
		StopBackgroundMusic(i);
		ClearOverlay(i);
	}
}

public Action Timer_TicksInSeconds(Handle timer)
{
	if (g_bBetweenRounds || g_bWaitingForPlayers)
		return Plugin_Continue;

	char sTime[32]; char sRecord[64]; float speed;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			speed = GetPlayerSpeed(i);

			sTime[0] = '\0';
			sRecord[0] = '\0';

			if (g_Airtime[i].timing)
			{
				FormatPlayerTime(GetEngineTime() - g_Airtime[i].starttime, sTime, sizeof(sTime), true, 1);
				Format(sTime, sizeof(sTime), " | Airtime: %s", sTime);
			}

			if (g_Airtime[i].currentairtimerecord > 0.0)
				FormatEx(sRecord, sizeof(sRecord), " | Airtime Record: %.2f", g_Airtime[i].currentairtimerecord);

			PrintHintText(i, "Speed: %.2f%s%s", speed, sRecord, strlen(sTime) > 0 ? sTime : "");
			StopSound(i, SNDCHAN_STATIC, "UI/hint.wav");
		}
	}

	if (g_iRemainingTime <= 0)
	{
		int winner = GetGameWinner();
		TFTeam winning_team = TFTeam_Unassigned;

		if (IsPlayerIndex(winner))
		{
			CPrintToChatAll("%s %N has won employee of the round with %i pizzas!", PLUGIN_TAG_COLORED, winner, g_Player[winner].totalpizzas);
			winning_team = TF2_GetClientTeam(winner);

			char sWinning[PLATFORM_MAX_PATH];
			FormatEx(sWinning, sizeof(sWinning), "vo/heavy_yes0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToClientSafeDelayed(winner, sWinning, 2.5);
		}
		else
		{
			CPrintToChatAll("%s ALL EMPLOYEES ARE FIRED!", PLUGIN_TAG_COLORED);
			EmitSoundToAllSafeDelayed(GetRandomInt(0, 1) == 0 ? "vo/heavy_battlecry03.mp3" : "vo/heavy_battlecry05.mp3", 1.5);
		}

		if (winning_team != TFTeam_Unassigned)
		{
			char sThanks[PLATFORM_MAX_PATH];
			FormatEx(sThanks, sizeof(sThanks), "vo/heavy_thanks0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToAllSafeDelayed(sThanks, 5.0);
		}

		g_iRemainingTime = 0;
		TF2_ForceWin(winning_team);
	}

	g_iRemainingTime--;

	if (g_iGamemodeType == GAMEMODE_TYPE_TEAMS)
	{
		if (g_iRemainingTime == 300)
			EmitSoundToAllSafe("vo/announcer_ends_5min.mp3");
		else if (g_iRemainingTime == 120)
			EmitSoundToAllSafe("vo/announcer_ends_2min.mp3");
		else if (g_iRemainingTime == 60)
			EmitSoundToAllSafe("vo/announcer_ends_60sec.mp3");
		else if (g_iRemainingTime == 30)
			EmitSoundToAllSafe("vo/announcer_ends_30sec.mp3");
		else if (g_iRemainingTime <= 10)
		{
			char sSound[PLATFORM_MAX_PATH];
			FormatEx(sSound, sizeof(sSound), "vo/announcer_ends_%isec.mp3", g_iRemainingTime);
			EmitSoundToAllSafe(sSound);
		}
	}

	return Plugin_Continue;
}

public Action Timer_TicksInMilliseconds(Handle timer)
{
	if (g_bBetweenRounds || g_bWaitingForPlayers)
		return Plugin_Continue;

	char sGamemode[64]; char sTime[32]; char sDestination[64]; char sArrow[12]; char sRecord[32];
	int entity; float vecOrigin[3]; float vecAngles[3]; float destOrigin[3];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			GetClientAbsOrigin(i, vecOrigin);
			GetClientAbsAngles(i, vecAngles);

			sGamemode[0] = '\0';
			sTime[0] = '\0';
			sDestination[0] = '\0';
			sArrow[0] = '\0';
			sRecord[0] = '\0';

			if (IsValidEntity(g_Player[i].destination))
			{
				entity = g_Player[i].destination;

				if (IsValidEntity(entity))
				{
					GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", destOrigin);
					GetDirectionArrow(i, vecOrigin, destOrigin, vecAngles, sArrow, sizeof(sArrow));
				}
			}

			if (g_Airtime[i].timing)
			{
				FormatPlayerTime(GetEngineTime() - g_Airtime[i].starttime, sTime, sizeof(sTime), true, 1);
				Format(sTime, sizeof(sTime), " | Airtime: %s", sTime);
			}

			GetGamemodeName(g_iGamemodeType, sGamemode, sizeof(sGamemode));
			SetHudTextParams(0.01, 0.03, 99999.0, 91, 255, 51, 225, g_Tutorial[i].flashtext > 0 ? 2 : 0, 1.0, 0.0, 0.0);
			ShowSyncHudText(i, g_hSync_Mode, "Mode: %s", sGamemode);

			GetDeliveryDestinationName(g_Player[i].destination, sDestination, sizeof(sDestination));
			SetHudTextParams(0.01, 0.06, 99999.0, 91, 255, 51, 225, g_Tutorial[i].flashtext > 0 ? 2 : 0, 1.0, 0.0, 0.0);
			ShowSyncHudText(i, g_hSync_Destination, "Destination: %s %s", sDestination, sArrow);

			if (g_Airtime[i].currentdeliveriesrecord > 0)
				FormatEx(sRecord, sizeof(sRecord), " [Record: %i]", g_Airtime[i].currentdeliveriesrecord);

			SetHudTextParams(0.01, 0.09, 99999.0, 91, 255, 51, 225, g_Tutorial[i].flashtext > 0 ? 2 : 0, 1.0, 0.0, 0.0);
			ShowSyncHudText(i, g_hSync_Score, "Deliveries: %i%s", g_Player[i].totalpizzas, sRecord);

			if (g_Tutorial[i].flashtext > 0)
				g_Tutorial[i].flashtext--;
		}
	}

	return Plugin_Continue;
}

//This requires the origin point be 'm_vecAbsOrigin' for trigger zones in order for it to work properly.
//This can be done a lot better.
void GetDirectionArrow(int client, float vecOrigin1[3], float vecOrigin2[3], float vecAngles1[3], char[] buffer, int size)
{
	// Angles from origin
	float vecPoints[3];
	MakeVectorFromPoints(vecOrigin1, vecOrigin2, vecPoints);

	float vecAngles[3];
	GetVectorAngles(vecPoints, vecAngles);

	// Differenz
	float diff = vecAngles1[1] - vecAngles[1];

	// Correct it
	if (diff < -180)
		diff = 360 + diff;

	if (diff > 180)
		diff = 360 - diff;

	if (g_bMutations[MUTATION_GPSMALFUNCTION])
		diff = GetRandomFloat(-360.0, 360.0);

	// Now geht the direction
	// Up
	if (diff >= -22.5 && diff < 22.5)
		Format(buffer, size, " [ \xe2\x86\x91 ]");

	// right up
	else if (diff >= 22.5 && diff < 67.5)
	{
		Format(buffer, size, " [ \xe2\x86\x97 ]");

		if (GetRandomFloat(0.0, 100.0) > 99.0)
		{
			char sRight[PLATFORM_MAX_PATH];
			FormatEx(sRight, sizeof(sRight), "vo/heavy_headright0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToClientSafe(client, sRight);

			if (GetRandomInt(0, 10) > 5)
				SpeakResponseConcept(client, "TLK_KILLED_PLAYER", "domination:revenge", "heavy");
		}
	}

	// right
	else if (diff >= 67.5 && diff < 112.5)
	{
		Format(buffer, size, " [ \xe2\x86\x92 ]");

		if (GetRandomFloat(0.0, 100.0) > 99.0)
		{
			char sRight[PLATFORM_MAX_PATH];
			FormatEx(sRight, sizeof(sRight), "vo/heavy_headright0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToClientSafe(client, sRight);

			if (GetRandomInt(0, 10) > 5)
				SpeakResponseConcept(client, "TLK_KILLED_PLAYER", "domination:revenge", "heavy");
		}
	}

	// right down
	else if (diff >= 112.5 && diff < 157.5)
	{
		Format(buffer, size, " [ \xe2\x86\x98 ]");

		if (GetRandomFloat(0.0, 100.0) > 99.0)
		{
			char sRight[PLATFORM_MAX_PATH];
			FormatEx(sRight, sizeof(sRight), "vo/heavy_headright0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToClientSafe(client, sRight);

			if (GetRandomInt(0, 10) > 5)
				SpeakResponseConcept(client, "TLK_KILLED_PLAYER", "domination:revenge", "heavy");
		}
	}

	// down
	else if (diff >= 157.5 || diff < -157.5)
		Format(buffer, size, " [ \xe2\x86\x93 ]");

	// down left
	else if (diff >= -157.5 && diff < -112.5)
	{
		Format(buffer, size, " [ \xe2\x86\x99 ]");

		if (GetRandomFloat(0.0, 100.0) > 99.0)
		{
			char sRight[PLATFORM_MAX_PATH];
			FormatEx(sRight, sizeof(sRight), "vo/heavy_headleft0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToClientSafe(client, sRight);

			if (GetRandomInt(0, 10) > 5)
				SpeakResponseConcept(client, "TLK_KILLED_PLAYER", "domination:revenge", "heavy");
		}
	}

	// left
	else if (diff >= -112.5 && diff < -67.5)
	{
		Format(buffer, size, " [ \xe2\x86\x90 ]");

		if (GetRandomFloat(0.0, 100.0) > 99.0)
		{
			char sRight[PLATFORM_MAX_PATH];
			FormatEx(sRight, sizeof(sRight), "vo/heavy_headleft0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToClientSafe(client, sRight);

			if (GetRandomInt(0, 10) > 5)
				SpeakResponseConcept(client, "TLK_KILLED_PLAYER", "domination:revenge", "heavy");
		}
	}

	// left up
	else if (diff >= -67.5 && diff < -22.5)
	{
		Format(buffer, size, " [ \xe2\x86\x96 ]");

		if (GetRandomFloat(0.0, 100.0) > 99.0)
		{
			char sRight[PLATFORM_MAX_PATH];
			FormatEx(sRight, sizeof(sRight), "vo/heavy_headleft0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToClientSafe(client, sRight);

			if (GetRandomInt(0, 10) > 5)
				SpeakResponseConcept(client, "TLK_KILLED_PLAYER", "domination:revenge", "heavy");
		}
	}
}

void GetDeliveryDestinationName(int destination, char[] buffer, int size)
{
	if (!IsValidEntity(destination))
	{
		strcopy(buffer, size, "None");
		return;
	}

	//Misleading AF
	GetEntPropString(destination, Prop_Data, "m_iParent", buffer, size);

	char sCharacters[11][1] =
	{
		"x",
		"X",
		"|",
		"=",
		"-",
		"_",
		"0",
		"Y",
		"y",
		"Z",
		"z"
	};

	if (g_bMutations[MUTATION_GPSMALFUNCTION])
	{
		for (int i = 0; i < strlen(buffer); i++)
			if (GetRandomInt(0, 1) == 1)
				ReplaceString(buffer, size, buffer[i], sCharacters[GetRandomInt(0, 10)]);
	}
}

int GetGameWinner()
{
	int winner = -1;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (g_Player[i].totalpizzas< 1)
				continue;

			if (winner == -1)
			{
				winner = i;
				continue;
			}

			if (g_Player[i].totalpizzas > g_Player[winner].totalpizzas)
				winner = i;
		}
	}

	return winner;
}

void ResetReferenceData(int client)
{
	g_Player[client].pizza = INVALID_ENT_REFERENCE;
	g_Player[client].destination = -1;
	g_Player[client].laststop = INVALID_ENT_REFERENCE;
	g_Airtime[client].spritetrail = INVALID_ENT_REFERENCE;
}

public void OnClientConnected(int client)
{
	g_Player[client].Init(client);
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client))
		return;

	g_Player[client].connected = true;
	g_Player[client].triggerdelay = -1;

	ResetReferenceData(client);

	SetHudScore(client, 0, false);

	g_Airtime[client].currentairtimerecord = 0.0;
	g_Airtime[client].roundairtimerecord = 0.0;

	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_Spawn, OnPlayerSpawn);
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);

	g_Player[client].backgroundmusic = true;

	g_Tutorial[client].tutorialstep = TUTORIAL_STEP_NONE;
	g_Tutorial[client].climbamount = 0;
	StopTimer(g_Tutorial[client].tutorialtimer);
	g_Tutorial[client].tutorialplayed = false;

	g_Player[client].isfemale = false;
	g_Player[client].supreme = false;

	EmitSoundToClientSafe(client, "hungryheavydelivery/jsr_groove_2.mp3", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.7);

	//Ledge Grabbing
	g_bHanging[client] = false;
	g_vecClimbPos[client] = view_as<float>({0.0, 0.0, 0.0});
}

public void OnClientCookiesCached(int client)
{
	if (IsFakeClient(client))
		return;

	char sValue[12];
	GetClientCookie(client, g_hCookie_ToggleMusic, sValue, sizeof(sValue));

	if (strlen(sValue) > 0)
		g_Player[client].backgroundmusic = StringToBool(sValue);
	else
	{
		g_Player[client].backgroundmusic = true;
		SetClientCookie(client, g_hCookie_ToggleMusic, "1");
	}

	sValue[0] = '\0';
	GetClientCookie(client, g_hCookie_Tutorial, sValue, sizeof(sValue));

	if (strlen(sValue) == 0)
		SetClientCookie(client, g_hCookie_Tutorial, "1");

	sValue[0] = '\0';
	GetClientCookie(client, g_hCookie_TutorialPlayed, sValue, sizeof(sValue));

	if (strlen(sValue) == 0)
		g_Tutorial[client].tutorialplayed = StringToBool(sValue);
	else
	{
		g_Tutorial[client].tutorialplayed = true;
		SetClientCookie(client, g_hCookie_TutorialPlayed, "1");
	}

	sValue[0] = '\0';
	GetClientCookie(client, g_hCookie_IsFemale, sValue, sizeof(sValue));

	if (strlen(sValue) > 0)
	{
		g_Player[client].isfemale = StringToBool(sValue);
	}
	else
	{
		g_Player[client].isfemale = false;
		SetClientCookie(client, g_hCookie_IsFemale, "0");
	}
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (g_Database == null)
		return;
	
	char sQuery[256];
	g_Database.Format(sQuery, sizeof(sQuery), "SELECT record_airtime, record_deliveries FROM `hungry_heavy_delivery_records` WHERE steamid = '%s' AND map = '%s';", auth, sCurrentMap);
	g_Database.Query(TQuery_OnGetRecord, sQuery, GetClientUserId(client));
}

public void TQuery_OnGetRecord(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
		ThrowError("Error retrieving client records for map '%s': %s", sCurrentMap, error);

	int client = GetClientOfUserId(data);

	if (!IsPlayerIndex(client))
		return;

	while (results.FetchRow())
	{
		g_Airtime[client].currentairtimerecord = results.FetchFloat(0);
		g_Airtime[client].currentdeliveriesrecord = results.FetchInt(1);
	}
}

public void OnClientDisconnect(int client)
{
	if (IsFakeClient(client))
		return;

	g_Player[client].connected = false;
	g_Player[client].triggerdelay = -1;

	ResetReferenceData(client);

	SetHudScore(client, 0, false);

	g_Airtime[client].currentairtimerecord = 0.0;
	g_Airtime[client].roundairtimerecord = 0.0;

	g_Airtime[client].currentdeliveriesrecord = 0;
	g_Airtime[client].rounddeliveriesrecord = 0;

	g_Airtime[client].starttime = 0.0;
	g_Airtime[client].timing = false;

	g_Player[client].backgroundmusic = true;

	g_Tutorial[client].tutorialstep = TUTORIAL_STEP_NONE;
	g_Tutorial[client].climbamount = 0;
	StopTimer(g_Tutorial[client].tutorialtimer);
	g_Tutorial[client].tutorialplayed = false;

	g_Player[client].isfemale = false;
	g_Player[client].supreme = false;

	StopTimer(g_Airtime[client].airtimesound);
	StopTimer(g_Player[client].backgroundmusictimer);
}

//This has a lot of problems but it works for now.
public Action OnPlayerSpawn(int entity)
{
	if (g_iGamemodeType == GAMEMODE_TYPE_ELIMINATION && !g_bPlayersFrozen)
		return Plugin_Stop;

	return Plugin_Continue;
}

//Rather people not fuck with people in tutorial mode.
public Action OnSetTransmit(int client, int entity)
{
	if (IsPlayerIndex(client) && IsPlayerAlive(client) && entity != client && g_Tutorial[entity].tutorialstep > TUTORIAL_STEP_NONE)
		return Plugin_Stop;

	return Plugin_Continue;
}

//Stop fall damage in-general, too much to deal with and stops the normal gameplay loop.
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (damagetype & DMG_FALL)
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public void OnGameFrame()
{
	float vecOrigin[3]; int destination; float vecDestStart[3]; float vecDestEnd[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		//The rings being in the players face is a problem and this is an easy fix for that.
		//GetClientAbsPosition(i, vecOrigin); vecOrigin[2] += 10.0;
		GetClientAbsOrigin(i, vecOrigin); vecOrigin[2] += GetEntityFlags(i) & FL_ONGROUND ? 20.0 : -20.0;

		if (HasPizzaBackpack(i))
		{
			TE_SetupBeamRingPoint(vecOrigin, 55.0, 57.0, g_iLaserMaterial, g_iHaloMaterial, 10, 10, 0.08, 1.0, 5.0, {235, 0, 0, 200}, 10, 0);
			TE_SendToAll();
		}

		if (IsValidEntity(g_Player[i].destination))
		{
			destination = g_Player[i].destination;

			if (IsValidEntity(destination))
			{
				GetAbsBoundingBox(destination, vecDestStart, vecDestEnd);
				Effect_DrawBeamBoxToClient(i, vecDestStart, vecDestEnd, g_iLaserMaterial, g_iHaloMaterial, 30, 30, 0.5, 5.0, 5.0, 1, 5.0, {210, 0, 0, 120}, 0);
			}
		}

		//This can 100% be done a better way but this is quick and easy.
		if (g_iGamemodeType == GAMEMODE_TYPE_BUNNYHOPPING)
			SetEntProp(i, Prop_Send, "m_iAirDash", 3);
	}
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsPlayerIndex(client) || !IsPlayerAlive(client))
		return;

	if (g_Player[client].connected)
	{
		g_Player[client].connected = false;

		char sCookie[16];
		GetClientCookie(client, g_hCookie_Tutorial, sCookie, sizeof(sCookie));

		if (StrEqual(sCookie, "1", false))
		{
			SetClientCookie(client, g_hCookie_Tutorial, "0");
			OpenTutorialMenu(client);
		}
		else
			OpenMainMenu(client);
	}

	g_Player[client].triggerdelay = -1;

	ResetReferenceData(client);

	SetSpawnFunctions(client);
	PlayBackgroundMusic(client);

	if (g_Player[client].isfemale)
		SetModel(client, "models/player/scout_female.mdl");

	g_Player[client].supreme = false;

	ClearTutorial(client);

	int spawns[2048];
	int totalspawns;

	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "info_player_teamspawn")) != -1)
		spawns[totalspawns++] = entity;

	int tele = spawns[GetRandomInt(0, totalspawns - 1)];

	float origin[3];
	GetEntityOrigin(tele, origin);

	float angles[3];
	GetEntityAngles(tele, angles);

	TeleportEntity(client, origin, angles, NULL_VECTOR);
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsPlayerIndex(client))
		return;
	
	switch (g_iGamemodeType)
	{
		case GAMEMODE_TYPE_RESETONDEATH:
		{
			SetHudScore(client, 0);
			CPrintToChat(client, "%s You have died, your score has been reset back to 0... Heavy is not happy.", PLUGIN_TAG_COLORED);

			char sSound[PLATFORM_MAX_PATH];
			FormatEx(sSound, sizeof(sSound), "vo/heavy_no0%i.mp3", GetRandomInt(1, 3));
			EmitSoundToClientSafeDelayed(client, sSound, 1.0);
		}

		case GAMEMODE_TYPE_ELIMINATION:
		{
			//Needs a frame delay to count this death properly.
			RequestFrame(Frame_CheckLiveCount);
		}
	}

	KillPizzaBackpack(client);
	ClearTutorial(client);

	if (g_Airtime[client].timing)
		EmitSoundToClientSafeDelayed(client, "coach/coach_student_died.wav", 1.0);
}

public void Frame_CheckLiveCount(any data)
{
	if (GetClientAliveCount() == 0)
	{
		g_iGamemodeType = GAMEMODE_TYPE_NORMAL;
		TF2_ForceWin(TFTeam_Unassigned);
	}
}

public void Event_OnResupply(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsPlayerIndex(client))
		return;

	SetSpawnFunctions(client);
}

public void Event_OnTeamplayRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bBetweenRounds = false;
	g_bPlayersFrozen = true;

	StopTimer(g_hSecondsTimer);
	g_hSecondsTimer = CreateTimer(1.0, Timer_TicksInSeconds, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	StopTimer(g_hMillisecondsTimer);
	g_hMillisecondsTimer = CreateTimer(0.1, Timer_TicksInMilliseconds, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	//Checks if there's any queued gamemodes by admins and/or console/RCON commands.
	if (g_iQueuedGamemode == 0)
	{
		//Pick whether it should be normal or random gamemode.
		g_iGamemodeType = GetRandomInt(0, 1);

		//If random, we should pick one of the available modes that isn't normal.
		if (g_iGamemodeType == GAMEMODE_TYPE_RANDOM)
		{
			//Elimination is the first non-normal gamemode, start with it and go up to the maximum amount of special modes.
			g_iGamemodeType = GetRandomInt(GAMEMODE_TYPE_ELIMINATION, GAMEMODE_TYPES);
		}
	}
	else
	{
		g_iGamemodeType = g_iQueuedGamemode;
		g_iQueuedGamemode = 0;
	}

	char sGamemode[64];
	GetGamemodeName(g_iGamemodeType, sGamemode, sizeof(sGamemode));
	PrintCenterTextAll("Gamemode: %s", sGamemode);

	if (g_iGamemodeType == GAMEMODE_TYPE_TEAMS)
	{
		EmitSoundToAllSafeDelayed("vo/announcer_you_must_not_fail_this_time.mp3", 3.0);

		int gamerules = FindEntityByClassname(-1, "tf_gamerules");

		if (!IsValidEntity(gamerules))
			gamerules = CreateEntityByName("tf_gamerules");
		
		DispatchKeyValue(gamerules, "hud_type", "1");
		DispatchSpawn(gamerules);
		
		char message[256];
		
		//BLU
		Format(message, sizeof(message), "Blue Pizzas");
		SetVariantString(message);
		AcceptEntityInput(gamerules, "SetBlueTeamGoalString");
		SetVariantString("2");
		AcceptEntityInput(gamerules, "SetBlueTeamRole");

		//RED
		Format(message, sizeof(message), "Red Pizzas");
		SetVariantString(message);
		AcceptEntityInput(gamerules, "SetRedTeamGoalString");
		SetVariantString("1");
		AcceptEntityInput(gamerules, "SetRedTeamRole");
	}

	//Set the remaining time for this round.
	g_iRemainingTime = convar_Default_Time.IntValue;
	CreateTF2Timer(g_iRemainingTime);

	for (int i = 1; i <= MaxClients; i++)
	{
		SetHudScore(i, 0);
		PlayBackgroundMusic(i);

		g_Airtime[i].roundairtimerecord = 0.0;
		g_Airtime[i].rounddeliveriesrecord = 0;

		if (IsClientConnected(i))
			ClearOverlay(i);

		ClearTutorial(i);
	}

	CreateTimer(0.5, Timer_ForceTauntAndSound, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ForceTauntAndSound(Handle timer)
{
	char sSound[PLATFORM_MAX_PATH];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			FakeClientCommand(i, "taunt");

			FormatEx(sSound, sizeof(sSound), "items/taunts/scout_boston_breakdance/scout_boston_breakdance__0%i.wav", GetRandomInt(2, 5));
			EmitSoundToClientSafe(i, sSound);
		}
	}
}

//Convenience
bool GetGamemodeName(int id, char[] buffer, int size)
{
	switch (id)
	{
		case GAMEMODE_TYPE_NORMAL:
		{
			strcopy(buffer, size, "Normal");
			return true;
		}
		case GAMEMODE_TYPE_ELIMINATION:
		{
			strcopy(buffer, size, "Elimination");
			return true;
		}
		case GAMEMODE_TYPE_TEAMS:
		{
			strcopy(buffer, size, "Teams");
			return true;
		}
		case GAMEMODE_TYPE_RESETONDEATH:
		{
			strcopy(buffer, size, "Reset On Death");
			return true;
		}
		case GAMEMODE_TYPE_BUNNYHOPPING:
		{
			strcopy(buffer, size, "Bunnyhopping");
			return true;
		}
	}

	return false;
}

bool GetMutationName(int id, char[] buffer, int size)
{
	switch (id)
	{
		case MUTATION_DOUBLEVELOCITY:
		{
			strcopy(buffer, size, "Double Velocity");
			return true;
		}
		case MUTATION_SUPREMEPIZZAS:
		{
			strcopy(buffer, size, "Supreme Pizzas");
			return true;
		}
		case MUTATION_GPSMALFUNCTION:
		{
			strcopy(buffer, size, "GPS Malfunction");
			return true;
		}
	}

	return false;
}

public void Event_OnTeamplayRoundActive(Event event, const char[] name, bool dontBroadcast)
{
	g_bPlayersFrozen = false;

	EmitSoundToAllSafe("coach/coach_go_here.wav");

	char sMutations[255]; char sMutation[32];
	for (int i = 0; i < sizeof(g_bMutations); i++)
	{
		g_bMutations[i] = GetRandomBool();
		GetMutationName(i, sMutation, sizeof(sMutation));

		if (g_bMutations[i])
			Format(sMutations, sizeof(sMutations), "%s%s%s", sMutations, (strlen(sMutations) == 0) ? " " : ", ", sMutation);
	}

	CPrintToChatAll("%s Mutations:%s", PLUGIN_TAG_COLORED, strlen(sMutations) > 0 ? sMutations : " None Active");

	//Tell people they can be faster moveable boys.
	if (g_bMutations[MUTATION_DOUBLEVELOCITY])
	{
		CPrintToChatAll("%s DOUBLE VELOCITY ACTIVATED!", PLUGIN_TAG_COLORED);
		EmitSoundToAllSafe("ui/rd_2base_alarm.wav");
		EmitSoundToAllSafeDelayed(GetRandomInt(0, 1) == 0 ? "vo/heavy_battlecry03.mp3" : "vo/heavy_battlecry05.mp3", 1.5);
		SpeakResponseConceptAllDelayed("TLK_PLAYER_ATTACKER_PAIN", 2.0);
	}
	else
	{
		char sCompleted[PLATFORM_MAX_PATH];
		FormatEx(sCompleted, sizeof(sCompleted), "vo/heavy_specialcompleted%02d.mp3", GetRandomInt(1, 11));
		EmitSoundToAllSafeDelayed(sCompleted, 2.0);
		SpeakResponseConceptAllDelayed("TLK_MVM_ENCOURAGE_MONEY", 3.0);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "tf_dropped_weapon"))
		SDKHook(entity, SDKHook_Spawn, OnDroppedWeaponSpawn);
	else if (StrEqual(classname, "prop_dynamic"))
	{
		SDKHook(entity, SDKHook_Spawn, OnDynamicPropSpawn);
		SDKHook(entity, SDKHook_SpawnPost, OnDynamicPropSpawnPost);

		if (g_bLate)
		{
			OnDynamicPropSpawn(entity);
			OnDynamicPropSpawnPost(entity);
		}
	}
	else if (StrEqual(classname, "trigger_multiple"))
	{
		SDKHook(entity, SDKHook_SpawnPost, OnTriggerSpawnPost);

		if (g_bLate)
			OnTriggerSpawnPost(entity);
	}
}

//Fix so if you walk into the pickup zone, it doesn't drop a bunch of weapons once it regenerates you.
public Action OnDroppedWeaponSpawn(int entity)
{
	//FUCK NO
	return Plugin_Stop;
}

//Fixes for server lag.
public Action OnDynamicPropSpawn(int entity)
{
	//lag fix
	DispatchKeyValue(entity, "DisableBoneFollowers", "1");
	DispatchKeyValue(entity, "solid", "0");

	//optional fixes
	DispatchKeyValue(entity, "DisableCollision", "1");
	DispatchKeyValue(entity, "PerformanceMode", "1");
}

public void OnDynamicPropSpawnPost(int entity)
{
	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (StrEqual(sName, "heavy_himself") || (StrContains(sName, "pizza_delivery_") == 0 && StrContains(sName, "person") != -1))
	{
		char sBuffer[256];
		FormatEx(sBuffer, sizeof(sBuffer), "%s_glow", sName);

		TF2_CreateGlow(sBuffer, entity, view_as<int>(StrEqual(sName, "heavy_himself") ? {255, 255, 255, 150} : {255, 0, 0, 150}));
	}
}

//An attempt was made to draw every zone with the tempents for beampoints but there's a limited amount of TEs.
//We do draw the pickup zone though to specify new players that you should walk into this.
public void OnTriggerSpawnPost(int entity)
{
	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	float vecOrigin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vecOrigin);

	float vecStart[3]; float vecEnd[3];
	GetAbsBoundingBox(entity, vecStart, vecEnd);

	if (StrEqual(sName, "pizza_pickup"))
	{
		SDKHook(entity, SDKHook_StartTouch, OnPizzaPickup);
		SDKHook(entity, SDKHook_Touch, OnPizzaPickup);
		SDKHook(entity, SDKHook_EndTouch, OnPizzaPickup);
		Effect_DrawRangedBeamBox(vecOrigin, vecStart, vecEnd, g_iLaserMaterial, g_iHaloMaterial, 0, 0, 0.0, 2.0, 2.0, 1, 0.0, {255, 255, 255, 120}, 0);
	}

	if (StrContains(sName, "pizza_delivery") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, OnPizzaDelivery);
		SDKHook(entity, SDKHook_Touch, OnPizzaDelivery);
		SDKHook(entity, SDKHook_EndTouch, OnPizzaDelivery);
	}
}

public void Event_OnTeamplayWaitingEnds(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
		if (g_Airtime[i].timing)
			FinishTimer(i);
}

public void Event_OnTeamplayRoundWin(Event event, const char[] name, bool dontBroadcast)
{
	g_bBetweenRounds = true;
	g_bPlayersFrozen = false;

	for (int i = 0; i < sizeof(g_bMutations); i++)
		g_bMutations[i] = false;

	int end_panel = GetRandomInt(0, 1);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (end_panel == 0)
			OpenCurrentAirtimeRecords(i);
		else
			OpenCurrentDeliveryTimes(i);

		ClearTutorial(i);

		if (g_Airtime[i].rounddeliveriesrecord > g_Airtime[i].currentdeliveriesrecord)
		{
			g_Airtime[i].currentdeliveriesrecord = g_Airtime[i].rounddeliveriesrecord;

			char sSteamID[32];
			if (g_Database != null && GetClientAuthId(i, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
			{
				char sName[128];
				SQL_FetchClientName(i, g_Database, sName, sizeof(sName));

				char sQuery[256];
				g_Database.Format(sQuery, sizeof(sQuery), "INSERT INTO `hungry_heavy_delivery_records` (name, steamid, record_airtime, record_deliveries, map) VALUES ('%s', '%s', '%f', '%i', '%s') ON DUPLICATE KEY UPDATE record_airtime = '%f', record_deliveries = '%i';", sName, sSteamID, g_Airtime[i].currentairtimerecord, g_Airtime[i].currentdeliveriesrecord, sCurrentMap, g_Airtime[i].currentairtimerecord, g_Airtime[i].currentdeliveriesrecord);
				g_Database.Query(onInsertRecord, sQuery);
			}
		}
	}
}

public void onInsertRecord(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
		ThrowError("Error while inserting a new record: %s", error);
}

public Action Event_OnTeamplayFlagEvent(Event event, const char[] name, bool dontBroadcast)
{
	SetEventBroadcast(event, true);

	//This event doesn't have the flag entity itself, we have to find it and kill it.
	if (event.GetInt("eventtype") != 4)
		return Plugin_Continue;

	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "item_teamflag")) != -1)
		if (GetEntProp(entity, Prop_Send, "m_nFlagStatus") == TF_FLAGINFO_DROPPED)
			AcceptEntityInput(entity, "Kill");
	
	return Plugin_Continue;
}

void SetSpawnFunctions(int client)
{
	if (TF2_GetPlayerClass(client) != TFClass_Scout)
	{
		TF2_SetPlayerClass(client, TFClass_Scout, false, true);
		TF2_RegeneratePlayer(client);
	}

	int weapon;

	if (wep_primary != null)
	{
		TF2_RemoveWeaponSlot(client, 0);
		weapon = TF2Items_GiveNamedItem(client, wep_primary);

		if (IsValidEntity(weapon))
			EquipPlayerWeapon(client, weapon);
	}

	if (wep_secondary != null)
	{
		TF2_RemoveWeaponSlot(client, 1);
		weapon = TF2Items_GiveNamedItem(client, wep_secondary);

		if (IsValidEntity(weapon))
			EquipPlayerWeapon(client, weapon);
	}

	if (wep_melee != null)
	{
		TF2_RemoveWeaponSlot(client, 2);
		weapon = TF2Items_GiveNamedItem(client, wep_melee);

		if (IsValidEntity(weapon))
			EquipPlayerWeapon(client, weapon);
	}

	TF2Attrib_ApplyMoveSpeedBonus(client, 3.0);

	int primary = GetPlayerWeaponSlot(client, 0);

	if (IsValidEntity(primary))
	{
		TF2Attrib_SetByName_Weapons(client, primary, "clip size bonus", 1.50);
		TF2Attrib_SetByName_Weapons(client, primary, "maxammo primary increased", 4.0);
		TF2Attrib_SetByName_Weapons(client, primary, "faster reload rate", 0.75);
		TF2Attrib_SetByName_Weapons(client, primary, "scattergun has knockback", 0.0);
	}

	int secondary = GetPlayerWeaponSlot(client, 1);

	if (IsValidEntity(secondary))
	{
		TF2Attrib_SetByName_Weapons(client, secondary, "clip size bonus", 3.0);
		TF2Attrib_SetByName_Weapons(client, secondary, "maxammo secondary increased", 5.0);
		TF2Attrib_SetByName_Weapons(client, secondary, "faster reload rate", 1.50);
	}

	g_Airtime[client].recordcache = false;
	g_Player[client].climbs = 0;
}

void PlayBackgroundMusic(int client)
{
	if (!g_Player[client].backgroundmusic || g_Player[client].backgroundmusictimer != null)
		return;

	int index = GetRandomInt(0, g_BackgroundMusic.Length - 1);

	char sMusic[PLATFORM_MAX_PATH];
	g_BackgroundMusic.GetString(index, sMusic, sizeof(sMusic));

	EmitSoundToClientSafe(client, sMusic, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);

	StopTimer(g_Player[client].backgroundmusictimer);
	g_Player[client].backgroundmusictimer = CreateTimer(g_BackgroundMusicSeconds.Get(index), Timer_NextSong, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_NextSong(Handle timer, any data)
{
	int client = data;
	g_Player[client].backgroundmusictimer = null;
	PlayBackgroundMusic(client);
}

void StopBackgroundMusic(int client)
{
	StopTimer(g_Player[client].backgroundmusictimer);

	char sMusic[PLATFORM_MAX_PATH];
	for (int i = 0; i < g_BackgroundMusic.Length; i++)
	{
		g_BackgroundMusic.GetString(i, sMusic, sizeof(sMusic));
		StopSound(client, SNDCHAN_AUTO, sMusic);
	}
}

//Doesn't fire during round end if you have full crits as the winning team, kind of annoying but whatever. (still works)
public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool &result)
{
	//Players shouldn't be flying out of the gate automatically.
	if (g_bPlayersFrozen)
		return Plugin_Continue;

	int slot = GetActiveWeaponSlot(client);

	float vecOrigin[3];
	GetClientAbsOrigin(client, vecOrigin);

	float vecAngles[3];
	GetClientEyeAngles(client, vecAngles);

	float vecVelocity[3];
	float vecDummy[3];

	bool bIsOnGround = view_as<bool>(GetEntityFlags(client) & FL_ONGROUND);

	float vecEyePosition[3];
	GetClientEyePosition(client, vecEyePosition);

	float vecLook[3];
	GetClientLookOrigin(client, vecLook);

	int iColors[4];
	switch (GetClientTeam(client))
	{
		case 2: iColors = {255, 0, 0, 255};
		case 3: iColors = {0, 0, 255, 255};
	}

	bool meleevault;

	switch (slot)
	{
		case 0:
		{
			AnglesToVelocity(vecAngles, (g_bMutations[MUTATION_DOUBLEVELOCITY] ? convar_Velocity_Primary_Double.FloatValue : convar_Velocity_Primary.FloatValue), vecVelocity);
			vecVelocity[0] = -vecVelocity[0];
			vecVelocity[1] = -vecVelocity[1];
			vecVelocity[2] = -vecVelocity[2];
			vecOrigin[2] += bIsOnGround ? 25.0 : 0.0;

			g_Airtime[client].secondaryshots = 0;

			if (g_iGamemodeType != GAMEMODE_TYPE_BUNNYHOPPING)
			{
				TE_SetupBeamPoints(vecEyePosition, vecLook, g_iLaserMaterial, g_iHaloMaterial, 0, 0, 1.0, 1.0, 1.0, 1, 0.0, iColors, 0);
				TE_SendToAll();

				vecLook[0] += GetRandomFloat(47.0, 53.0);
				TE_SetupBeamPoints(vecEyePosition, vecLook, g_iLaserMaterial, g_iHaloMaterial, 0, 0, 1.0, 1.0, 1.0, 1, 0.0, iColors, 0);
				TE_SendToAll();

				vecLook[1] += GetRandomFloat(47.0, 53.0);
				TE_SetupBeamPoints(vecEyePosition, vecLook, g_iLaserMaterial, g_iHaloMaterial, 0, 0, 1.0, 1.0, 1.0, 1, 0.0, iColors, 0);
				TE_SendToAll();

				vecLook[0] -= GetRandomFloat(97.0, 103.0);
				TE_SetupBeamPoints(vecEyePosition, vecLook, g_iLaserMaterial, g_iHaloMaterial, 0, 0, 1.0, 1.0, 1.0, 1, 0.0, iColors, 0);
				TE_SendToAll();

				vecLook[1] -= GetRandomFloat(97.0, 103.0);
				TE_SetupBeamPoints(vecEyePosition, vecLook, g_iLaserMaterial, g_iHaloMaterial, 0, 0, 1.0, 1.0, 1.0, 1, 0.0, iColors, 0);
				TE_SendToAll();
			}
		}
		case 1:
		{
			float angles[3];
			GetClientAbsAngles(client, angles);

			float velo[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", velo);

			AnglesToVelocity(angles, (GetVectorLength(velo) * 0.95), vecVelocity);

			g_Airtime[client].secondaryshots++;

			if (g_Airtime[client].secondaryshots >= 3)
			{
				g_Airtime[client].secondaryshots = 0;

				SetEntProp(client, Prop_Send, "m_iAirDash", 0);

				int primary = GetPlayerWeaponSlot(client, 0);
				int current_clip = GetClip(primary);
				int current_ammo = GetAmmo(client, primary);
				int amount = 3;

				if (current_ammo >= amount && current_clip < amount)
				{
					SetAmmo(client, primary, current_ammo - amount);
					SetClip(primary, amount);
				}
			}

			TE_SetupBeamPoints(vecEyePosition, vecLook, g_iLaserMaterial, g_iHaloMaterial, 0, 0, 0.06, 0.5, 0.5, 1, 0.0, iColors, 0);
			TE_SendToAll();
		}
		case 2:
		{
			if (!g_Airtime[client].timing && bIsOnGround)
			{
				GetAngleVectors(vecAngles, vecVelocity, vecDummy, vecDummy);
				ScaleVector(vecVelocity, g_bMutations[MUTATION_DOUBLEVELOCITY] ? convar_Velocity_Melee_Double.FloatValue : convar_Velocity_Melee.FloatValue);
				meleevault = true;
			}
		}
	}

	if (slot == 2 && (!meleevault || g_Tutorial[client].tutorialstep == TUTORIAL_STEP_CLIMB))
	{
		AttemptWallClimb(client);
		return Plugin_Continue;
	}

	if (g_Tutorial[client].tutorialstep < TUTORIAL_STEP_CLIMB && (g_iGamemodeType != GAMEMODE_TYPE_BUNNYHOPPING || g_iGamemodeType == GAMEMODE_TYPE_BUNNYHOPPING && bIsOnGround && slot == 1) || g_iGamemodeType == GAMEMODE_TYPE_BUNNYHOPPING && g_Tutorial[client].tutorialstep > TUTORIAL_STEP_NONE)
	{
		TeleportEntity(client, vecOrigin, NULL_VECTOR, vecVelocity);

		if (meleevault)
			EmitSoundToClientSafe(client, "weapons/airstrike_fire_01.wav");

		if (g_Airtime[client].timing && GetRandomFloat(0.0, 1.0) > 0.7)
			SpeakResponseConceptDelayed(client, "TLK_PLAYER_GO", 0.3);

		if (g_Tutorial[client].tutorialstep > TUTORIAL_STEP_NONE && g_Tutorial[client].tutorialtimer == null)
			g_Tutorial[client].tutorialtimer = CreateTimer(5.0, Timer_NextTutorialStep, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

void AttemptWallClimb(int client)
{
	float vecEyePos[3];
	GetClientEyePosition(client, vecEyePos);

	float vecEyeAngles[3];
	GetClientEyeAngles(client, vecEyeAngles);

	TR_TraceRayFilter(vecEyePos, vecEyeAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitSelf, client);

	if (!TR_DidHit(null))
		return;

	int entity = TR_GetEntityIndex();

	char sClassname[32];
	GetEntityClassname(entity, sClassname, sizeof(sClassname));

	if (!StrEqual(sClassname, "worldspawn"))
		return;

	float vecNormal[3];
	TR_GetPlaneNormal(null, vecNormal);
	GetVectorAngles(vecNormal, vecNormal);

	if ((vecNormal[0] >= 30.0 && vecNormal[0] <= 330.0) || (vecNormal[0] <= -30.0))
		return;

	float vecPos[3];
	TR_GetEndPosition(vecPos);

	float distance = GetVectorDistance(vecEyePos, vecPos);

	if (distance >= 80.0)
		return;

	float vecVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vecVelocity);
	vecVelocity[2] = g_bMutations[MUTATION_DOUBLEVELOCITY] ? convar_Velocity_Melee_Climb_Double.FloatValue : convar_Velocity_Melee_Climb.FloatValue;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vecVelocity);

	if (g_Tutorial[client].tutorialstep == TUTORIAL_STEP_CLIMB)
	{
		if (g_Tutorial[client].climbamount != -1)
		{
			g_Tutorial[client].climbamount++;
			PrintCenterText(client, "Climb %i/5 times!", g_Tutorial[client].climbamount);
		}

		if (g_Tutorial[client].climbamount >= 5)
		{
			EmitSoundToClientSafe(client, "ui/duel_score_behind.wav");
			g_Tutorial[client].climbamount = -1;

			if (g_Tutorial[client].tutorialtimer == null)
				g_Tutorial[client].tutorialtimer = CreateTimer(3.0, Timer_NextTutorialStep, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			EmitSoundToClientSafe(client, "ui/hitsound_beepo.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, (100 + (g_Tutorial[client].climbamount * 3)));
		}
	}
	else
	{
		EmitSoundToClientSafe(client, "ui/hitsound_beepo.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, (100 + (g_Player[client].climbs * 3)));
		g_Player[client].climbs++;
	}
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	return (entity != data);
}

public Action Timer_NextTutorialStep(Handle timer, any data)
{
	int client = GetClientOfUserId(data);

	if (!IsPlayerIndex(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;

	g_Tutorial[client].tutorialtimer = null;
	g_Tutorial[client].tutorialstep++;
	LoadTutorialStep(client);

	return Plugin_Stop;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	/*if ((!(GetEntityFlags(client) & FL_FAKECLIENT) && buttons & IN_JUMP) && (GetEntityFlags(client) & FL_ONGROUND))
	{
		int nOldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
		SetEntProp(client, Prop_Data, "m_nOldButtons", (nOldButtons &= ~(IN_JUMP | IN_DUCK)));
	}*/

	if (IsPlayerAlive(client) && GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") < 0 && GetActiveWeaponSlot(client) == 2)
	{
		if(buttons & IN_JUMP && g_bHanging[client] && !(buttons & IN_DUCK))
		{
			SetEntityMoveType(client, MOVETYPE_WALK);
			
			g_vecClimbPos[client][2] += 5.0;
			
			TeleportEntity(client, g_vecClimbPos[client], NULL_VECTOR, NULL_VECTOR); 
			
			g_bHanging[client] = false;
			
			SetVariantString("");
			AcceptEntityInput(client, "SetCustomModel");
			SetVariantBool(true);
			AcceptEntityInput(client, "SetCustomModelRotates");
		}
		else if(buttons & IN_DUCK && g_bHanging[client])
		{
			SetEntityMoveType(client, MOVETYPE_WALK);
			g_bHanging[client] = false;
			
			SetVariantString("");
			AcceptEntityInput(client, "SetCustomModel");
			SetVariantBool(true);
			AcceptEntityInput(client, "SetCustomModelRotates");
		}
		
		float flOrigin[3], flMins[3], flMaxs[3];
		GetClientAbsOrigin(client, flOrigin);
		GetClientMaxs(client, flMaxs);
		GetClientMins(client, flMins);
	
		flMaxs[0] += 2.5;
		flMaxs[1] += 2.5;
		flMins[0] -= 2.5;
		flMins[1] -= 2.5;
		
		Handle TraceRay = TR_TraceHullFilterEx(flOrigin, flOrigin, flMins, flMaxs, MASK_PLAYERSOLID, TraceFilterNotSelf, client);
		bool bHit = TR_DidHit(TraceRay);
		delete TraceRay;
		
		if(bHit)
		{
			float eyeangles[3], forw[3];
			GetClientEyeAngles(client, eyeangles);
			eyeangles[0] = 0.0;
			GetAngleVectors(eyeangles, forw, NULL_VECTOR, NULL_VECTOR);
			
			MapCircleToSquare(forw, forw);
			
			flOrigin[0] += (forw[0] * 29);
			flOrigin[1] += (forw[1] * 29);
			flOrigin[2] += (forw[2] * 29) + flMaxs[2];
			
			flOrigin[2] += 32.0;
		
			float flHitPos[3];
			TR_TraceRayFilter(flOrigin, view_as<float>({90.0, 0.0, 0.0}), MASK_PLAYERSOLID, RayType_Infinite, TraceFilterNotSelf, client);
			if (TR_DidHit() && !g_bHanging[client])
			{
				TR_GetEndPosition(flHitPos);
				
				GetClientMaxs(client, flMaxs);
				GetClientMins(client, flMins);
				
				TR_TraceHullFilter(flOrigin, flHitPos, flMins, flMaxs, MASK_SOLID, TraceEntityFilterSolid, client);
			
				float fatty[3];

				TR_GetEndPosition(fatty);
				
				GetClientEyePosition(client, flOrigin);
				float flDistance = GetVectorDistance(flOrigin, fatty);
				
				if(flDistance <= 40.0 && flDistance >= 22.0)
				{
					TR_TraceHullFilter(fatty, fatty, flMins, flMaxs, MASK_SOLID, TraceEntityFilterSolid, client);	//Test if we can fit to the dest pos before teleporting
					if(!TR_DidHit())
					{						
						g_vecClimbPos[client][0] = fatty[0];
						g_vecClimbPos[client][1] = fatty[1];
						g_vecClimbPos[client][2] = fatty[2];
						
						fatty[0] = flOrigin[0];
						fatty[1] = flOrigin[1];
						fatty[2] = (fatty[2] -= flMaxs[2]);
						
						TeleportEntity(client, fatty, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0})); 
						
						SetEntityMoveType(client, MOVETYPE_NONE);
						
						g_bHanging[client] = true;
						
						char strModel[PLATFORM_MAX_PATH];
						GetEntPropString(client, Prop_Data, "m_ModelName", strModel, PLATFORM_MAX_PATH);
						
						SetVariantString(strModel);
						AcceptEntityInput(client, "SetCustomModel");
						SetVariantBool(false);
						AcceptEntityInput(client, "SetCustomModelRotates");
						SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 0);		
					}
				}
			}
		}
	}

	if (GetEntityFlags(client) & FL_ONGROUND)
		g_Player[client].climbs = 0;

	if (g_bWaitingForPlayers || g_bBetweenRounds || g_bPlayersFrozen)
	{
		FinishTimer(client);
		return Plugin_Continue;
	}

	if (g_Tutorial[client].tutorialstep == TUTORIAL_STEP_DELIVERY && !IsClientNearEntityViaName(client, "tutorial_delivery_point", "info_teleport_destination", 500.0))
		TeleportToDestination(client, "tutorial_delivery_point");

	if ((g_Tutorial[client].tutorialstep >= TUTORIAL_STEP_PISTOL && g_Tutorial[client].tutorialstep <= TUTORIAL_STEP_FAN))
	{
		vel[0] = 0.0;
		vel[1] = 0.0;
		vel[2] = 0.0;
		return Plugin_Changed;
	}
	else if ((g_Tutorial[client].tutorialstep >= TUTORIAL_STEP_CLIMB && g_Tutorial[client].tutorialstep <= TUTORIAL_STEP_DELIVERY) && !(buttons & IN_FORWARD))
	{
		vel[0] = 0.0;
		vel[1] = 0.0;
		vel[2] = 0.0;
		return Plugin_Changed;
	}

	if (!IsPlayerAlive(client) || GetEntProp(client, Prop_Send, "m_nWaterLevel") > 1 || GetEntityMoveType(client) == MOVETYPE_NOCLIP || g_iGamemodeType == GAMEMODE_TYPE_BUNNYHOPPING)
	{
		FinishTimer(client);
		return Plugin_Continue;
	}

	if (!(GetEntityFlags(client) & FL_ONGROUND) && !g_Airtime[client].timing && HasPizzaBackpack(client))
	{
		//This buffer delay makes clients stay in the air for a certain amount of time before airtime starts.
		g_Airtime[client].offgrounddelay++;

		if (g_Airtime[client].offgrounddelay < 200)
			return Plugin_Continue;
		
		StartTimer(client);
	}
	else
		g_Airtime[client].offgrounddelay = 0;

	float speed = GetPlayerSpeed(client);

	if (g_Airtime[client].timing && speed > g_Airtime[client].topspeed)
		g_Airtime[client].topspeed = speed;

	float vecOrigin[3];
	GetClientAbsOrigin(client, vecOrigin);

	if (GetEntityFlags(client) & FL_ONGROUND && g_Airtime[client].timing)
	{
		float finished = FinishTimer(client);
		bool new_record;

		if (finished > g_Airtime[client].roundairtimerecord)
			g_Airtime[client].roundairtimerecord = finished;

		if (finished > g_Airtime[client].currentairtimerecord)
		{
			g_Airtime[client].currentairtimerecord = finished;
			new_record = true;

			char sSteamID[32];
			GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));

			if (g_Database != null)
			{
				char sName[128];
				SQL_FetchClientName(client, g_Database, sName, sizeof(sName));

				char sQuery[256];
				g_Database.Format(sQuery, sizeof(sQuery), "INSERT INTO `hungry_heavy_delivery_records` (name, steamid, record_airtime, record_deliveries, map) VALUES ('%s', '%s', '%f', '%i', '%s') ON DUPLICATE KEY UPDATE record_airtime = '%f', record_deliveries = '%i';", sName, sSteamID, g_Airtime[client].currentairtimerecord, g_Airtime[client].currentdeliveriesrecord, sCurrentMap, g_Airtime[client].currentairtimerecord, g_Airtime[client].currentdeliveriesrecord);
				g_Database.Query(onInsertRecord2, sQuery);
			}

			float offset[3] = {0.0, 0.0, 80.0};
			AttachParticle(client, "achieved", 5.0, "forward", offset);
			SpeakResponseConceptDelayed(client, "TLK_PLAYER_CHEERS", 0.8);
		}

		//Ground stomp.
		if (speed > 20.0)
		{
			CreateParticle("hammer_impact_button", vecOrigin, 10.0);
			EmitSoundToAllSafe("items/para_close.wav", client);
			PushAllPlayersFromPoint(vecOrigin, 500.0, 500.0, 0, client);
			DamageRadius(vecOrigin, 500.0, 5.0, client);
		}

		char sDifference[32];
		FormatEx(sDifference, sizeof(sDifference), "%.2f seconds behind record", finished - g_Airtime[client].currentairtimerecord);

		CPrintToChat(client, "%s Accomplished Airtime: %.2f (%s) (Highest Speed: %.2f)", PLUGIN_TAG_COLORED, finished, new_record ? "NEW RECORD" : sDifference, g_Airtime[client].topspeed);
		g_Airtime[client].topspeed = 0.0;

		EmitSoundToClientSafe(client, "ui/hitsound.wav");

		if (finished >= (g_Airtime[client].currentairtimerecord - 5.0))
		{
			int chosen = GetRandomInt(1, 5);

			if (g_Airtime[client].lastpositivemessage == chosen)
			{
				chosen--;

				if (chosen < 1)
					chosen = 5;
			}

			g_Airtime[client].lastpositivemessage = chosen;

			char sPositive[PLATFORM_MAX_PATH];
			FormatEx(sPositive, sizeof(sPositive), "vo/heavy_positivevocalization0%i.mp3", chosen);
			EmitSoundToClientSafe(client, sPositive);
		}
		else if (finished >= (g_Airtime[client].currentairtimerecord - 20.0))
		{
			int chosen = GetRandomInt(1, 6);

			if (g_Airtime[client].lastnegativemessage == chosen)
			{
				chosen--;

				if (chosen < 1)
					chosen = 5;
			}

			g_Airtime[client].lastnegativemessage = chosen;

			char sNegative[PLATFORM_MAX_PATH];
			FormatEx(sNegative, sizeof(sNegative), "vo/heavy_negativevocalization0%i.mp3", chosen);

			if (GetRandomInt(0, 5) > 2)
				EmitSoundToClientSafe(client, sNegative);
		}
	}

	return Plugin_Continue;
}

public void onInsertRecord2(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
		ThrowError("Error while inserting record 2: %s", error);
}

//Pizza Delivery
public void OnPizzaPickup(int entity, int other)
{
	if (g_bBetweenRounds || g_bWaitingForPlayers)
		return;

	int time = GetTime();
	int client = other;

	if (!IsPlayerIndex(client) || (g_Player[client].triggerdelay > -1 && g_Player[client].triggerdelay > time))
		return;

	g_Player[client].triggerdelay = time + 3;

	char sSound[PLATFORM_MAX_PATH];

	if (GivePizzaBackpack(client))
	{
		FormatEx(sSound, sizeof(sSound), "ui/item_bag_pickup.wav");
		EmitSoundToClientSafe(client, sSound);

		int slot = GetActiveWeaponSlot(client);
		TF2_RegeneratePlayer(client);
		EquipWeaponSlot(client, slot);

		if (g_Player[client].laststop != INVALID_ENT_REFERENCE && GetRandomFloat(0.0, 1.0) > 0.60)
			SpeakResponseConceptDelayed(client, "TLK_TIRED", 0.4);

		PickDestination(client);
	}
	else
	{
		//Safety check to pick a destination if they have a pizza bag but no destination for some reason.
		if (!IsValidEntity(g_Player[client].destination))
			PickDestination(client);
		
		FormatEx(sSound, sizeof(sSound), "vo/heavy_no0%i.mp3", GetRandomInt(1, 3));
		EmitSoundToClientSafe(client, sSound);
	}

	FormatEx(sSound, sizeof(sSound), "vo/heavy_moveup0%i.mp3", GetRandomInt(1, 3));
	EmitSoundToClientSafeDelayed(client, sSound, 1.5);
}

void PickDestination(int client)
{
	if (g_Tutorial[client].tutorialstep > TUTORIAL_STEP_NONE)
	{
		int entity = -1; char sName[64];
		while ((entity = FindEntityByClassname(entity, "trigger_multiple")) != -1)
		{
			GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

			if (StrEqual(sName, "pizza_delivery_1", false) || StrEqual(sName, "pizza_delivery_01", false))
			{
				g_Player[client].destination = entity;
				break;
			}
		}

		return;
	}

	int destinations[128];
	int total;

	int entity = -1; char sName[64];
	while ((entity = FindEntityByClassname(entity, "trigger_multiple")) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

		if (StrContains(sName, "pizza_delivery", false) != 0)
			continue;
		
		if (g_Player[client].laststop == entity)
			continue;
		
		destinations[total++] = entity;
	}

	g_Player[client].destination = destinations[GetRandomInt(0, total - 1)];
}

bool GivePizzaBackpack(int client, bool kill = false)
{
	//Client already has pizza on their back.
	if (HasPizzaBackpack(client))
	{
		if (kill)
			KillPizzaBackpack(client);
		else
			return false;
	}

	//Originally, this was meant to be a simple prop_dynamic entity parented to the player with the 'flag' attachment but the pizza model wouldn't show up that way due to engine limitations Valve put into place. This is fine though as It adds a glow to the pack automatically and I can even make it spin a lot easier as well.
	int entity = CreateEntityByName("item_teamflag");

	if (IsValidEntity(entity))
	{
		float vecOrigin[3];
		GetClientAbsOrigin(client, vecOrigin);

		DispatchKeyValueVector(entity, "origin", vecOrigin);
		DispatchKeyValue(entity, "flag_model", PIZZA_MODEL);
		DispatchKeyValue(entity, "skin", TF2_GetClientTeam(client) == TFTeam_Red ? "0" : "1");
		DispatchSpawn(entity);

		//This isn't that noticable unless you're in the air in which case, it gives you a certain sense of momentum.
		AttachParticle(entity, "bombinomicon_airwaves");

		//Force the client to pick up the item_teamflag entity with the pizza bag model.
		if (g_hSDKPickup != null)
			SDKCall(g_hSDKPickup, entity, client, true);

		//SPINNY SPINNY
		SetVariantString("spin");
		AcceptEntityInput(entity, "SetAnimation");

		//Save the reference for this entity to the client.
		g_Player[client].pizza = EntIndexToEntRef(entity);

		//Mutation for supreme pizzas. (we have the entity index here so might as well do stuff here instead of in the if statement)
		if (g_bMutations[MUTATION_SUPREMEPIZZAS] && GetRandomInt(0, 10) > 8)
		{
			g_Player[client].supreme = true;

			DispatchKeyValue(entity, "skin", "2");

			char sSound[PLATFORM_MAX_PATH];
			FormatEx(sSound, sizeof(sSound), "items/scout_boombox_0%i.wav", GetRandomInt(2, 5));
			EmitSoundToClientSafe(client, sSound);
		}
	}

	return true;
}

void KillPizzaBackpack(int client)
{
	//Client doesn't have pizza currently.
	if (!HasPizzaBackpack(client))
		return;

	int pizzapack = EntRefToEntIndex(g_Player[client].pizza);

	if (IsValidEntity(pizzapack))
		AcceptEntityInput(pizzapack, "Kill");

	g_Player[client].pizza = INVALID_ENT_REFERENCE;

	//If we kill their pizza bag for some reason, there's no place to go anyways.
	g_Player[client].destination = -1;
}

bool HasPizzaBackpack(int client)
{
	return (g_Player[client].pizza != INVALID_ENT_REFERENCE);
}

public void OnPizzaDelivery(int entity, int other)
{
	int time = GetTime();
	int client = other;

	if (!IsPlayerIndex(client) || (g_Tutorial[client].tutorialstep != TUTORIAL_STEP_DELIVERY && g_Player[client].triggerdelay > -1 && g_Player[client].triggerdelay > time))
		return;

	if (g_Tutorial[client].tutorialstep == TUTORIAL_STEP_DELIVERY)
		g_Player[client].triggerdelay = time + 3;

	if (!HasPizzaBackpack(client) || g_Player[client].destination == -1 || g_Player[client].destination != entity)
		return;

	KillPizzaBackpack(client);

	//Save their last stop so we can skip this when going back to grab a new pizza bag.
	g_Player[client].laststop = EntIndexToEntRef(entity);

	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	//This is a really messy way of firing the logic_relay entity associated with the delivery zone, it works though.
	int entity2 = INVALID_ENT_INDEX; char sName2[64];
	while ((entity2 = FindEntityByClassname(entity2, "logic_relay")) != INVALID_ENT_INDEX)
	{
		GetEntPropString(entity2, Prop_Data, "m_iName", sName2, sizeof(sName2));

		if (StrContains(sName2, sName) != -1)
		{
			AcceptEntityInput(entity2, "Trigger");
			break;
		}
	}

	if (g_Tutorial[client].tutorialstep <= TUTORIAL_STEP_NONE)
	{
		if (g_Player[client].supreme)
		{
			g_Player[client].totalpizzas += 2;
			g_Airtime[client].rounddeliveriesrecord += 2;
		}
		else
		{
			g_Player[client].totalpizzas++;
			g_Airtime[client].rounddeliveriesrecord++;
		}

		if (g_iGamemodeType == GAMEMODE_TYPE_TEAMS)
		{
			SendAnnouncerTeamMessage();
		}

		if (g_Airtime[client].rounddeliveriesrecord > g_Airtime[client].currentdeliveriesrecord && !g_Airtime[client].recordcache)
		{
			EmitSoundToClientSafe(client, "misc/achievement_earned.wav");
			g_Airtime[client].recordcache = true;
		}
	}

	g_Player[client].supreme = false;

	char sSound[PLATFORM_MAX_PATH];

	FormatEx(sSound, sizeof(sSound), "ui/hitsound_retro%i.wav", GetRandomInt(1, 5));
	EmitSoundToClientSafe(client, sSound);

	FormatEx(sSound, sizeof(sSound), "ui/item_bag_drop.wav");
	EmitSoundToClientSafe(client, sSound);

	SpeakResponseConceptDelayed(client, "TLK_ACCEPT_DUEL", 1.0);

	if (g_Tutorial[client].tutorialstep > TUTORIAL_STEP_NONE && g_Tutorial[client].tutorialtimer == null)
		g_Tutorial[client].tutorialtimer = CreateTimer(2.5, Timer_NextTutorialStep, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

	if (g_iGamemodeType == GAMEMODE_TYPE_TEAMS)
	{
		int team = GetClientTeam(client);
		SetTeamScore(team, (GetTeamScore(team) + 1));

		EmitSoundToAllSafeDelayed("vo/announcer_secure.mp3", 0.8);
	}
}

void SendAnnouncerTeamMessage()
{
	int pizzas_red;
	int pizzas_blue;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i) || !IsClientInGame(i) || !IsPlayerAlive(i) || g_Player[i].totalpizzas < 1)
			continue;

		switch (TF2_GetClientTeam(i))
		{
			case TFTeam_Red: pizzas_red += g_Player[i].totalpizzas;
			case TFTeam_Blue: pizzas_blue += g_Player[i].totalpizzas;
		}
	}

	char sSound[PLATFORM_MAX_PATH];

	if (pizzas_red == pizzas_blue && GetRandomInt(0, 4) > 2)
	{
		EmitSoundToAllSafeDelayed("vo/announcer_stalemate.mp3", 0.4);
		return;
	}

	TFTeam lead;

	if (pizzas_red > pizzas_blue)
		lead = TFTeam_Red;
	else if (pizzas_red < pizzas_blue)
		lead = TFTeam_Blue;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i) || !IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		if (GetRandomInt(0, 5) > 3)
			continue;

		if (lead == TF2_GetClientTeam(i))
		{
			FormatEx(sSound, sizeof(sSound), "vo/announcer_dec_success0%i.mp3", GetRandomInt(1, 2));
			EmitSoundToClientSafeDelayed(i, sSound, 0.4);
		}
		else
		{
			FormatEx(sSound, sizeof(sSound), "vo/announcer_dec_failure0%i.mp3", GetRandomInt(1, 2));
			EmitSoundToClientSafeDelayed(i, sSound, 0.4);
		}
	}
}

void SetHudScore(int client, int score, bool updatehud = true)
{
	if (!IsPlayerIndex(client))
		return;

	g_Player[client].totalpizzas = ClampCell(score, 0, 99999);

	//Due to how the millisecond timer is setup, this isn't as needed but it's still nice to update as soon as your total deliveries increases.
	if (updatehud && IsClientInGame(client))
	{
		char sRecord[32];

		if (g_Airtime[client].currentdeliveriesrecord > 0)
			FormatEx(sRecord, sizeof(sRecord), " [Record: %i]", g_Airtime[client].currentdeliveriesrecord);

		SetHudTextParams(0.01, 0.09, 99999.0, 91, 255, 51, 225, g_Tutorial[client].flashtext > 0 ? 2 : 0, 1.0, 0.0, 0.0);
		ShowSyncHudText(client, g_hSync_Score, "Deliveries: %i%s", g_Player[client].totalpizzas, sRecord);
	}
}

//Airtime
void StartTimer(int client)
{
	if (g_Tutorial[client].tutorialstep > TUTORIAL_STEP_NONE)
		return;

	g_Airtime[client].starttime = GetEngineTime();
	g_Airtime[client].timing = true;

	CreateSpriteTrail(client);

	StopTimer(g_Airtime[client].airtimesound);
	g_Airtime[client].airtimesound = CreateTimer(8.0, Timer_RepeatAirSound, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	TriggerTimer(g_Airtime[client].airtimesound, true);
}

public Action Timer_RepeatAirSound(Handle timer, any data)
{
	int client = data;

	if (IsPlayerIndex(client) && IsPlayerAlive(client) && g_Airtime[client].timing)
	{
		float vecOrigin[3];
		GetClientAbsOrigin(client, vecOrigin);

		EmitAmbientSoundSafe("ambient/desert_wind.wav", vecOrigin);	//Bugged
	}
}

float FinishTimer(int client)
{
	float fFinishTime = GetEngineTime() - g_Airtime[client].starttime;
	HaltTimer(client);

	KillSpriteTrail(client);

	StopTimer(g_Airtime[client].airtimesound);
	StopSoundSafeAll(client, "ambient/desert_wind.wav");

	return fFinishTime;
}

void HaltTimer(int client)
{
	g_Airtime[client].timing = false;
}

void CreateSpriteTrail(int client)
{
	KillSpriteTrail(client);

	char ClientName[128];
	Format(ClientName, sizeof(ClientName), "customname_%i", client);
	DispatchKeyValue(client, "targetname", ClientName);

	int entity = CreateEntityByName("env_spritetrail");
	DispatchKeyValue(entity, "renderamt", "255");
	DispatchKeyValue(entity, "rendermode", "1");
	DispatchKeyValue(entity, "spritename", "materials/sprites/spotlight.vmt");
	DispatchKeyValue(entity, "lifetime", "3.0");
	DispatchKeyValue(entity, "startwidth", "5.0");
	DispatchKeyValue(entity, "endwidth", "0.1");
	DispatchKeyValue(entity, "rendercolor", "255 255 0");
	DispatchSpawn(entity);

	float CurrentOrigin[3];
	GetClientAbsOrigin(client, CurrentOrigin);

	CurrentOrigin[2] += 5.0;	//5.0 seems to be the noticable amount where you can see it in the right times but have it not get in your way entirely.

	TeleportEntity(entity, CurrentOrigin, NULL_VECTOR, NULL_VECTOR);
	SetVariantString(ClientName);

	AcceptEntityInput(entity, "SetParent", -1, -1);
	AcceptEntityInput(entity, "showsprite", -1, -1);

	g_Airtime[client].spritetrail = EntIndexToEntRef(entity);
}

void KillSpriteTrail(int client)
{
	int entity = EntRefToEntIndex(g_Airtime[client].spritetrail);

	if (IsValidEntity(entity))
		AcceptEntityInput(entity, "Kill");

	g_Airtime[client].spritetrail = INVALID_ENT_REFERENCE;
}

void FormatPlayerTime(float Time, char[] result, int maxlength, bool showDash, int precision)
{
	if (Time <= 0.0 && showDash == true)
	{
		Format(result, maxlength, "-");
		return;
	}

	int hours = RoundToFloor(Time / 3600);
	Time -= hours * 3600;
	int minutes = RoundToFloor(Time / 60);
	Time -= minutes*60;
	float seconds = Time;

	char sPrecision[16];

	if(precision == 0)
		Format(sPrecision, sizeof(sPrecision), (hours > 0 || minutes > 0)?"%04.1f":"%.1f", seconds);
	else if(precision == 1)
		Format(sPrecision, sizeof(sPrecision), (hours > 0 || minutes > 0)?"%06.3f":"%.3f", seconds);
	else if(precision == 2)
		Format(sPrecision, sizeof(sPrecision), (hours > 0 || minutes > 0)?"%09.6f":"%.6f", seconds);

	if(hours > 0)
		Format(result, maxlength, "%d:%02d:%s", hours, minutes, sPrecision);
	else if(minutes > 0)
		Format(result, maxlength, "%d:%s", minutes, sPrecision);
	else
		Format(result, maxlength, "%s", sPrecision);
}

public Action Command_MainMenu(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	OpenMainMenu(client);
	return Plugin_Handled;
}

void OpenMainMenu(int client)
{
	Menu menu = new Menu(MenuHandler_MainMenu);
	menu.SetTitle("Hungry Heavy Delivery");

	menu.AddItem("records", "Top Records");
	menu.AddItem("how", "How to Play");
	menu.AddItem("credits", "Credits");
	menu.AddItem("tutorial", "Start Tutorial Scenario");
	AddMenuItemFormat(menu, "gender", ITEMDRAW_DEFAULT, "Toggle Gender [%s]", g_Player[client].isfemale ? "Female" : "Male");
	AddMenuItemFormat(menu, "music", ITEMDRAW_DEFAULT, "Play Music [%s]", g_Player[client].backgroundmusic ? "ON" : "OFF");

	menu.Display(client, 30);
}

public int MenuHandler_MainMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "records"))
				OpenRecordsMenu(param1);
			else if (StrEqual(sInfo, "how"))
				OpenHowToMenu(param1);
			else if (StrEqual(sInfo, "credits"))
				OpenCreditsPanel(param1);
			else if (StrEqual(sInfo, "tutorial"))
				OpenTutorialMenu(param1);
			else if (StrEqual(sInfo, "gender"))
			{
				ToggleGender(param1);
				OpenMainMenu(param1);
			}
			else if (StrEqual(sInfo, "music"))
			{
				ToggleMusic(param1);
				OpenMainMenu(param1);
			}
		}

		case MenuAction_End:
			delete menu;
	}
}

void OpenHowToMenu(int client)
{
	Panel panel = new Panel();

	//Having a video to show how things work is good but this will do for now.
	panel.DrawText("*(The goal of this gamemode is to deliver pizzas as fast as possible.");
	panel.DrawText("*(You will run into obstacles that could kill you along the way.");
	panel.DrawText("*(Other players can interrupt your speed by damage.");
	panel.DrawText("*(Your primary weapon makes you go backwards, your secondary makes you go forwards and your melee makes you go upwards.");
	panel.DrawItem("Back to Menu");

	panel.Send(client, MenuHandler_Void, MENU_TIME_FOREVER);

	char sLaugh[PLATFORM_MAX_PATH];
	FormatEx(sLaugh, sizeof(sLaugh), "vo/heavy_laughhappy0%i.mp3", GetRandomInt(1, 5));
	EmitSoundToClientSafeDelayed(client, sLaugh, 0.5);
}

public int MenuHandler_Void(Menu menu, MenuAction action, int param1, int param2)
{
	OpenMainMenu(param1);
	delete menu;
}

public void TF2_OnWaitingForPlayersStart()
{
	g_bWaitingForPlayers = true;
}

public void TF2_OnWaitingForPlayersEnd()
{
	g_bWaitingForPlayers = false;
}

public Action Command_ToggleGender(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	ToggleGender(client);
	return Plugin_Handled;
}

void ToggleGender(int client)
{
	g_Player[client].isfemale = !g_Player[client].isfemale;

	char sValue[12];
	IntToString(g_Player[client].isfemale, sValue, sizeof(sValue));

	SetClientCookie(client, g_hCookie_IsFemale, sValue);
	CPrintToChat(client, "%s Gender swapped to %s.", PLUGIN_TAG_COLORED, g_Player[client].isfemale ? "Female" : "Male");

	if (IsPlayerAlive(client))
		SetModel(client, g_Player[client].isfemale ? "models/player/scout_female.mdl" : "models/player/scout.mdl");
	
	char sAward[PLATFORM_MAX_PATH];
	FormatEx(sAward, sizeof(sAward), g_Player[client].isfemale ? "vo/female_scout/scout_award0%i.mp3" : "vo/scout_award0%i.mp3", GetRandomInt(1, 9));
	EmitSoundToClientSafe(client, sAward);
}

public Action Command_ShowCredits(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	OpenCreditsPanel(client, false);
	return Plugin_Handled;
}

void OpenCreditsPanel(int client, bool back = true)
{
	Panel panel = new Panel();
	panel.SetTitle(" - Mod Credits - ");
	panel.DrawText(" - Drixevel (Developer)");
	panel.DrawText(" - Sega (Jet Set Radio Music)");
	panel.DrawText(" - Mzullos5 (Mapping Help)");
	panel.DrawText(" - TheXeon (Developer - Syntax Updates)");
	panel.DrawText(" - Pelipoika (Code Suggestions)");
	panel.DrawText(" - AyesDyef (Female Scout Model)");
	panel.DrawText(" - DustyOldRoses (Female Scout Lines)");
	panel.DrawText(" - Bigwig (Original BigCity Map)");
	panel.DrawText(" - TF2Maps/GameBanana (Misc Map Contents)");
	panel.DrawText(" - Cole Zaveri (Testing)");
	panel.DrawText(" - Barren Reality (Testing)");
	
	if (back)
		panel.DrawItem("Back");
	
	panel.Send(client, MenuHandler_Credits, 30);

	char sThanks[PLATFORM_MAX_PATH];
	FormatEx(sThanks, sizeof(sThanks), "vo/heavy_thanks0%i.mp3", GetRandomInt(1, 3));
	EmitSoundToClientSafeDelayed(client, sThanks, 1.0);
}

public int MenuHandler_Credits(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
			if (param2 == 1)
				OpenMainMenu(param1);
		case MenuAction_End:
			delete menu;
	}
}

public Action Command_Records(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	OpenRecordsMenu(client, false);
	return Plugin_Handled;
}

void OpenRecordsMenu(int client, bool back = true)
{
	Menu menu = new Menu(MenuHandler_Records);
	menu.SetTitle("Current and top records:");

	menu.AddItem("top_airtime", "Top Airtimes for this map");
	menu.AddItem("top_deliveries", "Top Deliveries for this map");
	menu.AddItem("reset_airtime", "Reset Airtime Record for this map");
	menu.AddItem("reset_deliveries", "Reset Deliveries Record for this map");

	menu.ExitBackButton = back;
	menu.Display(client, 30);
}

public int MenuHandler_Records(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "top_airtime"))
				OpenTopAirtimes(param1);
			else if (StrEqual(sInfo, "top_deliveries"))
				OpenTopDeliveries(param1);
			else if (StrEqual(sInfo, "reset_airtime"))
				ResetAirtimeRecord(param1);
			else if (StrEqual(sInfo, "reset_deliveries"))
				ResetDeliveryRecord(param1);
		}

		case MenuAction_Cancel:
			if (param2 == MenuCancel_ExitBack)
				OpenMainMenu(param1);

		case MenuAction_End:
			delete menu;
	}
}

public Action Command_TopAirtimes(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	OpenTopAirtimes(client);
	return Plugin_Handled;
}

void OpenTopAirtimes(int client)
{
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT name, record_airtime FROM `hungry_heavy_delivery_records` WHERE map = '%s' ORDER BY record_airtime DESC LIMIT 0,25;", sCurrentMap);
	g_Database.Query(TQuery_OnShowTopAirtimes, sQuery, GetClientUserId(client));
}

public void TQuery_OnShowTopAirtimes(Database owner, DBResultSet hndl, const char[] error, any data)
{
	if (hndl == null)
		ThrowError("Error retrieving top airtime records for map '%s': %s", sCurrentMap, error);

	int client;

	if ((client = GetClientOfUserId(data)) == 0)
		return;

	Menu menu = new Menu(MenuHandler_TopAirtimes);
	menu.SetTitle("Top Airtimes for '%s':", sCurrentMap);

	char sName[MAX_NAME_LENGTH]; float record; char sRecord[64];
	while (hndl.FetchRow())
	{
		hndl.FetchString(0, sName, sizeof(sName));
		record = hndl.FetchFloat(1);

		if (strlen(sName) == 0 || record <= 0.0)
			continue;

		FormatPlayerTime(record, sRecord, sizeof(sRecord), true, 1);
		AddMenuItemFormat(menu, "", ITEMDRAW_DISABLED, "%s: %s", sName, sRecord);
	}

	if (GetMenuItemCount(menu) == 0)
		menu.AddItem("", "[No Times Recorded]", ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, 30);

	char sWinning[PLATFORM_MAX_PATH];
	FormatEx(sWinning, sizeof(sWinning), "vo/heavy_yes0%i.mp3", GetRandomInt(1, 3));
	EmitSoundToClientSafeDelayed(client, sWinning, 0.5);
}

public int MenuHandler_TopAirtimes(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
			OpenMainMenu(param1);

		case MenuAction_Cancel:
			if (param2 == MenuCancel_ExitBack)
				OpenRecordsMenu(param1, menu.ExitBackButton);

		case MenuAction_End:
			delete menu;
	}
}

public Action Command_ResetAirtimeRecord(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	ResetAirtimeRecord(client);
	return Plugin_Handled;
}

void ResetAirtimeRecord(int client)
{
	Menu menu = new Menu(MenuHandler_ResetAirtimeRecords);
	menu.SetTitle("Are you sure?\nThis would reset your airtime record for this map only.");
	menu.AddItem("yes", "Yes");
	menu.AddItem("no", "No");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ResetAirtimeRecords(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "yes"))
			{
				if (g_Database != null)
				{
					char sSteamID[32];
					GetClientAuthId(param1, AuthId_Steam2, sSteamID, sizeof(sSteamID));

					char sQuery[256];
					g_Database.Format(sQuery, sizeof(sQuery), "UPDATE `hungry_heavy_delivery_records` SET record_airtime = '0.0' WHERE steamid = '%s' AND map = '%s';", sSteamID, sCurrentMap);
					g_Database.Query(onUpdateRecord, sQuery);

					g_Airtime[param1].currentairtimerecord = 0.0;
					CPrintToChat(param1, "%s You have reset your airtime record for this map successfully.", PLUGIN_TAG_COLORED);
				}
				else
					CPrintToChat(param1, "%s Failure resetting your airtime record, please try again soon.", PLUGIN_TAG_COLORED);
			}

			OpenMainMenu(param1);
		}

		case MenuAction_Cancel:
			if (param2 == MenuCancel_ExitBack)
				OpenRecordsMenu(param1, menu.ExitBackButton);

		case MenuAction_End:
			delete menu;
	}
}

public void onUpdateRecord(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
		ThrowError("Error while updating record: %s", error);
}

public Action Command_TopDeliveries(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	OpenTopDeliveries(client);
	return Plugin_Handled;
}

void OpenTopDeliveries(int client)
{
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT name, record_deliveries FROM `hungry_heavy_delivery_records` WHERE map = '%s' ORDER BY record_deliveries DESC LIMIT 0,25;", sCurrentMap);
	g_Database.Query(TQuery_OnShowTopDeliveries, sQuery, GetClientUserId(client));
}

public void TQuery_OnShowTopDeliveries(Database owner, DBResultSet hndl, const char[] error, any data)
{
	if (hndl == null)
		ThrowError("Error retrieving top delivery records for map '%s': %s", sCurrentMap, error);

	int client;
	if ((client = GetClientOfUserId(data)) == 0)
		return;

	Menu menu = new Menu(MenuHandler_TopDeliveryTimes);
	menu.SetTitle("Top Deliveries for '%s':", sCurrentMap);

	char sName[MAX_NAME_LENGTH]; int record;
	while (hndl.FetchRow())
	{
		hndl.FetchString(0, sName, sizeof(sName));
		record = hndl.FetchInt(1);

		if (strlen(sName) == 0 || record <= 0)
			continue;

		AddMenuItemFormat(menu, "", ITEMDRAW_DISABLED, "%s: %i", sName, record);
	}

	if (menu.ItemCount == 0)
		menu.AddItem("", "[No Amounts Recorded]", ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, 30);

	char sWinning[PLATFORM_MAX_PATH];
	FormatEx(sWinning, sizeof(sWinning), "vo/heavy_yes0%i.mp3", GetRandomInt(1, 3));
	EmitSoundToClientSafeDelayed(client, sWinning, 0.5);
}

public int MenuHandler_TopDeliveryTimes(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
			OpenMainMenu(param1);

		case MenuAction_Cancel:
			if (param2 == MenuCancel_ExitBack)
				OpenRecordsMenu(param1, menu.ExitBackButton);

		case MenuAction_End:
			delete menu;
	}
}

public Action Command_ResetDeliveryRecord(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	ResetDeliveryRecord(client);
	return Plugin_Handled;
}

void ResetDeliveryRecord(int client)
{
	Menu menu = new Menu(MenuHandler_ResetDeliveryRecords);
	menu.SetTitle("Are you sure?\nThis would reset your delivery record for this map only.");
	menu.AddItem("yes", "Yes");
	menu.AddItem("no", "No");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ResetDeliveryRecords(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "yes"))
			{
				if (g_Database != null)
				{
					char sSteamID[32];
					GetClientAuthId(param1, AuthId_Steam2, sSteamID, sizeof(sSteamID));

					char sQuery[256];
					g_Database.Format(sQuery, sizeof(sQuery), "UPDATE `hungry_heavy_delivery_records` SET record_deliveries = '0' WHERE steamid = '%s' AND map = '%s';", sSteamID, sCurrentMap);
					g_Database.Query(onUpdateRecord2, sQuery);

					g_Airtime[param1].currentdeliveriesrecord = 0;
					CPrintToChat(param1, "%s You have reset your delivery record for this map successfully.", PLUGIN_TAG_COLORED);
				}
				else
					CPrintToChat(param1, "%s Failure resetting your delivery record, please try again soon.", PLUGIN_TAG_COLORED);
			}

			OpenMainMenu(param1);
		}

		case MenuAction_Cancel:
			if (param2 == MenuCancel_ExitBack)
				OpenRecordsMenu(param1, menu.ExitBackButton);

		case MenuAction_End:
			delete menu;
	}
}

public void onUpdateRecord2(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
		ThrowError("Error while updating record 2: %s", error);
}

public Action Command_ToggleMusic(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	ToggleMusic(client);
	return Plugin_Handled;
}

void ToggleMusic(int client)
{
	g_Player[client].backgroundmusic = !g_Player[client].backgroundmusic;
	SetClientCookie(client, g_hCookie_ToggleMusic, g_Player[client].backgroundmusic ? "1" : "0");
	CPrintToChat(client, "%s You have toggled music %s.", PLUGIN_TAG_COLORED, g_Player[client].backgroundmusic ? "on" : "off");

	if (g_Player[client].backgroundmusic) PlayBackgroundMusic(client);
	else StopBackgroundMusic(client);
}

void OpenCurrentAirtimeRecords(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return;

	Menu menu = new Menu(MenuHandler_CurrentTimes);
	menu.SetTitle("Airtime records for this round:");

	float record; char sRecord[64];
	for (int i = 1; i <= MaxClients; i++)
	{
		record = g_Airtime[i].roundairtimerecord;

		if (!IsClientInGame(i) || record <= 0.0)
			continue;

		FormatPlayerTime(record, sRecord, sizeof(sRecord), true, 1);
		AddMenuItemFormat(menu, "", ITEMDRAW_DISABLED, "%N: %s", i, sRecord);
	}

	menu.Display(client, 15);
}

public int MenuHandler_CurrentTimes(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;
	}
}

void OpenCurrentDeliveryTimes(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return;

	Menu menu = new Menu(MenuHandler_CurrentDeliveryRecords);
	menu.SetTitle("Delivery records for this round:");

	int record;
	for (int i = 1; i <= MaxClients; i++)
	{
		record = g_Airtime[i].rounddeliveriesrecord;

		if (!IsClientInGame(i) || record <= 0)
			continue;

		AddMenuItemFormat(menu, "", ITEMDRAW_DISABLED, "%N: %i", i, record);
	}

	menu.Display(client, 15);
}

public int MenuHandler_CurrentDeliveryRecords(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;
	}
}

public Action Command_Tutorial(int client, int args)
{
	if (g_bBetweenRounds || g_bPlayersFrozen || g_bWaitingForPlayers)
	{
		CPrintToChat(client, "%s You cannot use this command yet.", PLUGIN_TAG_COLORED);
		return Plugin_Handled;
	}

	OpenTutorialMenu(client);
	return Plugin_Handled;
}

void StartTutorial(int client)
{
	g_Tutorial[client].tutorialstep = TUTORIAL_STEP_PISTOL;
	g_Tutorial[client].climbamount = 0;

	LoadTutorialStep(client);
}

void ClearTutorial(int client)
{
	g_Tutorial[client].tutorialstep = TUTORIAL_STEP_NONE;
	g_Tutorial[client].climbamount = 0;
	StopTimer(g_Tutorial[client].tutorialtimer);
}

void LoadTutorialStep(int client)
{
	StopTimer(g_Tutorial[client].tutorialtimer);

	if (g_bBetweenRounds || g_bPlayersFrozen || g_bWaitingForPlayers)
	{
		ClearTutorial(client);
		return;
	}

	KillPizzaBackpack(client);

	switch (g_Tutorial[client].tutorialstep)
	{
		case TUTORIAL_STEP_PISTOL:
		{
			ShowOverlay(client, OVERLAY_TUTORIAL_01);
			EquipWeaponSlot(client, 1);
			TeleportToDestination(client, "tutorial_start_point");
		}
		case TUTORIAL_STEP_FAN:
		{
			ShowOverlay(client, OVERLAY_TUTORIAL_02);
			EquipWeaponSlot(client, 0);
			TeleportToDestination(client, "tutorial_start_point");
		}
		case TUTORIAL_STEP_CLIMB:
		{
			ShowOverlay(client, OVERLAY_TUTORIAL_03);
			EquipWeaponSlot(client, 2);
			TeleportToDestination(client, "tutorial_melee_point");
		}
		case TUTORIAL_STEP_DELIVERY:
		{
			ShowOverlay(client, OVERLAY_TUTORIAL_04);
			TeleportToDestination(client, "tutorial_delivery_point");
			GivePizzaBackpack(client, true);
			PickDestination(client);
			EquipWeaponSlot(client, 0);
		}
		case TUTORIAL_STEP_FINISH:
		{
			ShowOverlay(client, OVERLAY_TUTORIAL_05, 3.5);
			TF2_RespawnPlayer(client);

			ClearTutorial(client);

			SetClientCookie(client, g_hCookie_TutorialPlayed, "1");
			g_Tutorial[client].tutorialplayed = true;

			g_Tutorial[client].flashtext = 250;
		}
	}

	char sWinning[PLATFORM_MAX_PATH];
	FormatEx(sWinning, sizeof(sWinning), "vo/heavy_yes0%i.mp3", GetRandomInt(1, 3));
	EmitSoundToClientSafeDelayed(client, sWinning, 0.5);
}

void OpenTutorialMenu(int client)
{
	Menu menu = new Menu(MenuHandler_TutorialMenu);
	menu.SetTitle("Would you like to play the tutorial%s?", g_Tutorial[client].tutorialplayed ? " again" : "");
	menu.AddItem("yes", "Yes");
	menu.AddItem("no", "No");
	menu.Display(client, 15);
}

public int MenuHandler_TutorialMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[12];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "yes"))
				StartTutorial(param1);
		}

		case MenuAction_End:
			delete menu;
	}
}

public Action Command_SetGamemode(int client, int args)
{
	if (client == 0 || args > 0)
	{
		char sGamemode[64];
		GetCmdArgString(sGamemode, sizeof(sGamemode));

		int queue = GAMEMODE_TYPE_NONE;

		if (IsStringNumeric(sGamemode))
		{
			queue = StringToInt(sGamemode);

			if (queue < 0 || queue > GAMEMODE_TYPES)
			{
				CReplyToCommand(client, "%s You cannot specify a gamemode ID below zero or above %i.", PLUGIN_TAG, GAMEMODE_TYPES);
				return Plugin_Handled;
			}
		}
		else
		{
			char sGamemodeList[64];
			for (int i = 1; i <= GAMEMODE_TYPES; i++)
			{
				GetGamemodeName(i, sGamemodeList, sizeof(sGamemodeList));

				if (StrContains(sGamemode, sGamemodeList, false) != -1)
				{
					queue = i;
					break;
				}
			}

			if (queue == GAMEMODE_TYPE_NONE)
			{
				CReplyToCommand(client, "%s You have specified an invalid gamemode name.", PLUGIN_TAG);
				return Plugin_Handled;
			}
		}

		if (queue != GAMEMODE_TYPE_NONE)
		{
			g_iQueuedGamemode = queue;
			GetGamemodeName(g_iQueuedGamemode, sGamemode, sizeof(sGamemode));

			CReplyToCommand(client, "%s You have queued up the gamemode: %s", PLUGIN_TAG, sGamemode);
			CPrintToChatAll("%s %N has queued the gamemode: %s", PLUGIN_TAG_COLORED, client, sGamemode);
		}

		return Plugin_Handled;
	}

	OpenSetGamemodeMenu(client);
	return Plugin_Handled;
}

void OpenSetGamemodeMenu(int client)
{
	Menu menu = new Menu(MenuHandler_SetGamemode);
	menu.SetTitle("Pick a gamemode for next round:");

	char sID[12]; char sName[64];
	for (int i = 1; i <= GAMEMODE_TYPES; i++)
	{
		IntToString(i, sID, sizeof(sID));
		GetGamemodeName(i, sName, sizeof(sName));
		menu.AddItem(sID, sName);
	}

	menu.Display(client, 30);
}

public int MenuHandler_SetGamemode(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sID[12]; char sName[64];
			menu.GetItem(param2, sID, sizeof(sID), _, sName, sizeof(sName));

			g_iQueuedGamemode = StringToInt(sID);
			CPrintToChatAll("%s %N has queued the gamemode: %s", PLUGIN_TAG_COLORED, param1, sName);
		}

		case MenuAction_End:
			delete menu;
	}
}

public Action Command_SetMutations(int client, int args)
{
	if (client == 0 || args > 0)
	{
		char sMutation[64];
		GetCmdArgString(sMutation, sizeof(sMutation));

		int mutation = -1;

		if (IsStringNumeric(sMutation))
		{
			mutation = StringToInt(sMutation);

			if (mutation < 0 || mutation > MUTATIONS_TOTAL)
			{
				CReplyToCommand(client, "%s You cannot specify a mutation ID below zero or above %i.", PLUGIN_TAG, MUTATIONS_TOTAL);
				return Plugin_Handled;
			}
		}
		else
		{
			char sMutationList[64];
			for (int i = 1; i <= MUTATIONS_TOTAL; i++)
			{
				GetMutationName(i, sMutationList, sizeof(sMutationList));

				if (StrContains(sMutation, sMutationList, false) != -1)
				{
					mutation = i;
					break;
				}
			}

			if (mutation == -1)
			{
				CReplyToCommand(client, "%s You have specified an invalid mutation name.", PLUGIN_TAG);
				return Plugin_Handled;
			}
		}

		if (mutation != -1)
		{
			g_bMutations[mutation] = !g_bMutations[mutation];
			GetMutationName(mutation, sMutation, sizeof(sMutation));

			CReplyToCommand(client, "%s You have toggled the mutation %s to %s.", PLUGIN_TAG, sMutation, g_bMutations[mutation] ? "ON" : "OFF");
			CPrintToChatAll("%s %N has toggled the %s mutation: %s", PLUGIN_TAG_COLORED, client, sMutation, g_bMutations[mutation] ? "ON" : "OFF");
		}

		return Plugin_Handled;
	}

	OpenToggleMutationsMenu(client);
	return Plugin_Handled;
}

void OpenToggleMutationsMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ToggleMutation);
	menu.SetTitle("Toggle a mutation on/off:");

	char sID[12]; char sName[64];
	for (int i = 0; i < sizeof(g_bMutations); i++)
	{
		IntToString(i, sID, sizeof(sID));
		GetMutationName(i, sName, sizeof(sName));
		AddMenuItemFormat(menu, sID, ITEMDRAW_DEFAULT, "%s (%s)", sName, g_bMutations[i] ? "ON" : "OFF");
	}

	menu.Display(client, 30);
}

public int MenuHandler_ToggleMutation(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sID[12]; char sName[64];
			menu.GetItem(param2, sID, sizeof(sID), _, sName, sizeof(sName));
			int mutation = StringToInt(sID);

			g_bMutations[mutation] = !g_bMutations[mutation];
			CPrintToChatAll("%s %N has toggled the %s mutation: %s", PLUGIN_TAG_COLORED, param1, sName, g_bMutations[mutation] ? "ON" : "OFF");

			OpenToggleMutationsMenu(param1);
		}

		case MenuAction_End:
			delete menu;
	}
}

public Action Command_EndGame(int client, int args)
{
	TF2_ForceWin(TFTeam_Unassigned);
	CPrintToChatAll("%s %N has ended the round!", PLUGIN_TAG_COLORED, client);
	return Plugin_Handled;
}

stock void CreateTF2Timer(int timer)
{
	int entity = FindEntityByClassname(-1, "team_round_timer");

	if (!IsValidEntity(entity))
		entity = CreateEntityByName("team_round_timer");

	char sTime[32];
	IntToString(timer, sTime, sizeof(sTime));
	
	DispatchKeyValue(entity, "reset_time", "1");
	DispatchKeyValue(entity, "auto_countdown", "0");
	DispatchKeyValue(entity, "timer_length", sTime);
	DispatchSpawn(entity);

	AcceptEntityInput(entity, "Resume");

	SetVariantInt(1);
	AcceptEntityInput(entity, "ShowInHUD");
}

stock void PauseTF2Timer()
{
	int entity = FindEntityByClassname(-1, "team_round_timer");

	if (!IsValidEntity(entity))
		entity = CreateEntityByName("team_round_timer");
	
	AcceptEntityInput(entity, "Pause");
}

stock void UnpauseTF2Timer()
{
	int entity = FindEntityByClassname(-1, "team_round_timer");

	if (!IsValidEntity(entity))
		entity = CreateEntityByName("team_round_timer");
	
	AcceptEntityInput(entity, "Resume");
}

public bool TraceFilterNotSelf(int entityhit, int mask, any entity)
{
	if (entity == 0 && entityhit != entity)
		return true;
	
	return false;
}

public bool TraceEntityFilterSolid(int entityhit, int contentsMask, int entity) 
{
	if (entityhit > MaxClients && entityhit != entity)
		return true;
	
	return false;
}

void MapCircleToSquare(float out[3], const float input[3]) 
{ 
	float x = input[0], y = input[1]; 
	float nx, ny; 
	
	if(x < 0.000002 && x > -0.000002) 
	{ 
		nx = 0.0; 
		ny = y; 
	} 
	else if(y < 0.000002 && y > -0.000002) 
	{ 
		nx = x; 
		ny = 0.0; 
	} 
	else if (y > 0.0) 
	{ 
		if (x > 0.0) 
		{ 
			if (x < y) 
			{ 
				nx = x / y; 
				ny = 1.0; 
			} 
			else 
			{ 
				nx = 1.0; 
				ny = y / x; 
			} 
		} 
		else 
		{ 
			if (x < -y) 
			{ 
				nx = -1.0; 
				ny = -(y / x); 
			} 
			else 
			{ 
				nx = x / y; 
				ny = 1.0; 
			} 
		} 
	}
	else 
	{ 
		if (x > 0.0) 
		{ 
			if (-x > y) 
			{
				nx = -(x / y); 
				ny = -1.0; 
			} 
			else 
			{ 
				nx = 1.0; 
				ny = (y / x); 
			} 
		} 
		else 
		{ 
			if (x < y) 
			{ 
				nx = -1.0; 
				ny = -(y / x); 
			} 
			else 
			{ 
				nx = -(x / y); 
				ny = -1.0; 
			} 
		} 
	}
	
	out[0] = nx; 
	out[1] = ny; 
}  