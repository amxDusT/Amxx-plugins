/* 
    Keeps some bots active in the server as spectator.
    
    added: 
     one of the bots has the function of checking KB by attaching
     to a player and seeing if he responds to KnifeBot

*/


#include < amxmodx >
#include < amxmisc >
#include < fakemeta >
#include < reapi >
//#define DEBUG

#define MAX_BOTS    2

new pBot[ MAX_BOTS ][ MAX_NAME_LENGTH ];
new pBots;
new g_iBot[ MAX_BOTS ];
new pActive;
new bool:bIsUsed[ MAX_BOTS ];
new iTarget[ MAX_BOTS ];
new iUsed;
new fwdAddToFullPack = -1;
new fwServerFrame = -1;
public plugin_init()
{
    register_plugin( "[KNIFE] Active Bots", "1.0.2", "DusT" );
    
    bind_pcvar_num( create_cvar( "amx_bots_active", "1" ), pActive );
    for( new i; i < MAX_BOTS; i++ )
        bind_pcvar_string( create_cvar( fmt( "amx_bot%d_name", i + 1 ), fmt( "Player%d", i + 1 ) ), pBot[ i ], charsmax( pBot[] ) );
    //bind_pcvar_string( create_cvar( "amx_bot1_name", "CSAMX.NET" ), pBot[ 0 ], charsmax( pBot[] ) );
    //bind_pcvar_string( create_cvar( "amx_bot2_name", "JOIN NOW OR NEVER!!" ), pBot[ 1 ], charsmax( pBot[] ) );
    bind_pcvar_num( create_cvar( "amx_bots_num", "1", _, _, true, 1.0, true, float(MAX_BOTS) ), pBots );

    register_concmd( "kb_session", "CmdSession", ADMIN_IMMUNITY, "Display attached bots." );
    register_concmd( "kb_check", "CmdCheck", ADMIN_IMMUNITY, "Usage: < user > [ time in seconds ]" );
    register_concmd( "kb_remove", "CmdRemove", ADMIN_IMMUNITY, "Usage: < user >" );

    RegisterHookChain( RG_CBasePlayer_Observer_IsValidTarget, "IsValidTarget" );
}

public IsValidTarget( const this, iPlayerIndex, bool:bSameTeam )
{
    if( is_user_bot( iPlayerIndex ) )
    {
        new players[ MAX_PLAYERS ], num;
        get_players( players, num, "ch" );
        for( new i; i < num; i++ )
        {
            SetHookChainArg( 2, ATYPE_INTEGER, players[ i ] );
            return HC_CONTINUE;
        }
        SetHookChainArg( 2, ATYPE_INTEGER, 0 );
        return HC_CONTINUE;
    }

    return HC_CONTINUE;
}

public CmdSession( id, level, cid )
{
    if( !cmd_access( id, level, cid, 0 ) )
        return PLUGIN_HANDLED;
    
    if( !iUsed )
        console_print( id, "No Bots attached." );
    else
    {
        for( new i; i < MAX_BOTS; i++ )
            if( bIsUsed[ i ] )
                console_print( id, "%n - %s", iTarget[ i ], pBot[ i ] );
    }
    return PLUGIN_HANDLED;
}

public CmdCheck ( id, level, cid )
{
    if( !cmd_access( id, level, cid, 2 ) )
        return PLUGIN_HANDLED;
    
    if( iUsed >= MAX_BOTS )
    {
        console_print( id, "All bots are being used. Remove some bots." );
        return PLUGIN_HANDLED;
    }

    new target[ MAX_NAME_LENGTH ];
    read_argv( 1, target, charsmax( target ) );
    new pid = cmd_target( id, target, 0 );
    if( !pid )
        return PLUGIN_HANDLED;
        
    if( get_user_flags( pid ) & ADMIN_IMMUNITY )
    {
        if( !( get_user_flags( id ) & ADMIN_ADMIN ) )
        {
            console_print( id, "Player has immunity." );
            return PLUGIN_HANDLED;
        }
    }
    if( !(1 <= get_user_team( pid ) <= 2 ) )
    {
        console_print( id, "Player is not CT or T." );
        return PLUGIN_HANDLED;
    }
    for( new i; i < MAX_BOTS; i++ )
    {
        if( bIsUsed[ i ] && iTarget[ i ] == pid )
        {
            console_print( id, "Player has already a bot attacched.")
            return PLUGIN_HANDLED;
        }
    }
    new botIndex = -1;
    for( new i; i < MAX_BOTS; i++ )
    {
        if( !bIsUsed[ i ] )
        {
            botIndex = i;
            break;
        }
    }

    if( botIndex == -1 || !g_iBot[ botIndex ] )
    {
        console_print( id, "Fail. Bot not connected." );
        return PLUGIN_HANDLED;
    }
    iTarget[ botIndex ] = pid;
    bIsUsed[ botIndex ] = true;

    if( fwdAddToFullPack == -1 )
    {
        fwdAddToFullPack = register_forward( FM_AddToFullPack, "fw_AddToFullPack", 1 );
        fwServerFrame = register_forward( FM_StartFrame, "fw_StartFrame", 1 );
    }
    iUsed++;

    new Float:time = 300.0;
    if( read_argc() == 3 )
        time = read_argv_float( 2 );
    
    
    if( time >= 5.0 )
        set_task( time, "DetachBot", pid );

    //set_ent_data( g_iBot[ botIndex ], "CBasePlayer", "m_iTeam", get_user_team( pid ) == 1? 2:1 );
    rg_set_user_team( g_iBot[ botIndex ], get_user_team( pid ) == 1? 2:1 );
    rg_user_spawn( g_iBot[ botIndex ] );
    set_entvar( g_iBot[ botIndex ], var_owner, id );
    if( is_user_alive( iTarget[ botIndex ] ) )
    {   
        new Float:fOrigin[ 3 ];
        pev( iTarget[ botIndex ], pev_origin, fOrigin );
        engfunc( EngFunc_SetOrigin, g_iBot[ botIndex ], fOrigin );
    }
    else
        engfunc( EngFunc_SetOrigin, g_iBot[ botIndex ], Float:{-9999.9,-9999.9,-9999.9} );
    
    #if defined DEBUG
        new Float:fOrigin[ 3 ];
        pev( g_iBot[ botIndex ], pev_origin, fOrigin );
        console_print( id, "BOT position: %.2f %.2f %.2f", fOrigin[ 0 ], fOrigin[ 1 ], fOrigin[ 2 ] );
        console_print( id, "Bot Alive: %s", is_user_alive( g_iBot[ botIndex ] )? "true":"false" );
    #endif
    return PLUGIN_HANDLED;
}

public CmdRemove( id, level, cid )
{
    if( !cmd_access( id, level, cid, 2 ) )
        return PLUGIN_HANDLED;

    new name[ MAX_NAME_LENGTH ];
    read_argv( 1, name, charsmax( name ) );

    new pid = cmd_target( id, name, 0 );
    if( get_user_flags( pid ) & ADMIN_IMMUNITY )
    {
        if( !( get_user_flags( id ) & ADMIN_ADMIN ) )
        {
            console_print( id, "Player has immunity." );
            return PLUGIN_HANDLED;
        }
    }

    DetachBot( pid );
    return PLUGIN_HANDLED;
}

public DetachBot( id )
{
    new botIndex = -1;
    for( new i; i < MAX_BOTS; i++ )
    {
        if( bIsUsed[ i ] && iTarget[ i ] == id )
        {
            botIndex = i;
            break;
        }
    }
    if( botIndex == -1 )
        return;
    
    DetachBotByBIndex( botIndex );
    #if defined DEBUG
        new Float:fOrigin[ 3 ];
        pev( g_iBot[ botIndex ], pev_origin, fOrigin );
        console_print( id, "BOT position: %.2f %.2f %.2f", fOrigin[ 0 ], fOrigin[ 1 ], fOrigin[ 2 ] );
        console_print( id, "Bot Alive: %s", is_user_alive( g_iBot[ botIndex ] )? "true":"false" );
    #endif
}
public DetachBotByBIndex( botid )
{
    if( !bIsUsed[ botid ] )
        return;

    bIsUsed[ botid ] = false;
    iTarget[ botid ] = 0;
    iUsed--;
    if( is_user_alive( g_iBot[ botid ] ) )
    {
        engfunc( EngFunc_SetOrigin, g_iBot[ botid ], Float:{-9999.9,-9999.9,-9999.9} );
        //set_ent_data( g_iBot[ botid ], "CBasePlayer", "m_iTeam", 3 );
        rg_set_user_team( g_iBot[ botid ], TEAM_UNASSIGNED );
        user_silentkill( g_iBot[ botid ] );
    }
    if( !iUsed && fwdAddToFullPack )
    {
        unregister_forward( FM_AddToFullPack, fwdAddToFullPack, 1 );
        fwdAddToFullPack = -1;
        unregister_forward( FM_StartFrame, fwServerFrame, 1 );
        fwServerFrame = -1;
    }  
   
}

public fw_StartFrame()
{

    static Float:flFrameTime;
    global_get( glb_frametime, flFrameTime );
    static i;
    //engfunc( EngFunc_RunPlayerMove, client_index, view angle, forward speed, side speed, up speed, buttons, impulse, duration )
    for( i = 0; i < MAX_BOTS; i++)
        if( bIsUsed[ i ] )
            engfunc( EngFunc_RunPlayerMove, g_iBot[ i ], Float:{ 0.0, 0.0, 0.0 }, 0.0, 0.0, 0.0, 0, 0, floatround( flFrameTime * 1000.0 ) );
    return FMRES_IGNORED;
}

public fw_AddToFullPack( es_handle, e, iEnt, iHost, iHostflags, bPlayer, pSet )
{
    static i; 
    for( i = 0; i < MAX_BOTS; i++ )
    {
        if( bIsUsed[ i ] && iEnt == g_iBot[ i ] )
        {
            /*if( iHost == get_entvar( g_iBot[ i ], var_owner ) )
            {
                set_es(es_handle, ES_RenderFx, kRenderFxNone );
                set_es(es_handle, ES_RenderMode, kRenderNormal );
                set_es( es_handle, ES_RenderAmt, 255 );  
            }
            else
            {*///set_user_rendering(id,kRenderFxNone,0,0,0,kRenderTransAlpha,0) 
            set_es(es_handle, ES_RenderFx, kRenderFxNone);
            set_es(es_handle, ES_RenderMode, kRenderTransAlpha);
            set_es( es_handle, ES_RenderColor, {0,0,0});
            set_es( es_handle, ES_RenderAmt, 0 );      // invisible 
                
            //}
          
            set_es( es_handle, ES_Solid, SOLID_NOT );   // noclip
            if( iHost == iTarget[ i ] && is_user_alive( g_iBot[ i ] ) && is_user_alive( iTarget[ i ] ) )
            {
                static Float:fOrigin[ 3 ];
                pev( iTarget[ i ], pev_origin, fOrigin );
                engfunc( EngFunc_SetOrigin, g_iBot[ i ], fOrigin );
                //set_es( es_handle, ES_Origin, fOrigin );
            }   
        }
        
    }
}

public plugin_cfg()
{
    new szConfig[ 128 ];
    
    get_configsdir( szConfig, charsmax( szConfig ) );
    add( szConfig, charsmax( szConfig ), "/server_bots.cfg" );
    if( file_exists(szConfig) )
	{
		server_cmd("exec %s", szConfig);
		server_exec();
	}

    if( pActive )
        AddBots();
}

public AddBots()
{
    for( new i; i < pBots; i++ )
        AddBot( i );
}

public AddBot( id )
{
    if( g_iBot[ id ] )
        return;
    new players[ MAX_PLAYERS ], num;
    get_players( players, num, "d" );
    new countbots;
    for( new i; i < num; i++ )
    {
        if( is_user_bot(players[ i ] ) )
            countbots++
    }
    if( countbots >= MAX_BOTS )
        return;
    g_iBot[ id ] = engfunc( EngFunc_CreateFakeClient, pBot[ id ] );
    if ( !g_iBot[ id ] )
    {
        log_amx( "Unable to create bots." );
        return;
    }

    engfunc( EngFunc_FreeEntPrivateData, g_iBot[ id ] );
    new szRejected[ 128 ];
    dllfunc( DLLFunc_ClientConnect, g_iBot[ id ] , pBot[ id ] , "127.0.0.1" , szRejected );
    dllfunc( DLLFunc_ClientPutInServer, g_iBot[ id ] );

    set_entvar(  g_iBot[ id ], var_movetype, MOVETYPE_NOCLIP );
    set_pev( g_iBot[ id ] , pev_flags , pev( g_iBot[ id ] , pev_flags ) | FL_FAKECLIENT );
    // join spec(?)
    message_begin(MSG_ALL,get_user_msgid("TeamInfo"));
    write_byte(g_iBot[ id ]);
    write_string("SPECTATOR");
    message_end();

    engclient_cmd( g_iBot[ id ], "jointeam" , "6" );
    set_pev( g_iBot[ id ], pev_solid, SOLID_NOT );
    //set flags to no one can kill
    remove_user_flags( g_iBot[ id ], ADMIN_USER ); // z flag
    set_user_flags( g_iBot[ id ], ADMIN_IMMUNITY );
}
/*
RemoveBots()
{
    bActive = false;
    //let's kick
    if( g_iBot[ 0 ] )
        server_cmd( "kick #%d", get_user_userid( g_iBot[ 0 ] ) );
    if( g_iBot[ 1 ] )
        server_cmd( "kick #%d", get_user_userid( g_iBot[ 1 ] ) );
    
    g_iBot[ 0 ] = 0;
    g_iBot[ 1 ] = 0;
}*/
public client_disconnected( id, bool:drop, message[], msglen )
{
    if( is_user_bot( id ) )
    {
        for( new i; i < MAX_BOTS; i++ )
        {
            if( g_iBot[ i ] == id )
                g_iBot[ i ] = 0;
        }
    }
    if( task_exists( id ) )
    {
        remove_task( id );
    }
    DetachBot( id );
    
}

public rg_user_spawn( id ) 
{ 
    static msgTeamInfo;
    rg_round_respawn( id );

    if( msgTeamInfo || ( msgTeamInfo = get_user_msgid( "TeamInfo" ) ) )
    {
        message_begin( MSG_ALL , msgTeamInfo , _ , 0 );
        write_byte( id );
        write_string( "SPECTATOR" );
        message_end( );
    }
    //set_user_godmode(id, 1);
    set_entvar( id, var_takedamage, DAMAGE_NO );
    set_pev( id, pev_solid, SOLID_NOT );
}