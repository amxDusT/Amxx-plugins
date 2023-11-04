/*
    Changelog:
        - added natives for various vm items
        - added jumps cvar
        1.1: 
            - insta enable 
            - keep item on reconnection
        1.1.1: 
            - fixed insta enable
    TODO: 
        - check todos 
        - ?
*/

#include < amxmodx >
//#include < amxmisc >
//#include < fakemeta >
#include < reapi >
#include < zp_lasermine >
#include < zp50_class_human >
#include < zp50_class_zombie >
#include < zp50_colorchat_const >
#include < zpv_vip >

enum _:eItems
{
    VITEM_DISABLED = -1,
    VITEM_NONE = 0,
    VITEM_DAMAGE,
    VITEM_JUMP,
    VITEM_SPEED,
    VITEM_GRAVITY,
    VITEM_INVIS,
    VITEM_LMS
}
new const szVipItems[ eItems ][] = {
    "VITEM_NONE",
    "VITEM_DAMAGE",
    "VITEM_JUMP",
    "VITEM_SPEED",
    "VITEM_GRAVITY",
    "VITEM_INVIS",
    "VITEM_LMS"
} 
new bool:pCvarInstaEnable;
new bool:pCvarKeepActiveOnDisconnect;
new Trie:tLastItemActive; 
new bool:bSlowMode[ MAX_PLAYERS + 1 ];
new bool:pCvarsEnabled[ eItems ];
new Float:pDamageMultiplier, Float:pSpeed, Float:pGravity, pInvis, pLMs;
new pJumps;
new iCurrent[ MAX_PLAYERS + 1 ], iNext[ MAX_PLAYERS + 1 ];
new pAdminHasVIP;
new iNumUsing;
new HookChain:fwSpawn;
public plugin_init()
{
    register_plugin( "[ZP] VIP Menu", "1.1.2", "DusT" );

    register_clcmd( "say /vm", "@OnVipmenuSay" );
    
    register_logevent("@OnRoundStart", 2, "0=World triggered", "1=Round_Start" );

    DisableHookChain( fwSpawn = RegisterHookChain( RG_CSGameRules_PlayerSpawn, "@OnPlayerSpawn_Post", true ) );
    CreateCvars();    
    AutoExecConfig( true );
    register_dictionary( "zp_vipmenu.txt" );
    tLastItemActive = TrieCreate();
}
public OnConfigsExecuted()
{
    new flags[ 32 ];
    get_cvar_string( "zpv_vip_flags", flags, charsmax( flags ) );
    pAdminHasVIP = read_flags( flags );
}
public client_disconnected( id )
{
    if( task_exists( id ) )
        remove_task( id );
    if( !is_vip( id ) )     return;

    bSlowMode[ id ] = false;
    if( pCvarKeepActiveOnDisconnect || pCvarInstaEnable )
    {
        new name[ MAX_NAME_LENGTH ];
        get_user_name( id, name, charsmax( name ) ); 
        strtolower( name ); 
        TrieSetCell( tLastItemActive, name, iCurrent[ id ] );
    }
}
public client_putinserver( id )
{
    if( iNext[ id ] )
        iNext[ id ] = VITEM_NONE;
    if( iCurrent[ id ] )
        iCurrent[ id ] = VITEM_NONE;
    
    new name[ MAX_NAME_LENGTH ];
    get_user_name( id, name, charsmax( name ) ); 
    strtolower( name ); 
    new item; 
    if( TrieGetCell( tLastItemActive, name, item ) )
    {
        if( pCvarKeepActiveOnDisconnect )
        {

            iCurrent[ id ] = item;
            iNext[ id ] = item; 
            GiveItem( id, false );
        }
        if( pCvarInstaEnable )
            bSlowMode[ id ] = true;
    }
    
}
@OnRoundStart()
{
    TrieClear( tLastItemActive );
    new players[ MAX_PLAYERS ], num;
    get_players( players, num, "ch" );
    for( new i, id; i < num; i++ )
    {
        id = players[ i ];
        if( !is_vip( id ) ) continue;
        if( iCurrent[ id ] == iNext[ id ] ) continue;
        RemoveItem( id );
        iCurrent[ id ] = iNext[ id ];
        GiveItem( id );
    }
}
@OnPlayerSpawn_Post( id )
{
    if( iCurrent[ id ] == VITEM_INVIS )
        set_task( 0.1, "SetRendering", id );
}
GiveItem( id, bool:message = true )
{
    switch( iCurrent[ id ] )
    {
        case VITEM_DAMAGE: zpv_damage_set( id, pDamageMultiplier );
        case VITEM_JUMP: zpv_jumps_set( id, pJumps );
        case VITEM_SPEED: { zpv_human_speed_set( id, (pSpeed/100.0)); zpv_zombie_speed_set( id, (pSpeed/100.0)); }
        case VITEM_GRAVITY: { zpv_human_gravity_set( id, -(pGravity/100.0)); zpv_zombie_gravity_set( id, -(pGravity/100.0)); }
        case VITEM_LMS: set_task( float( pLMs ), "@OnLMReceived", id, .flags="b" );
        case VITEM_INVIS:
        {
            set_task( 0.1, "SetRendering", id );
            if( !iNumUsing )
            {
                EnableHookChain( fwSpawn );
                iNumUsing++;
            }
        } 
    }
    if( message )
    {
        if( iCurrent[ id ] == VITEM_LMS )
            client_print_color( id, id, "%s%l", ZP_PREFIX, "ZPV_ITEM_ENABLED", szVipItems[ VITEM_LMS ], pLMs );
        else
            client_print_color( id, id, "%s%l", ZP_PREFIX, "ZPV_ITEM_ENABLED", szVipItems[ iCurrent[ id ] ] );
    }
}
RemoveItem( id )
{
    switch( iCurrent[ id ] )
    {
        case VITEM_DAMAGE: zpv_damage_reset( id );
        case VITEM_JUMP: zpv_jumps_reset( id );
        case VITEM_SPEED: { zpv_human_speed_reset( id ); zpv_zombie_speed_reset( id ); }
        case VITEM_GRAVITY: { zpv_human_gravity_reset( id ); zpv_zombie_gravity_reset( id ); }
        case VITEM_LMS: remove_task( id );
        case VITEM_INVIS: 
        {
            rg_set_user_rendering( id );
            iNumUsing--;
            if( !iNumUsing )
                DisableHookChain( fwSpawn );
        }
    }
}
public SetRendering( id )
{
    rg_set_user_rendering( id, _, _, kRenderTransAlpha, 255 - pInvis * 2  );    // TODO: check if percentage are good.
}
@OnVipmenuSay( id )
{
    if( !is_vip(id) )
    {
        client_print_color( id, id, "%s%l", ZP_PREFIX, "ZPV_NO_ACCESS" );
    }
    else
        VipMenu( id );
    return PLUGIN_HANDLED;
}

VipMenu( id )
{
    new menuid = menu_create( "VIP Menu", "@MenuHandler", true );
    for( new i, param[ 3 ]; i < eItems; i++ )
    {
        if( !pCvarsEnabled[ i ] )   continue;

        num_to_str( i, param, charsmax( param ) );
        if( i != VITEM_LMS )
            menu_additem( menuid, fmt( "%L%s%s", id, szVipItems[ i ], iCurrent[id]==i? "\w[\yACTIVE\w]":"", (iCurrent[id]!=i && iNext[id]==i)? "\w[\rNEXT\w]":"" ) , param );
        else
        {
            menu_additem( menuid, fmt( "%L%s%s", id, szVipItems[ VITEM_LMS ], pLMs, iCurrent[id]==i? "\w[\yACTIVE\w]":"", (iCurrent[id]!=i && iNext[id]==i)? "\w[\rNEXT\w]":"" ), param );
        }
    }
    if( !menu_items( menuid ) )
    {
        client_print_color( id, id, "%s%l", ZP_PREFIX, "ZPV_NO_ITEMS" ); 
        menu_destroy( menuid );
        return;
    }
    menu_display( id, menuid );
}
@MenuHandler( id, menuid, item )
{
    if( !is_user_connected( id ) )
        return menu_return( menuid );
    
    if( item < 0 )
        return menu_return( menuid );
    
    new param[ 3 ];
    menu_item_getinfo( menuid, item, _, param, charsmax( param ) );
    new iVipItem = str_to_num( param );
    if( pCvarsEnabled[ iVipItem ] && iNext[ id ] != iVipItem )
    {
        iNext[ id ] = iVipItem;
        if( iNext[ id ] != iCurrent[ id ] )
        {
            if( pCvarInstaEnable && !bSlowMode[ id ] )
            {
                iCurrent[ id ] = iNext[ id ]; 
                bSlowMode[ id ] = true;
                GiveItem( id );
            }
            else
            {
                if( iVipItem == VITEM_LMS )
                    client_print_color( id, print_team_default, "%s%l", ZP_PREFIX, "ZPV_ITEM_NEXT_ROUND", szVipItems[ iVipItem ], pLMs );
                else
                    client_print_color( id, print_team_default, "%s%l", ZP_PREFIX, "ZPV_ITEM_NEXT_ROUND", szVipItems[ iVipItem ] );
            }
        }
    }
    return menu_return( menuid );
}
menu_return( menuid )
{
    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}
is_vip( id )
{
    return get_user_flags(id) & pAdminHasVIP;
}
CreateCvars()
{
    bind_pcvar_num( create_cvar( "zpv_item_none", "1", _, 
        "Show 'None' in the vipmenu and allow to deselect other elements", true, 0.0, true, 1.0 ), pCvarsEnabled[ VITEM_NONE ] );
    bind_pcvar_num( create_cvar( "zpv_item_damage", "1", _, 
        "Enable Extra Damage.", true, 0.0, true, 1.0 ), pCvarsEnabled[ VITEM_DAMAGE ] );
    bind_pcvar_num( create_cvar( "zpv_item_jump", "1", _, 
        "Enable Extra Jump.", true, 0.0, true, 1.0 ), pCvarsEnabled[ VITEM_JUMP ] );
    bind_pcvar_num( create_cvar( "zpv_item_speed", "1", _, 
        "Enable Extra Speed.", true, 0.0, true, 1.0 ), pCvarsEnabled[ VITEM_SPEED ] );
    bind_pcvar_num( create_cvar( "zpv_item_gravity", "1", _, 
        "Enable Extra Gravity.", true, 0.0, true, 1.0 ), pCvarsEnabled[ VITEM_GRAVITY ] );
    bind_pcvar_num( create_cvar( "zpv_item_invis", "1", _, 
        "Enable Invisibility.", true, 0.0, true, 1.0 ), pCvarsEnabled[ VITEM_INVIS ] );
    bind_pcvar_num( create_cvar( "zpv_item_lms", "1", _, 
        "Enable Extra LMs.", true, 0.0, true, 1.0 ), pCvarsEnabled[ VITEM_LMS ] );
    

    bind_pcvar_num( create_cvar( "zpv_instant_enable", "1", _, 
        "Enable item as soon as player chooses it if first time choosing item.", true, 0.0, true, 1.0 ), pCvarInstaEnable );
    bind_pcvar_num( create_cvar( "zpv_item_disconnected", "1", _,
        "Keep the item active for the player if reconnects on same round", true, 0.0, true, 1.0 ), pCvarKeepActiveOnDisconnect );

    bind_pcvar_float( create_cvar( "zpv_damage_power", "1.2", _,
        "How strong is Extra Damage.", true, 1.0 ), pDamageMultiplier );
    bind_pcvar_float( create_cvar( "zpv_speed", "10", _,
        "Percentage of speed to add (Default ZOMBIE speed is 75%. Default HUMAN speed is 100%)." ), pSpeed );
    bind_pcvar_float( create_cvar( "zpv_gravity", "20", _,
        "Percentage of gravity to substract (Default ZOMBIE and HUMAN gravity is 100% (800 gravity) )." ), pGravity );
    bind_pcvar_num( create_cvar( "zpv_invis", "60", _,
        "Percentage of invisibility." ), pInvis );
    bind_pcvar_num( create_cvar( "zpv_lms_time", "100", _,
        "How long before getting a free LM. Time is in seconds." ), pLMs );
    bind_pcvar_num( create_cvar( "zpv_jumps", "1", _,
        "How many jumps to give", true, 1.0 ), pJumps );
    hook_cvar_change( create_cvar( "zpv_vip_flags", "b", _,
        "Flags needed to be considered VIP by the plugin" ), "@OnFlagsChange" );
}

@OnFlagsChange( pcvar, const old_value[], const new_value[] )
{
    pAdminHasVIP = read_flags( new_value );
}
@OnLMReceived( id )
{
    if( !is_user_connected( id ) )  return;
    if( iCurrent[ id ] != VITEM_LMS )   return;
    zp_lm_set( id, zp_lm_get( id ) + 1 );
    client_print_color( id, id, "%s%l", ZP_PREFIX, "ZPV_LM_RECEIVED" );
}

rg_set_user_rendering(index, fx = kRenderFxNone, {Float,_}:color[3] = {0.0,0.0,0.0}, render = kRenderNormal, amount = 0 )
{
    set_entvar(index, var_renderfx, fx);
    set_entvar(index, var_rendercolor, color);
    set_entvar(index, var_rendermode, render);
    set_entvar(index, var_renderamt, float(amount) );
} 

public plugin_end()
    TrieDestroy( tLastItemActive );