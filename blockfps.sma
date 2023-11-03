/*
    set max fps limit.
    kicks otherwise
*/
#include < amxmodx >
#include < amxmisc >
#include < reapi >

//#define ASPEC   // remove this to remove aspec stuff


#if defined ASPEC
native is_user_aspec( id );
new pAspec;
#endif


#define set_bit(%1,%2)      (%1 |= (1<<(%2&31)))
#define clear_bit(%1,%2)    (%1 &= ~(1 <<(%2&31)))
#define check_bit(%1,%2)    (%1 & (1<<(%2&31)))

#define TASK_HUD 1002
#define TASK_KICK 2002


new bIsOn, bHasBlock;
new Float:g_fClientGameTime[ MAX_PLAYERS + 1 ], g_iClientFPS[ MAX_PLAYERS + 1 ], g_iClientFrames[ MAX_PLAYERS + 1 ], g_iCurrentClientFPS[ MAX_PLAYERS + 1 ];
new iCvarMaxFps, Float:fCvarKickTime;

new Float:fTime[ MAX_PLAYERS + 1 ];
public plugin_init()
{
    register_plugin( "FPS Limit", "1.0.2", "DusT" );

    register_clcmd( "say", "CmdSay" );

    RegisterHookChain( RG_CBasePlayer_PreThink, "fw_PreThink_Post", true );

    bind_pcvar_num( create_cvar( "amx_max_fps", "105", _, "Block Players if they have more than this number", true, 100.0 ), iCvarMaxFps );
    bind_pcvar_float( create_cvar( "amx_fps_kick_time", "20", _, "Time to wait before kicking player for high fps", true, 0.1 ), fCvarKickTime );
    #if defined ASPEC
    bind_pcvar_num( create_cvar( "amx_fps_aspec", "1", _, "Allow high fps on aspec" ), pAspec );
    #endif
}
public plugin_natives()
{
    register_native( "get_user_fps", "_user_fps" );
}
public _user_fps( pl, argc )
    return g_iCurrentClientFPS[ get_param( 1 ) ];
public CmdSay( id )
{
    new args[ 64 ], cmd[ 10 ], name[ MAX_NAME_LENGTH ];
    read_args( args, charsmax( args ) );
    remove_quotes( args ); trim( args );
    strtok2( args, cmd, charsmax( cmd ), name, charsmax( name ) );
    //parse( args, cmd, charsmax( cmd ), name, charsmax( name ) );
    if( equali( cmd, "/fps" ) || equali( cmd, "!fps" ) )
    {
        new pid;
        if( !name[ 0 ] )
            pid = id; 
        else
            pid = cmd_target( id, name, CMDTARGET_NO_BOTS );
        if( !pid ) 
            return PLUGIN_HANDLED;
        
        new Float:fCurrTime = get_gametime(); 
        if( fTime[ id ] + 5.0 >= fCurrTime )
        {
            client_print_color( id, print_team_red, "^4[AMX]^1 Wait ^3%.1f^1 seconds.", fTime[ id ] + 5.0 - fCurrTime );
            return PLUGIN_HANDLED;
        }
        fTime[ id ] = fCurrTime;
        client_print_color( id, print_team_red, "^4[AMX]^1 %n has ^3%d^1 fps.", pid, g_iCurrentClientFPS[ pid ] );
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public fw_PreThink_Post( id )
{
    if( !is_user_connected( id ) )
        return HC_CONTINUE;
    #if defined ASPEC
    if( pAspec && is_user_aspec( id ) )
    {
        if( task_exists( TASK_HUD + id ) )
            remove_task( TASK_HUD + id );

        if( task_exists( TASK_KICK + id ) )
            remove_task( ( TASK_KICK + id ) );
        
        return HC_CONTINUE;
    }
    #endif
    static Float:fVel[ 3 ];

    g_fClientGameTime[ id ] = get_gametime();
    
    if( g_iClientFPS[ id ] >= g_fClientGameTime[ id ] )
        g_iClientFrames[ id ] += 1;
    else
    {
        g_iClientFPS[ id ] += 1;
        g_iCurrentClientFPS[ id ] = g_iClientFrames[ id ];
        g_iClientFrames[ id ] = 0;

        //btn = pev( id, pev_button );

        //if player isn't moving and has high fps, don't do shit.
        if( get_entvar( id, var_button ) & ( IN_ATTACK | IN_ATTACK2 | IN_MOVELEFT | IN_MOVERIGHT | IN_FORWARD | IN_BACK | IN_JUMP | IN_DUCK ) ) 
            if( g_iCurrentClientFPS[ id ] > iCvarMaxFps )
                set_bit( bIsOn, id );
        
        if( check_bit( bIsOn, id ) && g_iCurrentClientFPS[ id ] <= iCvarMaxFps )
        {
            clear_bit( bIsOn, id );
            clear_bit( bHasBlock, id );

            if( task_exists( TASK_HUD + id ) )
                remove_task( TASK_HUD + id );

            if( task_exists( TASK_KICK + id ) )
                remove_task( ( TASK_KICK + id ) );
        }
    }
    if( check_bit( bIsOn, id ) )
    {
        if( check_bit( bHasBlock, id ) )
        {
            get_entvar( id, var_velocity, fVel );
            fVel[ 0 ] = 0.0; fVel[ 1 ] = 0.0;
            set_entvar( id, var_velocity, fVel );
        }
        if( !task_exists( TASK_HUD + id ) )
            set_task( 1.0, "ShowHud", TASK_HUD + id, _, _, "b" );

        if( !task_exists( TASK_KICK + id ) )
            set_task( fCvarKickTime, "KickPlayer", TASK_KICK + id );
    }
    return HC_CONTINUE;
}
public ShowHud( id )
{
    id -= TASK_HUD;
    set_bit( bHasBlock, id );
    static message[ 256 ];
    if( !message[ 0 ] )
        copy( message, charsmax( message ), "FPS Too HIGH^nPlease use 'fps_max 100' in console to edit" );
    
    set_hudmessage( 255, 255, 255, -1.0, -1.0, 0, 6.0, 1.0, 0.0, 0.0, -1 );
    show_hudmessage( id, message );
}

public KickPlayer( id )
{
    id -= TASK_KICK;

    server_cmd( "kick #%d Higher FPS than %d", get_user_userid( id ), iCvarMaxFps );
}
public client_disconnected( id )
{
    clear_bit( bIsOn, id );

    if( task_exists( TASK_HUD + id ) )
        remove_task( TASK_HUD + id );

    if( task_exists( TASK_KICK + id ) )
        remove_task( ( TASK_KICK + id ) );
}