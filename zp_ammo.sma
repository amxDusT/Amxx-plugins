/*

*/
#include < amxmodx >
#include < amxmisc >
#include < sqlx >
//#include < zp50_core >
#include < zp50_ammopacks >
#include < zp50_colorchat_const >

#define DEBUG
#define ADMIN_SUPER_ADM    ADMIN_LEVEL_A

#define set_bit(%1,%2)      (%1 |= (1<<(%2&31)))
#define clear_bit(%1,%2)    (%1 &= ~(1<<(%2&31)))
#define check_bit(%1,%2)    (%1 & (1<<(%2&31)))

new const TASK_SAVE = 35353;
new const VERSION[] = "1.3.1";

new const host[] = ""; 
new const user[] = "";
new const pass[] = "";	
new const db[]   = "";

new table[] = "zp_ammo";

new bJustInserted;
new bHasJoined;

new Handle:tuple;

new iTotalAmmo[ MAX_PLAYERS + 1 ];
new pInitialAmmo;

new szSteamid[ MAX_PLAYERS + 1 ][ 35 ];
new szIP[ MAX_PLAYERS + 1 ][ MAX_IP_LENGTH ];
public plugin_init()
{
    register_plugin( "ZP Ammo", VERSION, "DusT" );
    tuple = SQL_MakeDbTuple( host, user, pass, db );
    bind_pcvar_num( get_cvar_pointer( "zp_starting_ammo_packs" ), pInitialAmmo );

    hook_cvar_change( create_cvar( "zp_save_ammo_time", "300", _, 
        "Saves ammo for everyone in the server. 0 = disabled.", true, 0.0 ), "@OnHookChange" );
    register_clcmd( "say", "CmdSay" );
}
@OnHookChange( pcvar, old_value[], new_value[] )
{
    new old_val = str_to_num( old_value );
    new new_val = str_to_num( new_value );

    if( old_val == new_val )    return;
    
    if( task_exists( TASK_SAVE ) )
        remove_task( TASK_SAVE );
    
    if( !new_val )      return; 
    set_task( float( new_val ), "SaveAmmoTask", TASK_SAVE, _, _, "b" );
}

public SaveAmmoTask()
{
    new players[ MAX_PLAYERS ], num;
    get_players( players, num, "ch" );
    for( new i; i < num; i++ )
    {
        SaveAmmo( players[ i ] );
    }
}
SaveAmmo( id )
{
    if( !check_bit( bHasJoined, id ) ) return;
    new query[ 256 ];
    new escName[ 64 ];
    SQL_QuoteStringFmt( Empty_Handle, escName, charsmax( escName ), "%n", id );
    formatex( query, charsmax( query ), "UPDATE `%s` SET `ammo`=%d, `total_ammo`=`total_ammo`+%d\ 
            WHERE `player_nick`='%s';", table, zp_ammopacks_get( id ), iTotalAmmo[ id ], escName );
    #if defined DEBUG
    log_to_file( "zp_ammo.log", "QUERY UPDATE: %s", query );
    #endif
    SQL_ThreadQuery( tuple, "IgnoreHandle", query );
}

is_super_admin( id )
{
    return get_user_flags( id ) & ADMIN_SUPER_ADM;
}
public CmdSay( id )
{
    new args[ 64 ], cmd[ 10 ], target[ MAX_NAME_LENGTH ];
    read_args( args, charsmax( args ) );
    remove_quotes( args ); trim( args );
    
    if( args[ 0 ] != '/' && args[ 0 ] != '!' )
        return PLUGIN_CONTINUE;
    format( args, charsmax( args ), "%s", args[ 1 ] );
    parse( args, cmd, charsmax( cmd ), target, charsmax( target ) );
    
    if( !equali( cmd, "ammo" ) && !equali( cmd, "ap" ) )
        return PLUGIN_CONTINUE;
    
    new player = target[ 0 ]? cmd_target( id, target, CMDTARGET_ALLOW_SELF ):id;

    if( is_super_admin( player ) && !is_user_admin( id ) )
    {
        client_print_color( id, print_team_red, "%s%n has ^3Immunity^1.", ZP_PREFIX, player );
        return PLUGIN_HANDLED;
    }

    if( !player )
        player = id;
    
    client_print_color( id, print_team_red, "%s%n has ^3%d AmmoPacks^1.", ZP_PREFIX, player, zp_ammopacks_get( player ) );

    return PLUGIN_HANDLED;
}

public plugin_cfg(){
    set_task( 0.1, "SQL_Init" );
    new time = get_cvar_num( "zp_save_ammo_time" );
    if( time > 0 )
        set_task( float( time ), "SaveAmmoTask", TASK_SAVE, _, _, "b" );
}

public zp_on_ammo_change( id, ammo, flag )
{
    if( flag == ZP_AP_INITIAL )
        return; 
    
    if( !check_bit( bHasJoined, id ) )
        return; 

    if( ammo <= 0 )
        return; 

    iTotalAmmo[ id ] += ammo;
}


public plugin_end()
{
    SQL_FreeHandle( tuple );
}

public client_putinserver( id ){
    zp_ammopacks_set( id, 0, ZP_AP_INITIAL );
    if( !is_user_bot( id ) && !is_user_hltv( id ) )
        set_task( 1.0, "SQL_GetAmmos", id );
}

public SQL_GetAmmos( id )
{
    if( !is_user_connected( id ) )
        return;
    
    new escName[ 64 ], data[ 2 ];
    data[ 0 ] = id; data[ 1 ] = 0;
    SQL_QuoteStringFmt( Empty_Handle, escName, charsmax( escName ), "%n", id );

    SQL_ThreadQuery( tuple, "SQL_GetAmmosHandler", fmt( "SELECT `ammo` FROM `%s` WHERE `player_nick`='%s';", table, escName ), data, sizeof data );
}

public SQL_GetAmmosHandler( failState, Handle:query, error[], errNum, data[] )
{
    new id = data[ 0 ];
    if( !is_user_connected( id ) )
        return;
    
    get_user_authid( id, szSteamid[ id ], charsmax( szSteamid[] ) );
    get_user_ip( id, szIP[ id ], charsmax( szIP[] ), true );
    if( !SQL_NumResults( query ) )
    {
        new escName[ 64 ];
        
        SQL_QuoteStringFmt( Empty_Handle, escName, charsmax( escName ), "%n", id );
        set_bit( bJustInserted, id );
        //id, nick, steamid, ip, ammo, total_ammo
        SQL_ThreadQuery( tuple, "IgnoreHandle", fmt( "INSERT INTO `%s` VALUES(NULL,'%s','%s','%s',%d,%d);", table, escName, szSteamid[ id ], szIP[ id ], pInitialAmmo, pInitialAmmo ) );
        zp_ammopacks_set( id, pInitialAmmo, ZP_AP_INITIAL );
    }
    else
        zp_ammopacks_set( id, SQL_ReadResult( query, 0 ), ZP_AP_INITIAL );
        
    
    set_bit( bHasJoined, id );
}
public client_disconnected( id ){
    if( task_exists( id ) )
        remove_task( id );
    
    new escName[ 64 ];
    SQL_QuoteStringFmt( Empty_Handle, escName, charsmax( escName ), "%n", id );

    if( check_bit( bHasJoined, id ) )
    {
        new query[ 512 ];
        if( check_bit( bJustInserted, id ) )
        {
            formatex( query, charsmax( query ), "UPDATE `%s` SET `ammo`=%d, `total_ammo`=`total_ammo`+%d\ 
            WHERE `player_nick`='%s';", table, zp_ammopacks_get( id ), iTotalAmmo[ id ], escName );
        }
        else
        {
            formatex( query, charsmax( query ), "UPDATE `%s` SET `ammo`=%d, `total_ammo`=`total_ammo`+%d,\ 
            `player_steamid`='%s', `player_ip`='%s' WHERE `player_nick`='%s';", table, zp_ammopacks_get( id ), iTotalAmmo[ id ], szSteamid[ id ], szIP[ id ], escName );
        }
        #if defined DEBUG
        log_to_file( "zp_ammo.log", "QUERY DISCONNECT: %s", query );
        #endif
        SQL_ThreadQuery( tuple, "IgnoreHandle", query );
        clear_bit( bHasJoined, id );
        clear_bit( bJustInserted, id );
    }
    iTotalAmmo[ id ] = 0;
}

/*
    INSERT INTO `zp_ammo`
    SELECT `id`,`nick`,`steam_id`,`ip`,`ammo`, `total_ammo`
    FROM `zp_players`

*/
public SQL_Init()
{
    new query[ 512 ];
    formatex(query, charsmax(query), "CREATE TABLE IF NOT EXISTS `%s`(\
                                        id INT NOT NULL AUTO_INCREMENT,\
                                        player_nick VARCHAR(63) NOT NULL UNIQUE,\
                                        player_steamid VARCHAR(35) DEFAULT NULL,\
                                        player_ip VARCHAR(20) DEFAULT NULL,\
                                        ammo INT NOT NULL,\
                                        total_ammo INT NOT NULL,\
                                        PRIMARY KEY(id)\
                                      );", table );
    SQL_ThreadQuery( tuple, "IgnoreHandle", query );
}
public IgnoreHandle( failState, Handle:query, error[], errNum )
{
    if( errNum )
        set_fail_state( error );
}
