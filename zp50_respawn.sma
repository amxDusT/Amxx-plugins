#include < amxmodx >
#include < zp50_core >
#include < zp50_gamemodes >
#include < reapi >
#include < hamsandwich >
#define LIBRARY_NEMESIS "zp50_class_nemesis"
#include <zp50_class_nemesis>
#define LIBRARY_SURVIVOR "zp50_class_survivor"
#include <zp50_class_survivor>
#define LIBRARY_SNIPER "zp50_class_sniper"
#include <zp50_class_sniper>

#define IsValidTeam(%1) (TEAM_TERRORIST <= get_member(%1, m_iTeam) <= TEAM_CT)
//define DEBUG
enum _:eModes
{
	ZMODE_NEM,	//0
	ZMODE_PLAGUE, //1
	ZMODE_SURV, // 2 
	ZMODE_SNIPER, // 3 
	ZMODE_SWARM, // 4 
	ZMODE_MULTIPLE, // 5 
	ZMODE_NORMAL // 6 
}
new pCvar[ eModes ];
new iModeId[ eModes ];
new iCurrentMode = ZP_NO_GAME_MODE;
new Float:pRespawnTime;
new bool:bIsFinished = false;
public plugin_init()
{
	register_plugin("[ZP] Respawn", "1.2", "DusT" );
	if( LibraryExists(LIBRARY_NEMESIS, LibType_Library) )
		bind_pcvar_num( get_cvar_pointer( "zp_nemesis_allow_respawn" ), pCvar[ ZMODE_NEM ] );
	bind_pcvar_num( get_cvar_pointer( "zp_plague_allow_respawn" ), pCvar[ ZMODE_PLAGUE ] );
	bind_pcvar_num( get_cvar_pointer( "zp_swarm_allow_respawn" ), pCvar[ ZMODE_SWARM ] );
	if( LibraryExists(LIBRARY_SURVIVOR, LibType_Library) )
		bind_pcvar_num( get_cvar_pointer( "zp_survivor_allow_respawn" ), pCvar[ ZMODE_SURV ] );
	if( LibraryExists(LIBRARY_SNIPER, LibType_Library) )	
		bind_pcvar_num( get_cvar_pointer( "zp_sniper_allow_respawn" ), pCvar[ ZMODE_SNIPER ] );
	bind_pcvar_num( get_cvar_pointer( "zp_multi_allow_respawn" ), pCvar[ ZMODE_MULTIPLE ] );
	bind_pcvar_num( get_cvar_pointer( "zp_infection_allow_respawn" ), pCvar[ ZMODE_NORMAL ] );
	//new pointer = get_cvar_pointer( "zp_respawn_delay" )
	bind_pcvar_float( get_cvar_pointer( "zp_respawn_delay" ), pRespawnTime );
	RegisterHookChain( RG_CBasePlayer_Killed, "@OnPlayerKilled", true );
	RegisterHookChain( RG_CSGameRules_PlayerSpawn, "@OnPlayerSpawn", true );
	RegisterHookChain( RG_HandleMenu_ChooseAppearance, "@OnAppearanceChosen", true );
	#if defined DEBUG
	register_clcmd( "say /rzombie", "CmdSpawnZombie" );
	register_clcmd( "say /rhuman", "CmdSpawnHuman" );
	#endif
}
#if defined DEBUG
public CmdSpawnZombie( id )
{
	if( is_user_alive( id ) )
		return PLUGIN_HANDLED;
	zp_core_respawn_as_zombie( id );
	ExecuteHamB(Ham_CS_RoundRespawn, id)

	return PLUGIN_HANDLED;
}
public CmdSpawnHuman( id )
{
	if( is_user_alive( id ) )
		return PLUGIN_HANDLED;
	zp_core_respawn_as_zombie( id, false );
	ExecuteHamB(Ham_CS_RoundRespawn, id)
	
	return PLUGIN_HANDLED;
}
#endif
public plugin_cfg()
{

	iModeId[ ZMODE_NORMAL ] = zp_gamemodes_get_id( "Infection Mode" );
	iModeId[ ZMODE_NEM ] = zp_gamemodes_get_id( "Nemesis Mode" );
	iModeId[ ZMODE_PLAGUE ] = zp_gamemodes_get_id( "Plague Mode" );
	iModeId[ ZMODE_SWARM ] = zp_gamemodes_get_id( "Swarm Mode" );
	iModeId[ ZMODE_SURV ] = zp_gamemodes_get_id( "Survivor Mode" );
	iModeId[ ZMODE_SNIPER ] = zp_gamemodes_get_id( "Sniper Mode" );
	iModeId[ ZMODE_MULTIPLE ] = zp_gamemodes_get_id( "Multiple Infection Mode" );
	bIsFinished = true;	// ensuring players don't spawn before every mode id is gotten
}
public plugin_natives()
{
	set_module_filter("module_filter")
	set_native_filter("native_filter")
}

public module_filter(const module[])
{
	if (equal(module, LIBRARY_NEMESIS) || equal(module, LIBRARY_SURVIVOR) || equal(module, LIBRARY_SNIPER))
		return PLUGIN_HANDLED;
	
	return PLUGIN_CONTINUE;
}
public native_filter(const name[], index, trap)
{
	if (!trap)
		return PLUGIN_HANDLED;
		
	return PLUGIN_CONTINUE;
}

public zp_fw_gamemodes_start( game_mode_id )
{
	iCurrentMode = game_mode_id;
}
@OnPlayerKilled( id )
{
	if( task_exists( id ) )
		remove_task( id );
	set_task( pRespawnTime, "@OnRespawn", id, .flags="b" );
}

@OnPlayerSpawn( id )
{
	if( task_exists( id ) )
		remove_task( id );
}

@OnAppearanceChosen( id )
{
	if( get_member( id, m_bJustConnected ) && iCurrentMode == ZP_NO_GAME_MODE )
		set_task( 0.1, "@OnRespawn", id, .flags="b" );
	else
		set_task( pRespawnTime, "@OnRespawn", id, .flags="b" );
}
public client_disconnected( id )
	if( task_exists( id ) )
		remove_task( id );

@OnRespawn( id )
{
	if( !bIsFinished )
		return;
	if( !is_user_connected( id ) || is_user_alive( id ) )
	{
		remove_task( id ); 
		return;
	}
	if( !IsValidTeam( id ) )
	{
		//client_print( id, print_chat, "DEBUG: no valid team. Waiting again before spawn" );
		return;
	}
	
	if( iCurrentMode == ZP_NO_GAME_MODE || ( iCurrentMode == iModeId[ ZMODE_NEM ] && pCvar[ ZMODE_NEM ] ) )
	{
		zp_core_respawn_as_zombie( id, false );
		RespawnUser( id );
	}
	else if( iCurrentMode == iModeId[ ZMODE_PLAGUE ] ) 
	{
		if( LibraryExists(LIBRARY_NEMESIS, LibType_Library) && pCvar[ ZMODE_PLAGUE ])
		{
			zp_core_respawn_as_zombie( id );
			RespawnUser( id );
			zp_class_nemesis_set( id );
		}	
	}
	else
	{
		for( new i = ZMODE_SWARM; i < eModes; i++ )
		{
			if( iCurrentMode == iModeId[ i ] && pCvar[ i ] )
			{
				#if defined DEBUG
				client_print( id, print_chat, "DEBUG : respawning as zombie %d", i )
				#endif
				zp_core_respawn_as_zombie( id );
				RespawnUser( id );
			}
		}
	}
}

RespawnUser( id )
{
	rg_round_respawn( id );
}
public zp_fw_core_spawn_post( id )	// hacky
{
	if( iCurrentMode == ZP_NO_GAME_MODE )
		zp_core_respawn_as_zombie( id, false );
	else if( iCurrentMode == iModeId[ ZMODE_NORMAL ] )
		zp_core_respawn_as_zombie( id, true );
}
