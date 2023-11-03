#include <amxmodx>
#include <engine>

new bool:bHasCam[ MAX_PLAYERS + 1 ];
public plugin_init()
{
    register_plugin( "Cam Toggle", "1.0", "DusT" );
    register_clcmd( "say /cam", "CamToggle" );
    register_clcmd( "say cam", "CamToggle" );
    register_clcmd( "say /tp", "CamToggle" );
    register_clcmd( "say tp", "CamToggle" );
    register_clcmd( "say 3d", "CamToggle" );
    register_clcmd( "say /3d", "CamToggle" );
    //register_forward( FM_AddToFullPack, "fw_AddToFullPack", 1 );
}
public plugin_precache()
{
    precache_model( "models/rpgrocket.mdl" );
}
public CamToggle( id )
{
    if( bHasCam[id] )
    {
        set_view( id, CAMERA_NONE );
        client_print_color( id, print_team_red, "^4[KM]^1 Camera ^3disabled^1." );
    }
    else 
    {
        set_view( id, CAMERA_3RDPERSON );
        client_print_color( id, print_team_blue, "^4[KM]^1 Camera ^3enabled^1." );
    }
        

    bHasCam[ id ] = !bHasCam[ id ];
    return PLUGIN_HANDLED;
}
public client_disconnected( id )
{
    bHasCam[ id ] = false;
}

/*public fw_AddToFullPack( es_handle, e, ent, host, hostflags, player, pSet )
{
    if( player && !is_user_bot(ent) )
    {
        set_es(es_handle, ES_RenderAmt, 255 );
        if(player && ent == host ){
            set_es( es_handle, ES_Scale, 0.2 );
        }
    }
}*/