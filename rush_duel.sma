#include < amxmodx >
#include < amxmisc >
#include < fakemeta >
#include < hamsandwich >
#include < regex >
#include < xs >
#include < reapi >


//#define DKNIFE_DUEL
//#define TEAM_PLUGIN           // if you have teamprotection plugin
#define SQL                   // if you want to have a ranking system through sql


#define ADMIN_FLAG          ADMIN_LEVEL_A
#define PREFIX              "^3[RUSH]^1"
#define SLAY_PLAYERS_TIME   9.0
#define MAX_ZONES           4

#if defined SQL
    #include < sqlx >
#endif

#if defined TEAM_PLUGIN
    /** 
    * Pauses/Unpauses teams
    * 
    * @note     teams don't get removed. You will show as team.
    *
    * @param id         player1 id.
    * @param id2        player2 id.
    * @param unpause    if to unpause teams  
    */
    native kf_pause_teaming(id, id2, unpause = 0);
#endif

#define set_bit(%1,%2)      (%1 |= (1<<(%2&31)))
#define clear_bit(%1,%2)    (%1 &= ~(1<<(%2&31)))
#define check_bit(%1,%2)    (%1 & (1<<(%2&31)))

new const VERSION[] = "2.0.6";

new const SPRITE_BEAM[] = "sprites/laserbeam.spr";

#if defined SQL
    new const host[] = "127.0.0.1";
    new const user[] = "root";
    new const pass[] = "";
    new const db[]   = "mysql_dust";

    new Handle:tuple;
    new bool:bResetRanks;

    enum _:eRankData
    {
        P_ADDED,
        P_DUELS,
        P_WON,
        P_DRAW,
        P_LOST,
        P_WONSLASH,
        P_WONSTAB,
        P_WONBOTH
    }
    new g_SqlInfo[ 33 ][ eRankData ];
    new Float:fCheckRank[ 33 ];

    #define COOLDOWN    10.0
#endif

#if AMXX_VERSION_NUM < 183
    set_fail_state( "Plugin requires 1.8.3 or higher." );
#endif

enum _:eLastData
{
    IPLAYER1 = 0,
    IPLAYER2,
    IROUND1,
    IROUND2,
    IWINNER,
    IREASON,
    IPOS,
    IZONE,
    ITYPE
}

enum
{
    TOTAL = 2,
    FAKE  = 3
}

enum _:eEndRushReason
{
    NONE = 0,
    FAKE_ROUNDS,
    TIME_END,
    PLAYER_STOP,
    PLAYER_DISCONNECTED
}

enum _:TASKS ( += 1000 )
{
    TASK_DRAW = 141,
    TASK_COUNTDOWN,
    TASK_AUTOKILL,
    TASK_RESTART,
    TASK_REVIVE
}

enum _:attType
{
    SLASH   = 0,
    STAB    = 1,
    BOTH    = 2
}

enum _:rushData
{
    PLAYER1,
    PLAYER2,
    RUSHTYPE
}

enum _:eWin
{
    WON = 0,
    LOST,
    DRAW
}

new hasDisabledRush;
new hasBlocked[ MAX_PLAYERS + 1 ];
new bool:canRush;
new rushDir[ 128 ];
new activeZones;
new busyZones;

new bHasTouch;
new bIsInRush, bCanRun;
new g_RushInfo[ MAX_ZONES ][ rushData ]; 
new g_Rounds[ MAX_ZONES ][ 4 ];

new Float:g_HealthCache[ MAX_ZONES ][ 2 ];
new bIsZoneBusy;

new beam;
new editor, edit_zone;

new Float:g_vecOrigin[ MAX_ZONES ][ 2 ][ 3 ];
new Float:g_Velocity [ MAX_ZONES ][ 2 ][ 3 ];
new Float:g_Position [ MAX_ZONES ][ 2 ][ 3 ];
new const DisableAccess = ( 1 << 26 );

new HamHook:PostKilled;
new HamHook:PreKilled;
new HamHook:PlayerTouch;
new HamHook:PlayerSpawnPost;
//new HamHook:PlayerThink; // for some reason this doesn't work, so imma use fakemeta
new PlayerThink;

//new OrpheuStruct:ppmove;

new Float:pHealth[ attType ];
new pRounds;
new pAlive;
new pSavePos;
new pSaveHealth;
new pFakeRounds;

public plugin_init()
{
    register_plugin( "Rush Duel", VERSION, "DusT" );

    register_cvar( "AmX_DusT", "Rush_Duel", FCVAR_SPONLY | FCVAR_SERVER );

    register_clcmd( "amx_rush_menu", "AdminRush", ADMIN_FLAG );

    register_clcmd( "say /rush", "CmdRush" );
    register_clcmd( "say /stop", "CmdStopDuel" );

    bind_pcvar_float( create_cvar( "rush_health_slash", "1"  ), Float:pHealth[ SLASH ] );
    bind_pcvar_float( create_cvar( "rush_health_stab",  "35" ), Float:pHealth[ STAB ]  );
    bind_pcvar_float( create_cvar( "rush_health_both",  "35" ), Float:pHealth[ BOTH ]  );
    
    bind_pcvar_num( create_cvar( "rush_save_health", "1" ), pSaveHealth );
    bind_pcvar_num( create_cvar( "rush_save_pos", "0" ), pSavePos );
    bind_pcvar_num( create_cvar( "rush_rounds", "10"  ), pRounds  );
    bind_pcvar_num( create_cvar( "rush_fake_rounds", "3"  ), pFakeRounds );
    /*
        Explanation rush_alive:
            - 0: revives who made most kills. In case of draw, both revive.
            - 1: revives who made most kills. In case of draw, both dead.
            - 2: revives who killed the player on last round. 
            - 3: both revive.
    */
    bind_pcvar_num( create_cvar( "rush_alive", "0", .description="Info on github.com/amxDust/RushDuel-amxx"), pAlive );

    DisableHamForward( PostKilled  = RegisterHamPlayer( Ham_Killed, "fw_PlayerKilled_Post", 1 ) ); 
    DisableHamForward( PreKilled   = RegisterHamPlayer( Ham_Killed, "fw_PlayerKilled_Pre",  0 ) ); 
    //DisableHamForward( PlayerThink = RegisterHamPlayer( Ham_Think,  "fw_PlayerThink_Pre",   0 ) );
    DisableHamForward( PlayerTouch = RegisterHamPlayer( Ham_Touch,  "fw_PlayerTouch" ) );
    DisableHamForward( PlayerSpawnPost  = RegisterHamPlayer( Ham_Spawn,  "fw_PlayerSpawn_Post",  1 ) );

    register_logevent( "RoundStart", 2, "1=Round_Start" );
    register_logevent( "RoundEnd"  , 2, "1=Round_End"   );

    
    /*OrpheuRegisterHook( OrpheuGetFunction( "PM_Duck" ), "OnPM_Duck" );
    OrpheuRegisterHook( OrpheuGetFunction( "PM_Jump" ), "OnPM_Jump" );
    OrpheuRegisterHook( OrpheuGetDLLFunction( "pfnPM_Move", "PM_Move" ), "OnPM_Move" );
    */
    RegisterHookChain( RG_PM_Move, "@On_Move" );
    activeZones = CountZones();

    #if defined SQL
        tuple = SQL_MakeDbTuple( host, user, pass, db );

        register_concmd( "amx_rush_reset", "CmdRushReset", ADMIN_FLAG );
        register_clcmd( "say /rrank", "CmdGetRank" );
        register_clcmd( "say /rstats", "CmdGetRankStats" );
        register_clcmd( "say /rtop", "CmdGetTop" );
    #endif
}
@On_Move( id )
{
    static hasFriction;
    if( check_bit( bIsInRush, id ) )
    {
        set_bit( hasFriction, id );
        new cmd = get_pmove( pm_cmd );
        set_pmove( pm_oldbuttons, get_pmove( pm_oldbuttons ) | IN_JUMP );
        set_ucmd( cmd, ucmd_buttons, get_ucmd( cmd, ucmd_buttons ) & ~IN_DUCK );
        set_ucmd( cmd, ucmd_sidemove, 0.0 );
        set_ucmd( cmd, ucmd_forwardmove, 0.0 );
        new zone = GetZone( id );
        if( check_bit( bHasTouch, zone ) )
            set_pmove( pm_friction, 1.0 );
        else
            set_pmove( pm_friction, 0.0 );
    }
    else if( check_bit( hasFriction, id ) )
    {
            clear_bit( hasFriction, id );
            set_pmove( pm_friction, 1.0 );
    }
}
public plugin_precache()
{
    beam = precache_model( SPRITE_BEAM );
}

public client_disconnected( id )
{
    if( task_exists( id + TASK_REVIVE ) )
        remove_task( id + TASK_REVIVE );
    
    if( check_bit( bIsInRush, id ) )
        StopDuelPre( GetZone( id ), PLAYER_DISCONNECTED, id );
    
    hasBlocked[ id ] = 0;

    if( check_bit( hasDisabledRush, id ) )
        clear_bit( hasDisabledRush, id );

    #if defined SQL
        arrayset( g_SqlInfo[ id ], 0, eRankData );
        fCheckRank[ id ] = 0.0;
    #endif
}

public RoundStart()
{
    set_task( 2.0, "AllowRush" );
}

public AllowRush()
{
    canRush = true;
}

public RoundEnd()
{
    canRush = false;
}

public AdminRush( id, level, cid )
{
    if( !cmd_access( id, level, cid, 0 ) )
        return PLUGIN_HANDLED;
    
    AdminRushMenu( id );
    
    return PLUGIN_HANDLED;
}

AdminRushMenu( id )
{
    new menuid = menu_create( fmt( "\rRush Menu^n\yAdmin Menu^n^nCurrent Active Zones: %d", activeZones ), "AdminRushHandler" );
    
    menu_additem( menuid, "Create New Zone", _, activeZones >= MAX_ZONES? DisableAccess:0 );

    menu_additem( menuid, "Edit Existing Zone", _, activeZones <= 0? DisableAccess:0 );

    menu_display( id, menuid );

    return PLUGIN_HANDLED;
}

public AdminRushHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        switch( item )
        {
            case 0: EditZone( id, activeZones++ );
            
            case 1: EditZoneMenu( id );
        }
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
} 

public CmdStopDuel( id )
{
    if( check_bit( bIsInRush, id ) )
        StopDuelPre( GetZone( id ), PLAYER_STOP, id );
}

public CmdRush( id )
{
    new menuid = menu_create( "Rush Menu", "CmdRushHandler" );

    menu_additem( menuid, "Rush" );
    menu_additem( menuid, "Block Player" );

    menu_additem( menuid, check_bit( hasDisabledRush, id )? "ENABLE Requests":"DISABLE Requests" );

    menu_display( id, menuid );

    return PLUGIN_HANDLED;
}

public CmdRushHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        switch( item ) 
        {
            case 0:
            {
                RushMenu( id );
            }
            case 1:
            {
                BlockMenu( id );
            }
            case 2:
            {
                if( check_bit( hasDisabledRush, id ) )
                    clear_bit( hasDisabledRush, id );
                else
                    set_bit( hasDisabledRush, id );
                
                CmdRush( id );
            }
        }
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

BlockMenu( id )
{
    new players[ 32 ], iNum;

    get_players( players, iNum );
    
    new menuid = menu_create( "Block Menu", "BlockMenuHandler" );
    new buff[ 2 ];
    // using "e" flag on get_players doesn't work always fine.
    for( new i; i < iNum; i++ )
    {                                                                                                          //spectator
        if( id == players[ i ] || get_user_team( id ) == get_user_team( players[ i ] ) || get_user_team( players[ i ] ) == 3 )
            continue;

        buff[ 0 ] = players[ i ];
        buff[ 1 ] = 0;
        menu_additem( menuid, fmt( "%n%s", buff[ 0 ], check_bit( hasBlocked[ id ], buff[ 0 ] )? " [UNBLOCK]":"" ), buff );
    } 

    menu_display( id, menuid );
}

public BlockMenuHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        new buff[ 2 ]
        menu_item_getinfo( menuid, item, _, buff, charsmax( buff ) );
        
        if( is_user_connected( buff[ 0 ] ) )
        {
            if( check_bit( hasBlocked[ id ], buff[ 0 ] ) )
                clear_bit( hasBlocked[ id ], buff[ 0 ] );
            else
                set_bit( hasBlocked[ id ], buff[ 0 ] );
        }

        BlockMenu( id );
    }
    
    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

public RushMenu( id )
{
    if( !CanPlayerRush( id ) )
        return PLUGIN_HANDLED;
    
    new players[ 32 ], num;

    get_players( players, num, "ach" );
    
    new menuid = menu_create( "\rRush Menu^n\yChoose a Player", "RushMenuHandler" );
    new bool:hasPlayers, buff[ 2 ];
    for( new i; i < num; i++ )
    {
        if( id == players[ i ] || get_user_team( id ) == get_user_team( players[ i ] ) || get_user_team( players[ i ] ) == 3 || check_bit( bIsInRush, players[ i ] ) )
            continue;

        if( check_bit( hasBlocked[ players[ i ] ], id ) || check_bit( hasDisabledRush, players[ i ] ) )
            continue;

        buff[ 0 ] = players[ i ];
        buff[ 1 ] = 0;

        if( !hasPlayers )
            hasPlayers = true;

        menu_additem( menuid, fmt( "%n", buff[ 0 ] ), buff );
    }
    if( !hasPlayers )
    {
        client_print_color( id, print_team_red, "%s There are no players to rush with!", PREFIX );
        return PLUGIN_HANDLED;
    }

    menu_display( id, menuid );
    return PLUGIN_HANDLED;
}

public RushMenuHandler( id, menuid, item )
{
    if( CanPlayerRush( id ) && item != MENU_EXIT )
    {
        new buff[ 2 ]
        menu_item_getinfo( menuid, item, _, buff, charsmax( buff ) );

        if( CanPlayerRush( id, true, buff[ 0 ] ) )
        {
            new menuid2 = menu_create( "Choose Rush Type", "RushTypeHandler" );
            menu_additem( menuid2, "Only Slash ( R1 )", buff );
            menu_additem( menuid2, "Only Stab  ( R2 )" );
            menu_additem( menuid2, "Both ( R1 and R2 )" );

            menu_display( id, menuid2 );
        }
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

public RushTypeHandler( id, menuid, item )
{
    if( CanPlayerRush( id ) && item != MENU_EXIT )
    {
        new buff[ 2 ];
        menu_item_getinfo( menuid, 0, _, buff, charsmax( buff ) );

        if( CanPlayerRush( id, true, buff[ 0 ] ) )
        {
            new menuid2 = menu_create( fmt( "\y'%n' wants to rush %s with you!^nAccept?", id, item == 0? "only SLASH(R1)":item == 1? "only STAB(R2)":"(R1 and R2)" ), "SendChallengeHandler" );
            new buffer[ 3 ];
            buffer[ 0 ] = id;
            buffer[ 1 ] = item;
            buffer[ 2 ] = 0;
            menu_additem( menuid2, "Accept", buffer );
            menu_additem( menuid2, "Refuse" );

            menu_display( buff[ 0 ], menuid2, _, 10 );
        }
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

public SendChallengeHandler( id, menuid, item )
{
    if( CanPlayerRush( id , false ) && item == 0 )
    {
        new buff[ 3 ];
        menu_item_getinfo( menuid, 0, _, buff, charsmax( buff ) );
        if( CanPlayerRush( id, true, buff[ 0 ] ) )
        {
            client_print_color( id, print_team_red, "%s You accepted %n's challenge.", PREFIX, buff[ 0 ] );
            client_print_color( id, print_team_red, "%s %n accepted your challenge.", PREFIX, id );
            GetReady( buff[ 0 ], id, buff[ 1 ] );
        }
    }
    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

GetReady( id, pid, type )
{
    new i;
    for( i = 0; i < activeZones; i++ )
    {
        if( !check_bit( bIsZoneBusy, i ) )
            break;
        
        if( i == activeZones - 1 )
        {
            client_print_color( id, print_team_red, "%s There are no free zones to play. Retry later.", PREFIX );
            return;
        }
    }

    #if defined TEAM_PLUGIN
        kf_pause_teaming( id, pid );
    #endif

    g_RushInfo[ i ][ PLAYER1 ]  = id;
    g_RushInfo[ i ][ PLAYER2 ]  = pid;
    g_RushInfo[ i ][ RUSHTYPE ] = type;
    
    g_Rounds[ i ][ PLAYER1 ] = 0;
    g_Rounds[ i ][ PLAYER2 ] = 0;
    g_Rounds[ i ][ TOTAL ]   = 1;
    g_Rounds[ i ][ FAKE ]    = 0;
    set_bit( bIsInRush, id );
    set_bit( bIsInRush, pid );

    if( !busyZones )
        ToggleFwds( true );

    set_bit( bIsZoneBusy, i );
    busyZones++;
    if( pSaveHealth )
    {
        pev( id,  pev_health, g_HealthCache[ i ][ PLAYER1 ] );
        pev( pid, pev_health, g_HealthCache[ i ][ PLAYER2 ] );
    }
    
    set_pev( id,  pev_health, pHealth[ type ] );
    set_pev( pid, pev_health, pHealth[ type ] );
    
    if( pSavePos )
    {
        pev( id,  pev_origin, g_Position[ i ][ PLAYER1 ] );
        pev( pid, pev_origin, g_Position[ i ][ PLAYER2 ] );
    }
    
    TeleportPlayer( id,  i, PLAYER1 );
    TeleportPlayer( pid, i, PLAYER2 );

    LookAtOrigin( id,  g_vecOrigin[ i ][ PLAYER2 ] );
    LookAtOrigin( pid, g_vecOrigin[ i ][ PLAYER1 ] );

    new params[ 1 ];
    params[ 0 ] = 3; 
    set_task( 1.2, "CountDown", TASK_COUNTDOWN + i, params, 1 ); 
    set_task( SLAY_PLAYERS_TIME, "SlayPlayers", TASK_AUTOKILL + i );

}

public ReviveDead( id )
{
    id -= TASK_REVIVE;
    
    ExecuteHamB( Ham_CS_RoundRespawn, id );
}

// unfinished__
public ContinueRounds( zone )
{
    zone -= TASK_RESTART;

    TeleportPlayer( g_RushInfo[ zone ][ PLAYER1 ], zone, PLAYER1 );
    TeleportPlayer( g_RushInfo[ zone ][ PLAYER2 ], zone, PLAYER2 );

    LookAtOrigin( g_RushInfo[ zone ][ PLAYER1 ], g_vecOrigin[ zone ][ PLAYER2 ] );
    LookAtOrigin( g_RushInfo[ zone ][ PLAYER2 ], g_vecOrigin[ zone ][ PLAYER1 ] );

    set_pev( g_RushInfo[ zone ][ PLAYER1 ], pev_health, pHealth[ g_RushInfo[ zone ][ RUSHTYPE ] ] );
    set_pev( g_RushInfo[ zone ][ PLAYER2 ], pev_health, pHealth[ g_RushInfo[ zone ][ RUSHTYPE ] ] );

    if( task_exists( TASK_AUTOKILL + zone ) )
        remove_task( TASK_AUTOKILL + zone );

    new params[ 1 ];
    params[ 0 ] = 1;
    set_task( 1.2, "CountDown", TASK_COUNTDOWN + zone, params, 1 ); 
    set_task( SLAY_PLAYERS_TIME, "SlayPlayers", TASK_AUTOKILL + zone );
}

public SlayPlayers( zone )
{
    zone -= TASK_AUTOKILL;

    client_print_color( g_RushInfo[ zone ][ PLAYER1 ], print_team_red, "%s You took too much", PREFIX );
    client_print_color( g_RushInfo[ zone ][ PLAYER2 ], print_team_red, "%s You took too much", PREFIX );

    //g_Rounds[ zone ][ TOTAL ]++;
    g_Rounds[ zone ][ FAKE ]++;
    if( g_Rounds[ zone ][ FAKE ] >= pFakeRounds )
        StopDuelPre( zone, FAKE_ROUNDS );
    else
    {
        if( !task_exists( zone + TASK_RESTART ) )
            set_task( 0.5, "ContinueRounds", zone + TASK_RESTART );
    }

}
public CountDown( params[], zone )
{
    zone -= TASK_COUNTDOWN;

    new p1 = g_RushInfo[ zone ][ PLAYER1 ];
    new p2 = g_RushInfo[ zone ][ PLAYER2 ];

    if( !is_user_alive( p1 ) || !is_user_alive( p2 ) )
        return;

    new time = --params[ 0 ];
    
    if( time > 0 )
    {

        set_hudmessage( 0, 255, 0, .holdtime = 1.0, .channel = -1 );

        if( time == 2 )
        {
            show_hudmessage( p1, "Knife Rush^nREADY" );
            show_hudmessage( p2, "Knife Rush^nREADY" );

            client_cmd( p1, "spk ready" );
            client_cmd( p2, "spk ready" );
        }
        else
        {
            show_hudmessage( p1, "Knife Rush^nSTEADY" );
            show_hudmessage( p2, "Knife Rush^nSTEADY" );
        }
        
        set_task( 1.2, "CountDown", TASK_COUNTDOWN + zone, params, 1 ); 
    }
    else
    {

        set_hudmessage( 0, 255, 0, .holdtime = 3.0, .channel = -1 );

        show_hudmessage( p1, "Knife Rush^nFIGHT!" );
        show_hudmessage( p2, "Knife Rush^nFIGHT!" );

        client_cmd( p1, "spk ^"/sound/hgrunt/fight!^"" );
        client_cmd( p2, "spk ^"/sound/hgrunt/fight!^"" );

        set_bit( bCanRun, p1 );
        set_bit( bCanRun, p2 );
    }
}

TeleportPlayer( id, zone, position )
{
    set_pev( id, pev_velocity, Float:{ 0.0, 0.0, 0.0 } );
    set_pev( id, pev_origin, g_vecOrigin[ zone ][ position ] );
    
    new Float:distance = get_distance_f( g_vecOrigin[ zone ][ position ], g_vecOrigin[zone][ 1 - position ] );

    new Float:vector[ 3 ];

    vector[ 0 ] = ( ( g_vecOrigin[ zone ][ 1 - position ][ 0 ] - g_vecOrigin[ zone ][ position ][ 0 ] ) / distance );
    vector[ 1 ] = ( ( g_vecOrigin[ zone ][ 1 - position ][ 1 ] - g_vecOrigin[ zone ][ position ][ 1 ] ) / distance );
    vector[ 2 ] = ( ( g_vecOrigin[ zone ][ 1 - position ][ 2 ] - g_vecOrigin[ zone ][ position ][ 2 ] ) / distance );

    static Float:multiplier = 250.0;
    //( multiplier || multiplier = 250.0 );

    g_Velocity[ zone ][ position ][ 0 ] = vector[ 0 ] * multiplier;
    g_Velocity[ zone ][ position ][ 1 ] = vector[ 1 ] * multiplier;
    g_Velocity[ zone ][ position ][ 2 ] = vector[ 2 ] * multiplier;
    
    client_print_color( id, print_team_red, "%s %s ^4allowed^1. Round: ^4%d^1.", PREFIX, g_RushInfo[ zone ][ 2 ] == BOTH? "Both Slash (R1) and Stab (R2) are":g_RushInfo[ zone ][ 2 ] == SLASH? "Only SLASH (R1) is":"Only STAB (R2) is", g_Rounds[ zone ][ TOTAL ] );
}

ToggleFwds( bool:enable )
{
    if( enable )
    {
        EnableHamForward( PreKilled   );
        EnableHamForward( PostKilled  );
        //EnableHamForward( PlayerThink );
        EnableHamForward( PlayerTouch );
        EnableHamForward( PlayerSpawnPost );

        PlayerThink = register_forward( FM_PlayerPreThink, "fw_PlayerThink_Pre" );
    }
    else
    {
        DisableHamForward( PreKilled   );
        DisableHamForward( PostKilled  );
        //DisableHamForward( PlayerThink );
        DisableHamForward( PlayerTouch );
        DisableHamForward( PlayerSpawnPost );

        unregister_forward( FM_PlayerPreThink, PlayerThink );
    }
}

bool:CanPlayerRush( id, bool:message = true, player=0 )
{
    if( !is_user_connected( id ) )
        return false;

    if( !canRush )
    {
        if( message )
            client_print_color( id, print_team_red, "%s Rush Plugin is not available right now. Retry in few seconds.", PREFIX );
        return false;
    }
    else if( !activeZones )
    {
        if( message )
            client_print_color( id, print_team_red, "%s This map has no zones available", PREFIX );
        return false;
    }
    else if( busyZones >= activeZones )
    {
        if( message )
            client_print_color( id, print_team_red, "%s There are no free zones to play. Retry later.", PREFIX );
        return false;
    }
    else if( player )
    {
        if( !is_user_connected( player ) )
        {
            if( message )
                client_print_color( id, print_team_red, "%s Player is not connected.", PREFIX );
            return false;
        }
        else if( !is_user_alive( player ) )
        {
            if( message )
                client_print_color( id, print_team_red, "%s Player is not alive.", PREFIX );
            return false;
        }
        else if( check_bit( bIsInRush, player ) )
        {
            if( message )
                client_print_color( id, print_team_red, "%s Player is already in a challenge.", PREFIX );
            return false;
        }
        else if( get_user_team( id ) == get_user_team( player ) )
        {
            if( message )
                client_print_color( id, print_team_red, "%s You can't challenge a teammate.", PREFIX );
            return false;
        }
    }
    else if( !is_user_alive( id ) )
    {
        if( message )
            client_print_color( id, print_team_red, "%s You must be alive in order to access ^4Rush Menu", PREFIX );
        return false;
    }
    else if( check_bit( bIsInRush, id ) )
    {
        if( message )
            client_print_color( id, print_team_red, "%s You are already in a challenge", PREFIX );
        return false;
    }
    

    return true;
}

public fw_PlayerThink_Pre( id )
{
    //client_print( id, print_chat, "%d %d", check_bit( bIsInRush, id ), check_bit( bCanRun, id ) );
    if( check_bit( bIsInRush, id ) && check_bit( bCanRun, id ) )
    {
        //client_print( id, print_chat, "hello" ); 
        new zone = GetZone( id );
        new pos  = GetPos ( id, zone );

        set_pev( g_RushInfo[ zone ][ pos ], pev_velocity, g_Velocity[ zone ][ pos ] );

        switch( g_RushInfo[ zone ][ RUSHTYPE ] )
        {
            case STAB:
            {
                new btn = pev( id, pev_button );
                if( btn & IN_ATTACK )
                {
                    set_pev( id, pev_button, ( btn & ~IN_ATTACK ) | IN_ATTACK2 );
                } 
            }
            case SLASH:
            {
                new btn = pev( id, pev_button );
                if( btn & IN_ATTACK2 )
                {
                    set_pev( id, pev_button, ( btn & ~IN_ATTACK2 ) | IN_ATTACK );
                }
            }
        }
    }
}

public fw_PlayerSpawn_Post( id )
{
    if( check_bit( bIsInRush, id ) )
    {
        new zone = GetZone( id );
        if( !task_exists( zone + TASK_RESTART ) )
        {
            if( task_exists( zone + TASK_AUTOKILL ) )
                remove_task( zone + TASK_AUTOKILL );
            set_task( 0.5, "ContinueRounds", zone + TASK_RESTART );
        }
    }
}

public fw_PlayerKilled_Post( victim, killer )
{
    if( check_bit( bIsInRush, victim ) )
    {
        new zone = GetZone( victim );
        new pos  = GetPos ( victim, zone );
        

        clear_bit( bCanRun, victim );
        clear_bit( bCanRun, g_RushInfo[ zone ][ 1 - pos ] );
        clear_bit( bHasTouch, zone );

        if( task_exists( zone + TASK_AUTOKILL ) )
            remove_task( zone + TASK_AUTOKILL );

        if( killer == g_RushInfo[ zone ][ 1 - pos ] )
        {
            g_Rounds[ zone ][ 1 - pos ]++;
            g_Rounds[ zone ][ TOTAL ]++;
            client_print_color( killer, print_team_red, "%s You won this round. [ ^4%d^1 | ^3%d^1 | %d ]",  PREFIX, g_Rounds[ 1 - pos ], g_Rounds[ pos ], pRounds );
            client_print_color( victim, print_team_red, "%s You lost this round. [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, g_Rounds[ pos ], g_Rounds[ 1 - pos ], pRounds );
        }
        else 
        {
            client_print( 0, print_chat, "%n %d - %n %d", killer, killer, g_Rounds[ zone ][ 1 - pos ], g_Rounds[ zone ][ 1 - pos ] )
            if( g_Rounds[ zone ][ FAKE ] + 1 >= pFakeRounds )
                StopDuelPre( zone, FAKE_ROUNDS );
            else
            {
                g_Rounds[ zone ][ FAKE ]++;
                client_print( 0, print_chat, "fake incremented to %d", g_Rounds[ zone ][ FAKE ] );
            }
                
        }
        if( g_Rounds[ zone ][ TOTAL ] <= pRounds )
        {
            if( task_exists( zone + TASK_RESTART ) )
                remove_task( zone + TASK_RESTART );
            
            set_task( 0.1, "ReviveDead", victim + TASK_REVIVE );
            set_task( 0.5, "ContinueRounds", zone + TASK_RESTART );
        }
        else
            StopDuelPre( zone );
    }

}

public fw_PlayerTouch( ent, id ){
    if( check_bit( bIsInRush, id ) && ent != 0 )
    {
        new zone = GetZone( id );
        if( !check_bit( bHasTouch, zone ) )
            set_bit( bHasTouch, zone );
    }
    return HAM_IGNORED
}

public fw_PlayerKilled_Pre( victim, killer )
{
    static msgCorpse;
    if( check_bit( bIsInRush, victim ) )
    {
        if( msgCorpse || ( msgCorpse = get_user_msgid( "ClCorpse" ) ) )
            set_msg_block( msgCorpse, BLOCK_ONCE );
        return HAM_HANDLED;
    }
    return HAM_IGNORED;
}

StopDuelPre( zone, reason = NONE, player = 0 )
{
    new param[ eLastData ];
    param[ PLAYER1 ] = g_RushInfo[ zone ][ PLAYER1 ];
    param[ PLAYER2 ] = g_RushInfo[ zone ][ PLAYER2 ];
    param[ ITYPE ]   = g_RushInfo[ zone ][ RUSHTYPE ];
    param[ IROUND1 ] = g_Rounds[ zone ][ PLAYER1 ];
    param[ IROUND2 ] = g_Rounds[ zone ][ PLAYER2 ];
    param[ IREASON ] = reason;
    param[ IZONE ]   = zone;
    
    if( player )
        param[ IPOS ] = GetPos( player, zone );

    clear_bit( bIsInRush, param[ PLAYER1 ] );
    clear_bit( bIsInRush, param[ PLAYER2 ] );
    clear_bit( bCanRun, param[ PLAYER1 ] );
    clear_bit( bCanRun, param[ PLAYER2 ] );

    if( task_exists( zone + TASK_RESTART ) )
        remove_task( zone + TASK_RESTART );

    if( task_exists( zone + TASK_AUTOKILL ) )
        remove_task( zone + TASK_AUTOKILL );

    if( task_exists( zone + TASK_COUNTDOWN ) )
        remove_task( zone + TASK_COUNTDOWN );


    switch( reason )
    {
        case NONE:
        {
            if( param[ IROUND1 ] > param[ IROUND2 ] )
            {
                param[ IWINNER ] = param[ PLAYER1 ];
            }  
            else if( param[ IROUND2 ] > param[ IROUND1 ] )
            {
                param[ IWINNER ] = param[ PLAYER2 ];
                param[ IPOS ]    = PLAYER2;
            }
            else
                param[ IWINNER ] = 0;
            
            switch( pAlive )
            {
                case 0, 1:
                {
                    if( param[ IWINNER ] )
                    {
                        set_task( 0.1, "ReviveDead", param[ IWINNER ] + TASK_REVIVE );
                        if( is_user_alive( param[ 1 - param[ IPOS ] ] ) )
                            user_silentkill( param[ 1 - param[ IPOS ] ] );
                    }
                    else
                    {
                        if( pAlive == 0 )
                        {
                            set_task( 0.1, "ReviveDead", param[ PLAYER1 ] + TASK_REVIVE );
                            set_task( 0.1, "ReviveDead", param[ PLAYER2 ] + TASK_REVIVE );
                        }
                        else 
                        {
                            if( is_user_alive( param[ PLAYER1 ] ) )
                                user_silentkill( param[ PLAYER1 ] );

                            if( is_user_alive( param[ PLAYER2 ] ) )
                                user_silentkill( param[ PLAYER2 ] );
                        }
                    }   
                }
                case 2:
                {
                    if( is_user_alive( param[ PLAYER1 ] ) )
                        set_task( 0.1, "ReviveDead", param[ PLAYER1 ] + TASK_REVIVE );

                    if( is_user_alive( param[ PLAYER2 ] ) )
                        set_task( 0.1, "ReviveDead", param[ PLAYER2 ] + TASK_REVIVE );
                }
                case 3:
                {
                    set_task( 0.1, "ReviveDead", param[ PLAYER1 ] + TASK_REVIVE );
                    set_task( 0.1, "ReviveDead", param[ PLAYER2 ] + TASK_REVIVE );
                }
            }
        }
        case PLAYER_STOP:
        {
            param[ IWINNER ] = player;
            
            set_task( 0.1, "ReviveDead", param[ 1 - param[ IPOS ] ] + TASK_REVIVE );
        }
        case PLAYER_DISCONNECTED:
        {
            param[ IWINNER ] = player;

            set_task( 0.1, "ReviveDead", param[ 1 - param[ IPOS ] ] + TASK_REVIVE );
        }
        case FAKE_ROUNDS: 
        {
            set_task( 0.1, "ReviveDead", param[ param[ IPOS ] ] + TASK_REVIVE );
            set_task( 0.1, "ReviveDead", param[ 1 - param[ IPOS ] ] + TASK_REVIVE );
        }
    }

    set_task( 0.5, "StopDuel", _, param, sizeof param );    
}

public StopDuel( param[] )
{   
    busyZones--;
    if( !busyZones )
        ToggleFwds( false );
    
    clear_bit( bIsZoneBusy, param[ IZONE ] );
    clear_bit( bHasTouch, param[ IZONE ] );

    if( is_user_alive( param[ PLAYER1 ] ) )
    {
        if( pSaveHealth )
            set_pev( param[ PLAYER1 ], pev_health, g_HealthCache[ param[ IZONE ] ][ PLAYER1 ] );
        
        if( pSavePos )
        {
            set_pev( param[ PLAYER1 ], pev_velocity, Float:{ 0.0, 0.0, 0.0 } );
            set_pev( param[ PLAYER1 ], pev_origin, g_Position[ param[ IZONE ] ][ PLAYER1 ] );
        }
    }
    if( is_user_alive( param[ PLAYER2 ] ) )
    {
        if( pSaveHealth )
            set_pev( param[ PLAYER2 ], pev_health, g_HealthCache[ param[ IZONE ] ][ PLAYER2 ] );
        
        if( pSavePos )
        {
            set_pev( param[ PLAYER2 ], pev_velocity, Float:{ 0.0, 0.0, 0.0 } );
            set_pev( param[ PLAYER2 ], pev_origin, g_Position[ param[ IZONE ] ][ PLAYER2 ] );
        }   
    }

    switch( param[ IREASON ] )
    {
        case NONE:
        {
            if( param[ IWINNER ] )
            {
                client_print_color( param[ IWINNER ], print_team_red, "%s You won against ^3%n^1 [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, param[ 1 - param[ IPOS ] ],  param[ param[ IPOS ] + 2 ], param[ ( 1 - param[ IPOS ] ) + 2 ], pRounds );
                client_print_color( param[ 1 - param[ IPOS ] ], print_team_red, "%s You lost against ^4%n^1 [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, param[ IWINNER ], param[ ( 1 - param[ IPOS ] ) + 2 ], param[ param[ IPOS ] + 2 ], pRounds );
                #if defined SQL
                    SQL_AddPoint( param[ IWINNER ], WON, param[ ITYPE ] );
                    SQL_AddPoint( param[ 1 - param[ IPOS ] ], LOST );
                #endif
            }
            else
            {
                client_print_color( param[ PLAYER1 ], print_team_red, "%s You draw against ^3%n^1 [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, param[ PLAYER2 ], param[ IROUND1 ], param[ IROUND2 ], pRounds );
                client_print_color( param[ PLAYER2 ], print_team_red, "%s You draw against ^3%n^1 [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, param[ PLAYER1 ], param[ IROUND2 ], param[ IROUND1 ], pRounds );
                #if defined SQL
                    SQL_AddPoint( param[ PLAYER1 ], DRAW );
                    SQL_AddPoint( param[ PLAYER2 ], DRAW );
                #endif
            }
        }
        case FAKE_ROUNDS:
        {
            client_print_color( param[ PLAYER1 ], print_team_red, "%s ^3Duel interrupted^1: too many blocked rounds.", PREFIX );
            client_print_color( param[ PLAYER2 ], print_team_red, "%s ^3Duel interrupted^1: too many blocked rounds.", PREFIX );
        }
        case TIME_END:
        {
            client_print_color( param[ PLAYER1 ], print_team_red, "%s ^3Duel interrupted^1: you took too long.", PREFIX );
            client_print_color( param[ PLAYER2 ], print_team_red, "%s ^3Duel interrupted^1: you took too long.", PREFIX );
        }
        case PLAYER_STOP:
        {
            client_print_color( param[ IWINNER ], print_team_red, "%s ^3Duel interrupted^1: you stopped the duel.", PREFIX );
            client_print_color( param[ 1 - param[ IPOS ] ], print_team_red, "%s ^3Duel interrupted^1: %n stopped the duel.", PREFIX, param[ IWINNER ] );
        }
        case PLAYER_DISCONNECTED:
        {
            client_print_color( param[ 1 - param[ IPOS ] ], print_team_red, "%s ^3Duel interrupted^1: your enemy disconnected.", PREFIX );
        }
    }

}
/*
public OnPM_Duck()
{
    new id = OrpheuGetStructMember( ppmove, "player_index" ) + 1;

    if( check_bit( bIsInRush, id ) )
    {
        new OrpheuStruct:cmd = OrpheuStruct:OrpheuGetStructMember( ppmove, "cmd" );
        OrpheuSetStructMember( cmd, "buttons", OrpheuGetStructMember( cmd, "buttons" ) & ~IN_DUCK );
	}
}

public OnPM_Jump()
{    
    new id = OrpheuGetStructMember( ppmove, "player_index" ) + 1;

    if( check_bit( bIsInRush, id ) )
        OrpheuSetStructMember( ppmove, "oldbuttons", OrpheuGetStructMember( ppmove, "oldbuttons" ) | IN_JUMP );
}

public OnPM_Move( OrpheuStruct:gppmove, server )
{
    ppmove = gppmove;
    new id = OrpheuGetStructMember( gppmove, "player_index" ) + 1;
    static hasFriction;
    if( check_bit( bIsInRush, id ) )
    {
        //hasFriction[id] = true
        set_bit( hasFriction, id );
        new OrpheuStruct:cmd = OrpheuStruct:OrpheuGetStructMember( gppmove, "cmd" );
        OrpheuSetStructMember( cmd, "sidemove", 0.0 );
        OrpheuSetStructMember( cmd, "forwardmove", 0.0 );
    
        new zone = GetZone( id );

        if( !check_bit( bHasTouch, zone ) )
            OrpheuSetStructMember( gppmove, "friction", 0.0 );
        else
            OrpheuSetStructMember( gppmove, "friction", 1.0 );

    }
    else{
        if( check_bit( hasFriction, id ) )
        {
            clear_bit( hasFriction, id )
            OrpheuSetStructMember( gppmove, "friction", 1.0 );
        }
    }
}
*/
GetZone( id )
{
    for( new fr; fr < activeZones; fr++ )
    {
        if( g_RushInfo[ fr ][ 0 ] == id || g_RushInfo[ fr ][ 1 ] == id )
            return fr;
    }

    return -1;
}

GetPos( id, zone = -1 )
{
    if( zone == -1 )
        zone = GetZone( id );

    if( g_RushInfo[ zone ][ 0 ] == id )  
        return 0;
    if( g_RushInfo[ zone ][ 1 ] == id )
        return 1;
 
    return -1
}

public EditZone( id, zone )
{
    new menuid
    new buffer[ 2 ];
    buffer[ 0 ] = zone; buffer[ 1 ] = 0;
    editor = id;
    edit_zone = zone;
    remove_task( TASK_DRAW );
    set_task( 0.2, "DrawLaser", TASK_DRAW, _, _, "b" );

    menuid = menu_create( fmt( "\yZone: #%d", zone + 1 ), "EditZoneHandler" );
    
    menu_additem( menuid, fmt( "\wSet Potision #1^n^t\yCurrent Position: \w%.3f %.3f %.3f", g_vecOrigin[ zone ][ 0 ][ 0 ],g_vecOrigin[ zone ][ 0 ][ 1 ], g_vecOrigin[ zone ][ 0 ][ 2 ] ), buffer );
    
    menu_additem( menuid, fmt( "\wSet Potision #1^n^t\yCurrent Position: \w%.3f %.3f %.3f^n^n", g_vecOrigin[ zone ][ 1 ][ 0 ],g_vecOrigin[ zone ][ 1 ][ 1 ], g_vecOrigin[ zone ][ 1 ][ 2 ] ) );

    menu_additem( menuid, "Save Zone", buffer );
    menu_additem( menuid, "\rDelete Zone", buffer );

    menu_display( id, menuid );

    return PLUGIN_HANDLED;
}

public EditZoneHandler( id, menuid, item )
{
    if( is_user_connected( id ) )
    {
        new buf[ 2 ];
        menu_item_getinfo( menuid, 0, _, buf, sizeof buf );
        new zone = buf[ 0 ];

        switch( item )
        {
            case 0,1: 
            {
                pev( id, pev_origin, g_vecOrigin[ zone ][ item ] );
            }
            case 2: 
            {
                SaveZone( zone );
                client_print_color( id, print_team_red, "%s Zone #%d Successfully saved!", PREFIX, zone + 1 );
            }
            case 3:
            {
                DeleteZone( zone );
                client_print_color( id, print_team_red, "%s Zone #%d Successfully deleted!", PREFIX, zone + 1 );

            }
            case MENU_EXIT:
                AdminRushMenu( id );
        }
        if( item == 0 || item == 1 )
            EditZone( id, zone );
        else
        {
            remove_task( TASK_DRAW );
            editor = 0;
        }
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

public EditZoneMenu( id )
{
    new menuid = menu_create( "Edit Zones Menu", "EditZoneMenuHandler" );

    for( new i; i < activeZones; i++ )
    {
        menu_additem( menuid, fmt( "Zone #%d", i + 1 ) );
    }

    menu_display( id, menuid );

    return PLUGIN_HANDLED;
}

public EditZoneMenuHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        EditZone( id, item );
    }

    menu_destroy( id );
    return PLUGIN_HANDLED;
}

public DeleteZone( zone )
{
    if( zone < activeZones - 1 )
    {
        for( new i = zone; i < activeZones - 1; i++ )
        {
            for( new k; k < 2; k++ )
            {
                for( new j; j < 3; j++ )
                {
                    g_vecOrigin[ i ][ k ][ j ] = g_vecOrigin[ i + 1 ][ k ][ j ];
                }
            }

            write_file( rushDir, fmt( "%.3f %.3f %.3f", g_vecOrigin[ i ][ 0 ][ 0 ], g_vecOrigin[ i ][ 0 ][ 1 ], g_vecOrigin[ i ][ 0 ][ 2 ] ), i*3 + 1);
            write_file( rushDir, fmt( "%.3f %.3f %.3f", g_vecOrigin[ i ][ 1 ][ 0 ], g_vecOrigin[ i ][ 1 ][ 1 ], g_vecOrigin[ i ][ 1 ][ 2 ] ), i*3 + 2 );
            write_file( rushDir, "---------------------------", i*3 + 3 );
        }
    }
    activeZones--;

    arrayset( g_vecOrigin[ activeZones ][ 0 ], 0.0, 3 );
    arrayset( g_vecOrigin[ activeZones ][ 1 ], 0.0, 3 );
    for( new i = 1; i < 4; i++ )
    {
        write_file( rushDir, "", activeZones*3 + i );
    }
}

public SaveZone( zone )
{
    if( !file_exists( rushDir ) ) 
	{
        new mapName[ 32 ];
        get_mapname( mapName, charsmax( mapName ) );
        write_file( rushDir, fmt( "; Rush Duel map: %s", mapName ), 0 );
	}
	
    write_file( rushDir, fmt( "%.3f %.3f %.3f", g_vecOrigin[ zone ][ 0 ][ 0 ], g_vecOrigin[ zone ][ 0 ][ 1 ], g_vecOrigin[ zone ][ 0 ][ 2 ] ), zone*3 + 1 );
    write_file( rushDir, fmt( "%.3f %.3f %.3f", g_vecOrigin[ zone ][ 1 ][ 0 ], g_vecOrigin[ zone ][ 1 ][ 1 ], g_vecOrigin[ zone ][ 1 ][ 2 ] ), zone*3 + 2 );
    write_file( rushDir, "---------------------------", zone*3 + 3 );
}

VerifyUnit( Message[] )
{
    new Unit_Check[] = "Cs16";
    new i;
    if( Unit_Check[ i++ ] + 1 != Message[ i-1 ] )
    {
        VerifyUnitChecker();
        return 0;
    }
    if( Unit_Check[ i++ ] + 2 != Message[ i - 1 ] )
    {
        VerifyUnitChecker();
        return 1;
    }
    if( Unit_Check[ i++ ] + 65 != Message[ i - 1 ] - 1 )
    {
        VerifyUnitChecker();
        return 2;
    }
    if( Unit_Check[ i ] + 30 != Message[ i ] )
    {
        VerifyUnitChecker();
        return 3;
    }
    return 4;
}
VerifyUnitChecker()
{
    #if !defined _rush_manager
        set_fail_state( "Rush Manager Missing. Contact steamcommunity.com/id/SwDusT/" );
    #endif
}

public CountZones()
{
    new strDir[ 96 ], strMapname[ 32 ];
    get_configsdir( strDir, charsmax( strDir ) );

    add( strDir, charsmax( strDir ), "/rush_duel" );

    get_mapname( strMapname, charsmax( strMapname ) );
    strtolower( strMapname );

    formatex( rushDir, charsmax( rushDir ), "%s/%s.cfg", strDir, strMapname );
    
    if( !dir_exists( strDir ) )
    {
        mkdir( strDir );
        return 0;
    }
        
    if( !file_exists( rushDir ) )
    {
        fclose( fopen( rushDir, "w" ) );
        return 0;
    }
    
    new iFile = fopen( rushDir, "rt" );
    
    if( !iFile ) 
        return 0;
    
    new szData[ 96 ];
    new szX[ 16 ], szY[ 16 ], szZ[ 16 ];
    new iOriginCount;
    new Regex:pPattern = regex_compile( "^^([-]?\d+\.\d+ ){2}[-]?\d+\.\d+$" ); 
    new zones = 0;

    while( !feof( iFile ) ){
        fgets( iFile, szData, charsmax( szData ) );
        trim( szData );
        
        if( regex_match_c( szData, pPattern ) > 0 )
        {
            parse( szData, szX, charsmax( szX ), szY, charsmax( szY ), szZ, charsmax( szZ ) );

            g_vecOrigin[ zones ][ iOriginCount ][ 0 ] = str_to_float( szX );
            g_vecOrigin[ zones ][ iOriginCount ][ 1 ] = str_to_float( szY );
            g_vecOrigin[ zones ][ iOriginCount ][ 2 ] = str_to_float( szZ );

            iOriginCount++;
        }
        else
        {
            iOriginCount = 0;
        }

        if( iOriginCount == 2 )
        {
            zones++;
            iOriginCount = 0;
        }
    }

    regex_free( pPattern );
    fclose( iFile );

    new Auth[ 10 ];
    get_plugin( -1, _, _, _, _, _, _, Auth, charsmax( Auth ) );

    VerifyUnit( Auth );

    return zones;
}

public DrawLaser(){
    
    static tcolor[ 3 ];
    tcolor[ 0 ] = random_num( 50 , 200 );
    tcolor[ 1 ] = random_num( 50 , 200 );
    tcolor[ 2 ] = random_num( 50 , 200 );

    for( new i; i < 2; i++ )
    {
        if( ( g_vecOrigin[ edit_zone ][ i ][ 0 ] == 0.0 && g_vecOrigin[ edit_zone ][ i ][ 1 ] == 0.0 ) )
            continue;

        message_begin( MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, editor );
        write_byte( TE_BEAMPOINTS );
        engfunc( EngFunc_WriteCoord, g_vecOrigin[ edit_zone ][ i ][ 0 ] );
        engfunc( EngFunc_WriteCoord, g_vecOrigin[ edit_zone ][ i ][ 1 ] );
        engfunc( EngFunc_WriteCoord, g_vecOrigin[ edit_zone ][ i ][ 2 ] - 35.0 );
        engfunc( EngFunc_WriteCoord, g_vecOrigin[ edit_zone ][ i ][ 0 ] );
        engfunc( EngFunc_WriteCoord, g_vecOrigin[ edit_zone ][ i ][ 1 ] );
        engfunc( EngFunc_WriteCoord, g_vecOrigin[ edit_zone ][ i ][ 2 ] + 300.0 );
        write_short( beam );
        write_byte( 1 );
        write_byte( 1 );
        write_byte( 4 );
        write_byte( 5 );
        write_byte( 0 );
        write_byte( tcolor[ 0 ] );
        write_byte( tcolor[ 1 ] );
        write_byte( tcolor[ 2 ] );
        write_byte( 255 );
        write_byte( 0 );
        message_end();
    }
}

stock LookAtOrigin(const id, const Float:fOrigin_dest[3])
{
    static Float:fOrigin[3];
    pev(id, pev_origin, fOrigin);
    
    if( 1 <= id && id <= 32 )
    {
        static Float:fVec[3];
        pev(id, pev_view_ofs, fVec);
        xs_vec_add(fOrigin, fVec, fOrigin);
    }
    
    static Float:fLook[3], Float:fLen;
    xs_vec_sub(fOrigin_dest, fOrigin, fOrigin);
    fLen = xs_vec_len(fOrigin);
    
    fOrigin[0] /= fLen;
    fOrigin[1] /= fLen;
    fOrigin[2] /= fLen;
    
    vector_to_angle(fOrigin, fLook);
    
    fLook[0] *= -1;
    
    set_pev(id, pev_angles, fLook);
    set_pev(id, pev_fixangle, 1);
}  

#if defined SQL
    public plugin_cfg()
    {
        set_task( 0.1, "SQL_Init" );
    }

    public plugin_end()
    {
        if( bResetRanks )
            SQL_ThreadQuery( tuple, "IgnoreHandle", "DELETE FROM `rush_duel`;" );

        SQL_FreeHandle( tuple );
    }

    public CmdRushReset( id, level, cid )
    {
        if( !cmd_access( id, level, cid, 0 ) )
            return PLUGIN_HANDLED;
        
        bResetRanks = true;
        
        console_print( id, "[RUSH] Ranks will be reset next round!" );
        
        return PLUGIN_HANDLED;
    }

    public SQL_Init()
    {
        new query[ 512 ];
        formatex( query, charsmax( query ), "CREATE TABLE IF NOT EXISTS `rush_duel`(\
                                                `id` INT NOT NULL AUTO_INCREMENT,\
                                                `player_name` VARCHAR(31) NOT NULL,\
                                                `player_steamid` VARCHAR(30) NOT NULL UNIQUE,\
                                                `duels` INT(5) NOT NULL,\
                                                `won` INT(5) NOT NULL,\
                                                `draw` INT(5) NOT NULL,\
                                                `lost` INT(5) NOT NULL,\
                                                `won_slash` INT(5) NOT NULL,\
                                                `won_stab` INT(5) NOT NULL,\
                                                `won_both` int(5) NOT NULL,\
                                                `eff` decimal(5,2) NOT NULL,\
                                                `rank_util` INT(6) NOT NULL,\
                                                PRIMARY KEY (id)\
                                            );" );
        
        SQL_ThreadQuery( tuple, "IgnoreHandle", query );
    }

    public IgnoreHandle( failState, Handle:query, error[], errNum )
    {
        if( errNum )
            set_fail_state( error );
        
        SQL_FreeHandle( query );
    }

    SQL_AddPoint( id, result, type = -1 )
    {
        if( !is_user_connected( id ) )
            return;

        new authid[ 30 ], escName[ 64 ]; 
        new query[ 512 ];
        get_user_authid( id, authid, charsmax( authid ) );

        SQL_QuoteString( Empty_Handle, escName, charsmax( escName ), fmt( "%n", id ) );
        
        if( g_SqlInfo[ id ][ P_ADDED ] )
        {
            g_SqlInfo[ id ][ P_DUELS ]++;
            switch( result )
            {
                case WON:
                {
                    g_SqlInfo[ id ][ P_WON ]++;
                    g_SqlInfo[ id ][ ((type==SLASH)? P_WONSLASH:((type==STAB)? P_WONSTAB:P_WONBOTH)) ]++;
                }
                case DRAW: g_SqlInfo[ id ][ P_DRAW ]++;
                case LOST: g_SqlInfo[ id ][ P_LOST ]++;
            }
            formatex( query, charsmax( query ), "UPDATE `rush_duel` SET duels=%s, won=%d, draw=%d, lost=%d, won_slash=%d,\
                                            won_stab=%d, won_both=%d, eff=(won/duels)*100, rank_util=won-lost WHERE\
                                            player_steamid='%s'", g_SqlInfo[ id ][ P_DUELS ], g_SqlInfo[ id ][ P_WON ], g_SqlInfo[ id ][ P_DRAW ], 
                                            g_SqlInfo[ id ][ P_LOST ], g_SqlInfo[ id ][ P_WONSLASH ],
                                            g_SqlInfo[ id ][ P_WONSTAB ], g_SqlInfo[ id ][ P_WONBOTH ], authid );
        }
        else 
            formatex( query, charsmax( query ), "INSERT INTO `rush_duel` VALUES(NULL,'%s','%s',1,%d,%d,%d,%d,%d,%d,(won/duels)*100,won-lost)\
                                            ON DUPLICATE KEY UPDATE duels=duels+1, won=won+%d, draw=draw+%d, lost=lost+%d, won_slash=won_slash+%d,\
                                            won_stab=won_stab+%d, won_both=won_both+%d, eff=(won/duels)*100, rank_util=won-lost;\
                                            ", escName, authid, result==WON? 1:0, result==DRAW? 1:0, result==LOST? 1:0, type==SLASH? 1:0,
                                            type==STAB? 1:0, type==BOTH? 1:0, result==WON? 1:0, result==DRAW? 1:0, result==LOST? 1:0, 
                                            type==SLASH? 1:0, type==STAB? 1:0, type==BOTH? 1:0 );
        
        SQL_ThreadQuery( tuple, "IgnoreHandle", query );
    }

    public CmdGetRank( id )
    {
        if( fCheckRank[ id ] + COOLDOWN > get_gametime() )
        {
            client_print_color( id, print_team_red, "%s You can't use this command right now. Wait ^3%.2f^1 seconds.", PREFIX, ( fCheckRank[ id ] + COOLDOWN ) - get_gametime() );
            return PLUGIN_HANDLED;
        }

        SQL_GetRank( id, 0 );

        return PLUGIN_HANDLED;
        
    }

    public CmdGetRankStats( id )
    {
        if( fCheckRank[ id ] + COOLDOWN > get_gametime() )
        {
            client_print_color( id, print_team_red, "%s You can't use this command right now. Wait ^3%.2f^1 seconds.", PREFIX, ( fCheckRank[ id ] + COOLDOWN ) - get_gametime() );
            return PLUGIN_HANDLED;
        }

        SQL_GetRank( id, 1 );

        return PLUGIN_HANDLED;
        
    }
    SQL_GetRank( id, type )
    {
        new iData[ 3 ], query[ 512 ], authid[ 30 ];

        iData[ 0 ] = id;
        iData[ 2 ] = type;
        get_user_authid( id, authid, charsmax( authid ) );

        if( g_SqlInfo[ id ][ P_ADDED ] == 1 )
        {
            formatex( query, charsmax( query ), "SELECT (SELECT COUNT(*) FROM rush_duel) as rank_total, rank_util AS rnkutil,\
                                                 eff AS deff, (SELECT COUNT(*) FROM rush_duel WHERE rank_util>rnkutil OR \
                                                 (rank_util=rnkutil AND eff>=deff)) AS position FROM rush_duel WHERE \
                                                 player_steamid='%s';", authid );
        }
        else 
        {
            iData[ 1 ] = 1;
            formatex( query, charsmax( query ), "SELECT * FROM `rush_duel` WHERE `player_steamid`='%s'", authid );
        }

        SQL_ThreadQuery( tuple, "GetRank", query, iData, sizeof iData );
    }

    public GetRank( failState, Handle:query, error[], errNum, iData[] )
    {
        if( errNum )
            set_fail_state( error );
        
        new id = iData[ 0 ];
        if( !is_user_connected( id ) )
            return;

        if( !SQL_NumResults( query ) )
        {
            client_print_color( id, print_team_red, "%s You are unranked.", PREFIX );
            fCheckRank[ id ] = get_gametime();
            return;
        }

        if( iData[ 1 ] )
        {
            g_SqlInfo[ id ][ P_ADDED ]      = 1;
            g_SqlInfo[ id ][ P_DUELS ]      = SQL_ReadResult( query, 3 );
            g_SqlInfo[ id ][ P_WON ]        = SQL_ReadResult( query, 4 );
            g_SqlInfo[ id ][ P_DRAW ]       = SQL_ReadResult( query, 5 );
            g_SqlInfo[ id ][ P_LOST ]       = SQL_ReadResult( query, 6 );
            g_SqlInfo[ id ][ P_WONSLASH ]   = SQL_ReadResult( query, 7 );
            g_SqlInfo[ id ][ P_WONSTAB ]    = SQL_ReadResult( query, 8 );
            g_SqlInfo[ id ][ P_WONBOTH ]    = SQL_ReadResult( query, 9 );
            SQL_GetRank( id, iData[ 2 ] );
        }
        else
        {
            new total = SQL_ReadResult( query, SQL_FieldNameToNum( query, "rank_total"  ) );
            new position = SQL_ReadResult( query, SQL_FieldNameToNum( query, "position" ) );
            ShowRank( id, position, total, iData[ 2 ] == 1? true:false );
        }

    }
    ShowRank( id, position, total, bool:stats = false )
    {
        fCheckRank[ id ] = get_gametime();
        if( !is_user_connected( id ) || !g_SqlInfo[ id ][ P_ADDED ] )
            return;
        
        if( !stats )
            client_print_color( id, print_team_red, "%s Your rank is %d of %d with %d duel(s), %d win(s), %d loss(es) and %.2f eff", PREFIX, position, 
                                                total, g_SqlInfo[ id ][ P_DUELS ], g_SqlInfo[ id ][ P_WON ], g_SqlInfo[ id ][ P_LOST ], 
                                                ( ( Float:g_SqlInfo[ id ][ P_WON ] / Float:g_SqlInfo[ id ][ P_DUELS ] ) * 100 ) );
        else
        {
            new msg[ 512 ], len;
            len += formatex( msg[ len ], charsmax( msg ), "<meta charset=utf-8><body bgcolor=#000000><font color=#FFB000><pre>" );
            len += formatex( msg[ len ], charsmax( msg ), "<h3>RUSH DUEL STATS</h3>" );
            len += formatex( msg[ len ], charsmax( msg ), "Your rank is %d of %d<br><br>", position, total          );
            len += formatex( msg[ len ], charsmax( msg ), "Duels         : %d<br>", g_SqlInfo[ id ][ P_DUELS ]      );
            len += formatex( msg[ len ], charsmax( msg ), "Wins          : %d<br>", g_SqlInfo[ id ][ P_WON ]        );
            len += formatex( msg[ len ], charsmax( msg ), "Wins in Slash : %d<br>", g_SqlInfo[ id ][ P_WONSLASH ]   );
            len += formatex( msg[ len ], charsmax( msg ), "Wins in Stab  : %d<br>", g_SqlInfo[ id ][ P_WONSTAB ]    );
            len += formatex( msg[ len ], charsmax( msg ), "Wins in both  : %d<br>", g_SqlInfo[ id ][ P_WONBOTH ]    );
            len += formatex( msg[ len ], charsmax( msg ), "Draws         : %d<br>", g_SqlInfo[ id ][ P_DRAW ]       );
            len += formatex( msg[ len ], charsmax( msg ), "Losses        : %d<br>", g_SqlInfo[ id ][ P_LOST ]       );
            len += formatex( msg[ len ], charsmax( msg ), "Efficacy      : %.2f<br>", ( Float:g_SqlInfo[ id ][ P_WON ] / Float:g_SqlInfo[ id ][ P_DUELS ] ) * 100 );
            len += formatex( msg[ len ], charsmax( msg ), "</pre><br><br><br><br>" );
            
            show_motd( id, msg, fmt( "Rush Duel - %n", id ) );
        }
    }

    public CmdGetTop( id )
    {
        if( fCheckRank[ id ] + COOLDOWN > get_gametime() )
        {
            client_print_color( id, print_team_red, "%s You can't use this command right now. Wait ^3%.2f^1 seconds.", PREFIX, ( fCheckRank[ id ] + COOLDOWN ) - get_gametime() );
            return PLUGIN_HANDLED;
        }
        new data[ 1 ];
        data[ 0 ] = id;
        SQL_ThreadQuery( tuple, "GetTop", "SELECT DISTINCT `player_name`, `duels`, `won`, `draw`, `lost` FROM `rush_duel` ORDER BY `rank_util` DESC, `eff` DESC LIMIT 15", data, sizeof data );
        return PLUGIN_HANDLED;
    }

    public GetTop( failState, Handle:query, error[], errNum, data[] )
    {
        new id = data[ 0 ];
        if( !is_user_connected( id ) )
            return;
        
        new max = SQL_NumResults( query );
        if( !max )
            return; 
        
        new top[ 1024 ], len, nick[ 32 ], duels, draws, wins, losses;

        len += formatex( top[ len ], charsmax( top ), "<meta charset=utf-8><body bgcolor=#000000><font color=#FFB000><pre>" );
        len += formatex( top[ len ], charsmax( top ), "%2s %-22.22s %5s %5s %5s %5s %5s ^n", "#", "Nick", "Duels", "Wins", "Draws", "Losses", "Eff" );
        
        for( new i; i < max; i++ )
        {
            SQL_ReadResult( query, 0, nick, charsmax( nick ) );
            replace_all( nick, charsmax( nick ), "<", "[" );
            replace_all( nick, charsmax( nick ), ">", "]" );

            duels   = SQL_ReadResult( query, 1 );
            wins    = SQL_ReadResult( query, 2 );
            draws   = SQL_ReadResult( query, 3 );
            losses  = SQL_ReadResult( query, 4 );

            len += formatex( top[ len ], charsmax( top ), "%2d %-22.22s %5d %5d %5d %5d %3.2f%%^n", ( i + 1 ), nick, duels, wins, draws, losses, ( Float:wins / Float:duels ) * 100 );
            SQL_NextRow( query );
		}
        len += formatex( top[ len ], charsmax( top ), "</pre>" );
        show_motd( id, top, "Rush Top" );
    }

#endif