/*
 * Official resource topic: https://dev-cs.ru/resources/635/
 */

#include <amxmodx>
#include <amxmisc>
#include <reapi>

#pragma semicolon 1

public stock const PluginName[] = "Hook";
public stock const PluginVersion[] = "3.0.1";
public stock const PluginAuthor[] = "twisterniq (and dust)";
public stock const PluginURL[] = "https://github.com/twisterniq/amxx-hook-trail";
public stock const PluginDescription[] = "Adds the ability to use a hook. It provides an API.";

new const CONFIG_NAME[] = "hook";

const TASK_ID_HOOK = 100;

enum _:CVARS
{
	CVAR_FLAGS[ 20 ],
	Float:CVAR_DEFAULT_SPEED
};

new g_eCvar[CVARS];


new bool:g_bCanUseHook[MAX_PLAYERS + 1];
new g_iHookOrigin[MAX_PLAYERS + 1][3];
new bool:g_bHookUse[MAX_PLAYERS + 1];
new bool:g_bNeedRefresh[MAX_PLAYERS + 1];
new Float:g_flHookSpeed[MAX_PLAYERS + 1];
new Float:g_fOldGrav[ MAX_PLAYERS + 1 ];
public plugin_precache()
{
#if AMXX_VERSION_NUM == 190
	register_plugin(
		.plugin_name = PluginName,
		.version = PluginVersion,
		.author = PluginAuthor);
#elseif AMXX_VERSION_NUM >= 200
    register_plugin(
        PluginName,
        PluginVersion,
        PluginAuthor, 
        PluginURL,
        PluginDescription
    );
#endif
}
public plugin_init()
{
	register_dictionary("hook.txt");

	register_clcmd("+hook", "@func_HookEnable");
	register_clcmd("-hook", "@func_HookDisable");

	RegisterHookChain(RG_CSGameRules_PlayerSpawn, "@OnPlayerSpawn_Post", true);
	RegisterHookChain(RG_CBasePlayer_Killed, "@OnPlayerKilled_Post", true);
	bind_pcvar_float(create_cvar(
		.name = "hook_default_speed",
		.string = "800.0",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER, "HOOK_CVAR_DEFAULT_SPEED"),
		.has_min = true,
		.min_val = 1.0), g_eCvar[CVAR_DEFAULT_SPEED]);

	bind_pcvar_string( create_cvar( "hook_flags", "d" ), g_eCvar[CVAR_FLAGS], charsmax( g_eCvar[CVAR_FLAGS] ) );
	AutoExecConfig(true, CONFIG_NAME);

	new szPath[PLATFORM_MAX_PATH];
	get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
	server_cmd("exec %s/plugins/%s.cfg", szPath, CONFIG_NAME);
	server_exec();

	arrayset(g_flHookSpeed, g_eCvar[CVAR_DEFAULT_SPEED], sizeof g_flHookSpeed);

	new iEnt = rg_create_entity("info_target", true);

	if (iEnt)
	{
		SetThink(iEnt, "@think_Hook");
		set_entvar(iEnt, var_nextthink, get_gametime() + 0.1);
	}
}

public client_disconnected(id)
{
	g_bHookUse[id] = false;
	g_bCanUseHook[id] = false;
	remove_task(id+TASK_ID_HOOK);
	g_flHookSpeed[id] = g_eCvar[CVAR_DEFAULT_SPEED];
}
public client_putinserver( id )
{
	g_bCanUseHook[ id ] = (get_user_flags( id ) & read_flags(g_eCvar[CVAR_FLAGS]))? true:false; 
}
@OnPlayerSpawn_Post(const id)
{
	if (is_user_alive(id))
	{
		g_bHookUse[id] = false;
	}
}

@OnPlayerKilled_Post(const iVictim)
{
	g_bHookUse[iVictim] = false;
	remove_task(iVictim+TASK_ID_HOOK);
}

@func_HookEnable(const id)
{
	if (!is_user_alive(id))
	{
		return PLUGIN_HANDLED;
	}

	if (!g_bCanUseHook[id])
	{
		client_print_color(id, print_team_red, "%l", "HOOK_ERROR_ACCESS");
		return PLUGIN_HANDLED;
	}

	
	if( !g_bHookUse[ id ] )
		get_entvar( id, var_gravity, g_fOldGrav[ id ] );
	g_bHookUse[id] = true;
	get_user_origin(id, g_iHookOrigin[id], Origin_AimEndEyes);

	if (!task_exists(id+TASK_ID_HOOK))
	{
		set_task_ex(0.1, "@task_HookWings", id+TASK_ID_HOOK, .flags = SetTask_Repeat);
	}

	return PLUGIN_HANDLED;
}

@func_HookDisable(const id)
{
	if (g_bHookUse[id])
	{
		g_bHookUse[id] = false;
		set_entvar( id, var_gravity, g_fOldGrav[ id ] );
	}

	return PLUGIN_HANDLED;
}

@task_HookWings(id)
{
	id -= TASK_ID_HOOK;

	if (get_entvar(id, var_flags) & FL_ONGROUND && !g_bHookUse[id])
	{
		remove_task(id+TASK_ID_HOOK);
		return;
	}

	static Float:flVelocity[3];
	get_entvar(id, var_velocity, flVelocity);

	if (vector_length(flVelocity) < 10.0)
	{
		g_bNeedRefresh[id] = true;
	}
	else if (g_bNeedRefresh[id])
	{
		g_bNeedRefresh[id] = false;
	}
}

@think_Hook(const iEnt)
{
	static iPlayers[MAX_PLAYERS], iPlayerCount;
	get_players_ex(iPlayers, iPlayerCount, GetPlayers_ExcludeDead);

	static iOrigin[3], Float:flVelocity[3], iDistance;

	for (new i, iPlayer; i < iPlayerCount; i++)
	{
		iPlayer = iPlayers[i];

		if (!g_bHookUse[iPlayer])
		{
			continue;
		}

		get_user_origin(iPlayer, iOrigin);
		iDistance = get_distance(g_iHookOrigin[iPlayer], iOrigin);
		
		if (iDistance > 25)
		{
			flVelocity[0] = (g_iHookOrigin[iPlayer][0] - iOrigin[0]) * (g_flHookSpeed[iPlayer] / iDistance);
			flVelocity[1] = (g_iHookOrigin[iPlayer][1] - iOrigin[1]) * (g_flHookSpeed[iPlayer] / iDistance);
			flVelocity[2] = (g_iHookOrigin[iPlayer][2] - iOrigin[2]) * (g_flHookSpeed[iPlayer] / iDistance);
			set_entvar(iPlayer, var_velocity, flVelocity);
			set_entvar( iPlayer, var_gravity, 0.1 );
		}
	}

	set_entvar(iEnt, var_nextthink, get_gametime() + 0.1);
}
