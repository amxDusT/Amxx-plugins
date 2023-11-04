#include < amxmodx >
#include < reapi >
#include < zp50_gamemodes >
#include < zp50_ammopacks >
#include < zp50_colorchat_const>
#define LIBRARY_SURVIVOR "zp50_class_survivor"
#include <zp50_class_survivor>
#define LIBRARY_NEMESIS "zp50_class_nemesis"
#include <zp50_class_nemesis>
#define LIBRARY_SNIPER "zp50_class_sniper"
#include <zp50_class_sniper>


//#define DEBUG
#if defined DEBUG
#include < amxmisc >

#endif
enum
{
    WIN_ZOMBIE = 1,
    WIN_HUMANS,
    WIN_NO_ONE
}

enum _:eModes
{
    MODE_NONE       = -10,
    MODE_SURVIVOR   = 0,
    MODE_SNIPER     = 1,
    MODE_NEMESIS    = 2
}
new pKilled[ eModes ];
new pWin[ eModes ];
new iModeId[ eModes ];
new pMessage;
new iCurrentMode;
new HookChain:fwKilled;

public plugin_init()
{
    register_plugin("[ZP] Rewards", "2.0.2", "DusT")

    bind_pcvar_num( create_cvar( "zp_reward_surv_killed", "50", _, _, true, 0.0 ), pKilled[ MODE_SURVIVOR ] );
    bind_pcvar_num( create_cvar( "zp_reward_nem_killed", "50", _, _, true, 0.0 ), pKilled[ MODE_NEMESIS ] );
    bind_pcvar_num( create_cvar( "zp_reward_snip_killed", "50", _, _, true, 0.0 ), pKilled[ MODE_SNIPER ] );

    bind_pcvar_num( create_cvar( "zp_reward_surv_win", "50", _, _, true, 0.0 ), pWin[ MODE_SURVIVOR ] );
    bind_pcvar_num( create_cvar( "zp_reward_nem_win", "50", _, _, true, 0.0 ), pWin[ MODE_NEMESIS ] );
    bind_pcvar_num( create_cvar( "zp_reward_snip_win", "50", _, _, true, 0.0 ), pWin[ MODE_SNIPER ] );

    bind_pcvar_num( create_cvar( "zp_reward_show_messages", "1", _, _, true, 0.0, true, 1.0 ), pMessage );

    DisableHookChain( fwKilled = RegisterHookChain( RG_CBasePlayer_Killed, "@CBasePlayer_Killed_Pre" ) );
    #if defined DEBUG
    register_concmd( "zp_user_info", "CmdUserInfo" );
    #endif
    iCurrentMode = MODE_NONE;
}
#if defined DEBUG
public CmdUserInfo( id )
{
    new argv[ 32 ];
    read_argv( 1, argv, charsmax( argv ) );
    new player = cmd_target( id, argv, CMDTARGET_ALLOW_SELF );
    if( !player && !id )
        return PLUGIN_HANDLED;
    if( !player )
        player = id;
        
    console_print( id, "Player: %n", player );
    console_print( id, "Survivor: %s", ( LibraryExists(LIBRARY_SURVIVOR, LibType_Library) && zp_class_survivor_get( player ))? "Yes":"No");
    console_print( id, "Nemesis: %s", ( LibraryExists(LIBRARY_NEMESIS, LibType_Library) && zp_class_nemesis_get( player ))? "Yes":"No");
    console_print( id, "Sniper: %s", ( LibraryExists(LIBRARY_SNIPER, LibType_Library) && zp_class_sniper_get( player ))? "Yes":"No");
    return PLUGIN_HANDLED;
}
#endif
public plugin_cfg()
{
    iModeId[ MODE_SURVIVOR ] = zp_gamemodes_get_id( "Survivor Mode" );
    iModeId[ MODE_NEMESIS ] = zp_gamemodes_get_id( "Nemesis Mode" );
    iModeId[ MODE_SNIPER ] = zp_gamemodes_get_id( "Sniper Mode" );
}

public zp_fw_gamemodes_start( modeid )
{
    if( modeid < 0 )
    {
        iCurrentMode = MODE_NONE;
        return;
    }
    for( new i; i < eModes; i++ )
    {
        if( modeid == iModeId[ i ] )
        {
            RunninMode( i );
            return;
        }
    }
    iCurrentMode = MODE_NONE;
}
RunninMode( mode )
{
    iCurrentMode = mode;
    if( pKilled[ mode ] )
        EnableHookChain( fwKilled );
}

public zp_fw_gamemodes_end( modeid )
{
    if( iCurrentMode == MODE_NONE ) return;
    DisableHookChain( fwKilled );
    new iWinTeam;
    if (!zp_core_get_zombie_count())
        iWinTeam = WIN_HUMANS;
    else if (!zp_core_get_human_count())
        iWinTeam = WIN_ZOMBIE;
    else
        iWinTeam = WIN_NO_ONE;
    
    if( iWinTeam == WIN_HUMANS && iCurrentMode <= MODE_SNIPER && pWin[ iCurrentMode ] )
    {  
        new players[32], num;
        get_players( players, num, "e", "CT" );
        for( new i, player; i < num; i++ )
        {
            player = players[ i ];
            zp_ammopacks_set( player, zp_ammopacks_get( player ) + pWin[ iCurrentMode ] );
        }    
        if( pMessage )
            client_print_color( 0, print_team_red, "%s%s(s) earned %d ammos for winning the round!", ZP_PREFIX, iCurrentMode==MODE_SNIPER? "Sniper":"Survivor", pWin[ iCurrentMode ] );
    }
    else if( iWinTeam == WIN_ZOMBIE && iCurrentMode == MODE_NEMESIS && pWin[ iCurrentMode ] )
    {
        new players[32], num;
        get_players( players, num, "e", "TERRORIST" );
        for( new i, player; i < num; i++ )
        {
            player = players[ i ];
            zp_ammopacks_set( player, zp_ammopacks_get( player ) + pWin[ iCurrentMode ] );
        }
        if( pMessage )
            client_print_color( 0, print_team_red, "%sNemesis earned %d ammos for winning the round!", ZP_PREFIX, pWin[ iCurrentMode ] );
    }
}
@CBasePlayer_Killed_Pre( const victim, const killer )
{
    if( victim == killer || !killer || !is_user_connected( killer ) || !is_user_connected( victim ) )
        return HC_CONTINUE;
    if( iCurrentMode == MODE_NONE )
        return HC_CONTINUE;
    
    if( iCurrentMode == MODE_SURVIVOR && LibraryExists(LIBRARY_SURVIVOR, LibType_Library) && zp_class_survivor_get( victim ) && pKilled[ MODE_SURVIVOR ] )
    {
        zp_ammopacks_set( killer, zp_ammopacks_get( killer ) + pKilled[ iCurrentMode ] );
        if( pMessage )
            client_print_color( killer, print_team_default, "%sYou earned %d ammos for killing a survivor!", ZP_PREFIX, pKilled[ iCurrentMode ] );
    }
    else if( iCurrentMode == MODE_NEMESIS && LibraryExists(LIBRARY_NEMESIS, LibType_Library) && zp_class_nemesis_get( victim ) && pKilled[ MODE_NEMESIS ] )
    {
        zp_ammopacks_set( killer, zp_ammopacks_get( killer ) + pKilled[ iCurrentMode ] );
        if( pMessage )
            client_print_color( killer, print_team_default, "%sYou earned %d ammos for killing a nemesis!", ZP_PREFIX, pKilled[ iCurrentMode ] );
    }
    else if( iCurrentMode == MODE_SNIPER && LibraryExists(LIBRARY_SNIPER, LibType_Library) && zp_class_sniper_get( victim ) && pKilled[ MODE_SNIPER ] )
    {
        zp_ammopacks_set( killer, zp_ammopacks_get( killer ) + pKilled[ iCurrentMode ] );
        if( pMessage )
            client_print_color( killer, print_team_default, "%sYou earned %d ammos for killing a sniper!", ZP_PREFIX, pKilled[ iCurrentMode ] );
    }
    return HC_CONTINUE;
}


public module_filter(const module[])
{
	if (equal(module, LIBRARY_SNIPER) || equal(module, LIBRARY_NEMESIS) || equal(module, LIBRARY_SURVIVOR))
		return PLUGIN_HANDLED;
	
	return PLUGIN_CONTINUE;
}
public native_filter(const name[], index, trap)
{
	if (!trap)
		return PLUGIN_HANDLED;
		
	return PLUGIN_CONTINUE;
}
public plugin_natives()
{
	set_module_filter("module_filter")
	set_native_filter("native_filter")
}
