#include < amxmodx >
#include < fakemeta >

public plugin_init()
{
    register_plugin( "Block Kill Command", "1.1", "DusT" );
    
    register_forward( FM_ClientKill, "@OnClientSuicide" );
}

@OnClientSuicide( id )
{
    if( !is_user_alive( id ) )
        return FMRES_IGNORED;
    
    console_print( id, "You cannot kill yourself!" );
    return FMRES_SUPERCEDE;
}