

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include < reapi >
//Set to 1 to enable the seperate model, 0 keeps the player's model
#define ASPEC_MODEL 1
//The entire path of the model. Note that it must be in player folder, and the subfolder name and file name must be the same. Ex: "models/player/vip/vip.mdl"
#define SPECIAL_PRECACHE "models/player/vip/vip.mdl"
//This is the model's subfolder/file name. (Since they are both the same) Ex: "vip"
#define SPECIAL_SHORT "vip"

//The admin flag necessary to go Advance Spec
#define ADMIN_FLAG ADMIN_IMMUNITY
//How invisible Advance Spectators are. Default 127
#define ALPHA_RENDER 127

// Everything below is used by the plugin, do not edit them

native au_set_user_semiclip( id, bool:semiclip );

#define TASK_SPEC 3000

new g_Spec[MAX_PLAYERS+1];
new aspec_semiclip;

new fwdOnAspec;

public plugin_init() 
{
	register_plugin("Advanced Spectate", "1.5.1", "Emp`&DusT");

	register_clcmd("say", "say_event");
	register_clcmd("say_team","say_event");

	fwdOnAspec = CreateMultiForward( "OnAspec", ET_CONTINUE, FP_CELL, FP_CELL );

	register_concmd("amx_aspec", "aspec_target", ADMIN_FLAG, "<@TEAM | #userid | name> - forces player(s) to aspec");

	aspec_semiclip = register_cvar("aspec_semiclip", "1");

	register_event("DeathMsg","DeathEvent","a");
	RegisterHookChain( RG_CBasePlayer_TakeDamage, "fw_TakeDamage" );
}

public plugin_natives()
{
	register_native( "is_user_aspec", "_is_user_aspec" );
}

public _is_user_aspec( plugin, argc )
{
	return g_Spec[ get_param( 1 ) ] > 0? true:false;
}
returntype()
{
	SetHookChainArg( 4, ATYPE_FLOAT, 0.0 );
	SetHookChainReturn( ATYPE_INTEGER, 0 );
	return HC_SUPERCEDE;
}
public fw_TakeDamage( this, idinflictor, idattacker, Float:dmg, dmgbits )
{
	if( is_user_alive(this) )
	{
		if( g_Spec[this] )
			return returntype();
	}
	if( is_user_alive(idinflictor) )
	{
		if( g_Spec[idinflictor] )
			return returntype();
	}
	if( is_user_alive(idattacker) )
	{
		if( g_Spec[idattacker] )
			return returntype();
	}
	return HC_CONTINUE;
}
public aspec_target(id, level, cid)
{
	if(!cmd_access(id, level, cid, 2))
		return PLUGIN_HANDLED;
	
	new target[16], players[32], pnum;
	
	read_argv(1,target,15);
	
	if(target[0] == '@')
	{
		if( target[1] == 'A' )
			get_players(players, pnum);

		else if( target[1] == 'C' )
			get_players(players, pnum ,"e", "CT");

		else if( target[1] == 'T' )
			get_players(players, pnum ,"e", "TERRORIST");

		else
		{
			console_print(id, "*** No known team by that name. ***");
			return PLUGIN_HANDLED;
		}
	}
	else if(target[0] == '#')
	{
		new userid = str_to_num(target[1]);
		players[0] = find_player("k", userid);
		pnum = 1;
	}
	else
	{
		players[0] = find_player("bl", target);
		pnum = 1;
	}
	
	if( !pnum )
	{
		console_print(id, "*** No target(s) could be found. ***");
		return PLUGIN_HANDLED;
	}
	else
	{
		//if only one person, check if they already have aspec activated
		if( pnum == 1 && g_Spec[players[0]] )
		{
			unspec_stuff(players[0]);
		}
		else
		{
			for( new i; i<pnum; i++ )
				StartAspec( players[i] );
		}
	}

	return PLUGIN_HANDLED;
}

#if ASPEC_MODEL == 1
public plugin_precache()
	precache_model(SPECIAL_PRECACHE);
#endif

public say_event(id) 
{
	new said[10];
	read_args(said,9);
	remove_quotes(said);

	if( equali(said, "/aspec",6 ) || equali( said, "!aspec", 6 )  )

		// They aren't admin! Don't let them!
		if( !( get_user_flags(id) & ADMIN_FLAG ) )
			client_print(id, print_chat, "You do not have access to go Advanced Spectate.");

		// They are already in Aspec, take them out!
		else if( g_Spec[id] && is_user_alive(id) )
			unspec_stuff(id);

		// Put them in Aspec
		else
			StartAspec(id);
}
StartAspec(id)
{
	new ret;
	ExecuteForward( fwdOnAspec, ret, id, true );
	if( ret == PLUGIN_HANDLED )
		return;

	if( !is_user_alive(id) )
		rg_round_respawn( id );

	if( !g_Spec[id] )
	{	
		g_Spec[id] = _:rg_get_user_team(id);
		spec_stuff(id+TASK_SPEC);
	}

	rg_set_user_team(id, TEAM_SPECTATOR);

	#if ASPEC_MODEL == 1
		rg_set_user_model(id, SPECIAL_SHORT);
	#endif
	if( get_pcvar_num( aspec_semiclip ) )
		au_set_user_semiclip( id, true );
	client_print(id, print_chat, "You have gone Advanced Spectate.");
}

public spec_stuff(id)
{
	id -= TASK_SPEC;
	if( g_Spec[id] > 0 )
	{
		if( is_user_alive(id) )
		{
			set_entvar( id, var_takedamage, DAMAGE_NO );
			//set_user_godmode(id, 1);
			//_SetPlayerNotSolid(id);
			rg_set_rendering(id, kRenderFxDistort, {0, 0, 0}, kRenderTransAdd, ALPHA_RENDER);
		}
		set_task(5.0, "spec_stuff", id+TASK_SPEC);
	}
	else
		rg_set_rendering(id);
}

unspec_stuff(id)
{
	new ret;
	ExecuteForward( fwdOnAspec, ret, id, false );
	if( ret == PLUGIN_HANDLED )
		return;
	remove_task(id+TASK_SPEC);
	if( g_Spec[id] )
	{

		if( is_user_alive(id) )
		{
			client_print(id, print_chat, "You have returned to a normal team.");

			#if ASPEC_MODEL == 1
				rg_reset_user_model(id);
			#endif

			rg_set_user_team(id, (g_Spec[id]==1) ? TEAM_TERRORIST : TEAM_CT );

			set_entvar( id, var_takedamage, DAMAGE_AIM );

			rg_set_rendering(id);
			au_set_user_semiclip( id, false );
		}

		g_Spec[id] = 0;
	}
}

stock rg_get_user_team( id )
	return get_member( id, m_iTeam );

stock rg_set_rendering(id, fx = kRenderFxNone,  color[3] = {255, 255, 255}, render = kRenderNormal, amount = 0)
{
    set_entvar(id, var_renderfx, fx);
    set_entvar(id, var_rendercolor, color);
    set_entvar(id, var_rendermode, render);
    set_entvar(id, var_renderamt, float(amount));
}

public client_putinserver(id)
{
	g_Spec[id] = 0;
}
public client_disconnected(id)
{
	unspec_stuff(id);
}

public DeathEvent()
	unspec_stuff(read_data(2));

public plugin_end()
	DestroyForward( fwdOnAspec );