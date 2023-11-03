/*
    acer m2 only
*/

#include <amxmodx>

#include < reapi >
//#pragma semicolon 1

new pActive;
public plugin_init()
{
    register_plugin( "[reApi] Acer", "1.0", "DusT" );

    pActive = register_cvar( "amx_m2_only", "1" );

}
public plugin_cfg()
{
    new szMap[ 15 ];
    get_mapname( szMap, charsmax( szMap ) );

    if( containi( szMap, "ka_acer_2" ) != -1 && get_pcvar_num( pActive ) )
    {
        RegisterHookChain( RG_CBasePlayer_PreThink, "fw_PlayerPreThink" );
        RegisterHookChain( RG_CBasePlayer_Spawn, "fw_Spawn_Post", true );   
    }
}
public fw_Spawn_Post( id )
{
    rg_remove_all_items( id );
    rg_give_item( id, "weapon_knife", GT_REPLACE );
}
public fw_PlayerPreThink( id )
{
    static iButton; 
    iButton = get_entvar( id, var_button );
    if( iButton & IN_ATTACK )
    {
        set_entvar( id, var_button, ( iButton & ~IN_ATTACK ) | IN_ATTACK2 );
    }
}