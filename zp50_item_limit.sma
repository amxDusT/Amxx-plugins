/*
    NAME
    TIME : 0 = disabled (default 0)
    LIMIT : 0 = disabled (default 0)
    RESET : ROUND or SPAWN (spawn includes round) (default ROUND)
    BUY_TEXT : off/0
    SHOW_LIMIT : 0/off or MENU or TEXT

    EXTRA_SLOTS: NUMBER
    EXTRA_COST: 200
    EXTRA_INCREASE: 50
    
    [item]
    NAME = Antidote
    TIME = 270
    LIMIT = 5
    RESET = ROUND | SPAWN

    [item]
    NAME = Infection Bomb
    TIME = 270
    LIMIT = 5
    RESET = ROUND 
*/
#include < amxmodx >
#include < zp50_items >
#include < zp50_gamemodes >
#include < zp50_colorchat_const >
#include < zp50_ammopacks >
#include < reapi >

#pragma compress 1 

// ==== EDITABLE =====

//#define DEBUG
#define EXTRA_SLOTS_ITEM   "*Extra Slots Menu*"
new const szSlotCmd[][] =
{
    "!buyslots",
    "/buyslots",
    "/slots",
    "!slots",
}
#define MAX_ITEMS   64
new const INI_FILE[] = "/zp50_item_limit.ini";

// ===================

#define SetBit(%1,%2)      (%1 |= (1<<(%2&31)))
#define ClearBit(%1,%2)    (%1 &= ~(1<<(%2&31)))
#define GetBit(%1,%2)    (%1 & (1<<(%2&31)))

#define TASK_CHECK 125
#define TASK_CHECKA 1126
#define ZPD_ITEM_ERROR -2
#define ZPD_ITEM_INVALID -1

enum _:eReset
{
    RESET_ROUND = 0,
    RESET_SPAWN = 1
}
enum _:eShowLimit
{
    LIMIT_NO = 0,
    LIMIT_MENU = 1,
    LIMIT_TEXT = 2
}

enum _:eItems
{
    ITEM_ID,
    ITEM_RESET,
    ITEM_SHOWLIMIT,
    ITEM_BUYTEXT,
    ITEM_TIME,
    ITEM_LIMIT,
    ITEM_EXSLOT,
    ITEM_EXCOST,
    ITEM_EXINC
}
new iItemNum;
new iItem[ MAX_ITEMS ][ eItems ];
new iTime[ MAX_ITEMS ];
new szItemName[ MAX_ITEMS ][ MAX_NAME_LENGTH ];

new iItemsBought[ MAX_PLAYERS + 1 ][ MAX_ITEMS ];
new bool:bCanUse[ MAX_ITEMS ];

new iAdditions[ MAX_PLAYERS + 1 ][ MAX_ITEMS ];

new bool:bChecks[ MAX_PLAYERS ][ MAX_ITEMS ];

new iAnti, iBomb;
new Trie:tAdditions;
new Trie:tItemsBought;
new bHasJoined;
new iExtraSlotsID;
public plugin_init()
{
    register_plugin( "[ZP] Some Limits", "1.1.1", "DusT" );

    #if defined DEBUG
    register_concmd( "zpd_get_item", "GetItem" );
    #endif

    for( new i; i < sizeof szSlotCmd; i++ )
    {
        register_clcmd( fmt( "say %s", szSlotCmd[ i ] ), "CmdBuySlot", _, "Buy extra slots for items" );
    }
    iExtraSlotsID = zp_items_register( EXTRA_SLOTS_ITEM, 0 );

    register_event("HLTV", "@RoundStart", "a", "1=0", "2=0");    
    RegisterHookChain( RG_CSGameRules_PlayerSpawn, "@PlayerSpawn_Post", true );
    register_dictionary( "zp50_item_limit.txt" );
    iItemNum = -1;
    iAnti = -1;
    iBomb = -1;
    INI_Read();
    for( new i; i < iItemNum; i++ )
        if( !iItem[ i ][ ITEM_TIME ] )
            bCanUse[ i ] = true;
    
    tAdditions = TrieCreate();
    tItemsBought = TrieCreate();
}
public plugin_end()
{
    TrieDestroy(tAdditions);
    TrieDestroy(tItemsBought);
}
#if defined DEBUG
public GetItem( id )
{
    new item = read_argv_int( 1 );
    console_print( id, "NAME = %s", szItemName[ item ] );
    console_print( id, "LIMIT = %d", iItem[ item ][ ITEM_LIMIT ] );
    console_print( id, "RESET = %s", iItem[ item ][ ITEM_RESET ] == RESET_ROUND? "ROUND":"SPAWN" );
    console_print( id, "TIME = %d", iItem[ item ][ ITEM_TIME ] );
    console_print( id, "BUYTEXT = %s", iItem[ item ][ ITEM_BUYTEXT ] == 0? "off":"on" );
    console_print( id, "SHOWLIMIT = %s", iItem[ item ][ ITEM_SHOWLIMIT ]==LIMIT_NO?"OFF":(iItem[ item ][ ITEM_SHOWLIMIT ]==LIMIT_MENU? "MENU":"TEXT") );
    console_print( id, "EXTRA_SLOTS = %d", iItem[ item ][ ITEM_EXSLOT ] );
    console_print( id, "EXTRA_COST = %d", iItem[ item ][ ITEM_EXCOST ] );
    console_print( id, "EXTRA_INCREASE = %d", iItem[ item ][ ITEM_EXINC ] );
    
    return PLUGIN_HANDLED;
}
#endif
public plugin_natives()
{
    register_native( "zpd_get_slot_id", "_zpd_get_slot_id" );
    register_native( "zpd_set_item_slot", "_zpd_set_item_slot" );
    register_native( "zpd_get_item_slot", "_zpd_get_item_slot" );
}
public _zpd_get_slot_id( plugin, argc )
{
    if( iItemNum == -1 )
        return ZPD_ITEM_ERROR;

    new str[ MAX_NAME_LENGTH ];
    get_string( 1, str, charsmax( str ) );
    for( new i; i < iItemNum; i++ )
    {
        if( equali( szItemName[ i ], str ) )
            return i;
    }
    return ZPD_ITEM_INVALID;
}
public _zpd_set_item_slot( plugin, argc )
{
    new id = get_param( 1 );
    new item = get_param( 2 );
    new value = get_param( 3 );
    
    if( id < 0 || id >= 32 )
        return false;
    if( item < 0 || item >= iItemNum )
        return false;
    if( value < iItem[ item ][ ITEM_LIMIT ] )
        return false;

    iAdditions[ id ][ item ] = value;
    return true;
}
public _zpd_get_item_slot( plugin, argc )
{
    new id = get_param( 1 );
    new item = get_param( 2 );
    
    if( id < 0 || id >= 32 )
    {
        log_error(504, "Invalid Player ID (%d)", id );
        return 0;
    }
        
    if( item < 0 || item >= iItemNum )
    {
        log_error(504, "Invalid item ID (%d)", item );
        return 0;
    }

    return iAdditions[ id ][ item ];
}

public CmdBuySlot( id )
{
    new const DISABLED = (1<<27);
    new const ADDITION[] = "Slot"
    new menu = menu_create( "Buy Slots Menu", "SlotsMenuHandler" );
    new bool:bAdded;
    for( new i, text[ 64 ], param[ 5 ], cost; i < iItemNum; i++ )
    {
        if( !iItem[ i ][ ITEM_EXSLOT ] )    continue;
        if( !iItem[ i ][ ITEM_EXCOST ] )    continue;

        if( !bAdded )
            bAdded = true;
        cost = iItem[ i ][ ITEM_EXCOST ]+(iAdditions[ id ][ i ]*iItem[ i ][ ITEM_EXINC ]);
        formatex( text, charsmax( text ), "%s %s", szItemName[ i ], ADDITION );
        format( text, charsmax( text ), "%-32.32s\y%d AmmoPacks \w[%d/%d]", 
            text, cost, 
            iAdditions[ id ][ i ], iItem[ i ][ ITEM_EXSLOT ] );
        
        num_to_str( i, param, charsmax( param ) );
        //iAdditions[ id ][ index ] >= iItem[ index ][ ITEM_EXSLOT ]
        if( iAdditions[ id ][ i ] >= iItem[ i ][ ITEM_EXSLOT ] || zp_ammopacks_get( id ) < cost )
            menu_additem( menu, text, _, DISABLED );
        else
            menu_additem( menu, text, param );
    }
    if( !bAdded )
    {
        menu_destroy( menu );
        client_print_color( id, print_team_red, "%s%l", ZP_PREFIX, "ZP_NO_SLOTS" );
    }
    else
        menu_display( id, menu );
}

public SlotsMenuHandler( id, menu, item )
{
    if( is_user_connected( id ) && item > MENU_EXIT )
    {
        new param[ 5 ];
        menu_item_getinfo( menu, item, _, param, charsmax( param ) );
        new index = str_to_num( param );
        new ammo = zp_ammopacks_get( id );
        new cost = iItem[ index ][ ITEM_EXCOST ] + iAdditions[ id ][ index ]*iItem[ index ][ ITEM_EXINC ];
        if( ammo < cost )
        {
            client_print_color( id, print_team_red, "%s%l", ZP_PREFIX, "ZP_NO_AMMO" );
        }
        else if( iAdditions[ id ][ index ] >= iItem[ index ][ ITEM_EXSLOT ] )
        {
            client_print_color( id, print_team_red, "%s%l", ZP_PREFIX, "ZP_MAX_SLOTS", szItemName[ index ] );
        }
        else
        {
            zp_ammopacks_set( id, ammo - cost );
            iAdditions[ id ][ index ]++;

            client_print_color( id, print_team_red, "%s%l %l", ZP_PREFIX, "ZP_SLOT_BOUGHT", szItemName[ index ], "ZP_ITEM_NUMBERS", iAdditions[ id ][ index ], iItem[ index ][ ITEM_EXSLOT ] );
        }
    }
    menu_destroy( menu );
    return PLUGIN_HANDLED;
}

public client_putinserver( id )
{
    new name[ MAX_NAME_LENGTH ];
    get_user_name( id, name, charsmax( name ) );
    strtolower( name );
    TrieGetArray( tAdditions, name, iAdditions[ id ], sizeof iAdditions[] );
    TrieGetArray( tItemsBought, name, iItemsBought[ id ], sizeof iItemsBought[] );
    SetBit( bHasJoined, id );
}

public client_disconnected( id )
{
    if( GetBit( bHasJoined, id ) )
    {
        new name[ MAX_NAME_LENGTH ];
        get_user_name( id, name, charsmax( name ) );
        strtolower( name );
        TrieSetArray( tAdditions, name, iAdditions[ id ], sizeof iAdditions[] );
        TrieSetArray( tItemsBought, name, iItemsBought[ id ], sizeof iItemsBought[] );
        ClearBit( bHasJoined, id );
    }
    arrayset( iItemsBought[ id ], 0, iItemNum );
    arrayset( iAdditions[ id ], 0, iItemNum );
    arrayset( bChecks[ id ], false, iItemNum );
    if( task_exists( TASK_CHECKA + id ) )
        remove_task( TASK_CHECKA + id );
}
@PlayerSpawn_Post( id )
{
    for( new i; i < iItemNum; i++ )
    {
        if( iItem[ i ][ ITEM_RESET ] == RESET_SPAWN )
            iItemsBought[ id ][ i ] = 0;
    }
}
@RoundStart()
{
    new players[ MAX_PLAYERS ], num; 
    get_players( players, num );
    TrieClear( tItemsBought );
    for( new i; i < num; i++ )
    {
        arrayset( iItemsBought[ players[ i ] ], 0, iItemNum );
    }
}
public zp_fw_gamemodes_start( gameid )
{
    static mode1, mode2;
    
    if( !mode1 )
    {
        mode1 = zp_gamemodes_get_id("Infection Mode")
        mode2 = zp_gamemodes_get_id("Multiple Infection Mode")
    }
    if( gameid == mode1 || gameid == mode2 )
    {
        for( new i; i < iItemNum; i++ )
        {
            if( iItem[ i ][ ITEM_TIME ] )
            {
                set_task( float( iItem[ i ][ ITEM_TIME ] ), "AllowUse", i );
                iTime[ i ] = floatround( get_gametime() );
            }
                
        }
    }
}

public zp_fw_gamemodes_end( gameid )
{
    for( new i; i < iItemNum; i++ )
    {
        if( task_exists( i ) )
            remove_task( i );
        if( iItem[ i ][ ITEM_TIME ])
            bCanUse[ i ] = false;
    }
}
public AllowUse( i )
{
    bCanUse[ i ] = true;

    if( i == iAnti && iItem[ iAnti ][ ITEM_TIME ] == iItem[ iBomb ][ ITEM_TIME ] )
        client_print_color( 0, print_team_red, "%s^3%s^1 and ^3%s^1 %l", ZP_PREFIX, szItemName[ iAnti ],szItemName[ iBomb ], "ZP_ITEM_CAN_BUY" );
    else if( i != iBomb || (i == iBomb && iItem[ iAnti ][ ITEM_TIME ] != iItem[ iBomb ][ ITEM_TIME ] ) )
        client_print_color( 0, print_team_red, "%s^3%s^1 %l", ZP_PREFIX, szItemName[ i ], "ZP_ITEM_CAN_BUY" );
}

public zp_fw_items_select_pre( id, item, ignorecost )
{
    new text[32]
    for( new i; i < iItemNum; i++ )
    {
        if( item == iItem[ i ][ ITEM_ID ] )
        {
            bChecks[ id ][ i ] = true;
            new params[ 3 ];
            params[ 0 ] = i;
            set_task( 0.02, "RemoveTrue", TASK_CHECKA + id, params, sizeof params );
            if( iItem[ i ][ ITEM_SHOWLIMIT ] >= LIMIT_MENU )
            {
                formatex(text, charsmax(text), " \w[%d/%d]", iItemsBought[ id ][ i ], iItem[ i ][ ITEM_LIMIT ] + iAdditions[ id ][ i ] );
                zp_items_menu_text_add(text);
            }
            if( iItemsBought[ id ][ i ] >= iItem[ i ][ ITEM_LIMIT ] + iAdditions[ id ][ i ] )
                    return ZP_ITEM_NOT_AVAILABLE;
            if( !bCanUse[ i ] )
            {            
                new index = i-1<0? i+1:i-1;
                
                if( bChecks[ id ][ index ] == false )
                {
                    set_task(0.01, "CheckIndex", TASK_CHECK + id, params, sizeof params );
                }
    
                return ZP_ITEM_NOT_AVAILABLE;
            }
            return ZP_ITEM_AVAILABLE;
        }
    }
    return ZP_ITEM_AVAILABLE;
}

public zp_fw_core_cure_post( id, attacker )
{
    for( new i; i < iItemNum; i++ )
    {
        if( iItem[ i ][ ITEM_RESET ] == RESET_SPAWN )
            iItemsBought[ id ][ i ] = 0;
    }
}
public zp_fw_core_infect_post( id, attacker )
{
    for( new i; i < iItemNum; i++ )
    {
        if( iItem[ i ][ ITEM_RESET ] == RESET_SPAWN )
            iItemsBought[ id ][ i ] = 0;
    }
}

public CheckIndex( params[], id )
{
    id -= TASK_CHECK;
    new i = params[ 0 ];
    new index = i-1<0? i+1:i-1;
    if( bChecks[ id ][ index ] == false )
    {
        client_print_color( id, print_team_red, "%s%l", ZP_PREFIX, "ZP_ITEM_CANNOT_TIME", szItemName[ i ], GetpTime( i ) );
        //client_print( id, print_chat, "Message to be shown" );
    }
}
GetpTime( item )
{
    new time = iItem[ item ][ ITEM_TIME ] - floatround( get_gametime() ) + iTime[ item ];
    new minutes = time / 60; 
    time = time % 60; 
    new msg[ 32 ];
    formatex( msg, charsmax( msg ), "%l", "ZP_TIMELEFT", minutes, time );
    return msg;
}
public RemoveTrue( params[], id )
{
    id -= TASK_CHECKA;
    new i = params[ 0 ];
    bChecks[ id ][ i ] = false;
}
public zp_fw_items_select_post( id, item, ignorecost )
{
    if( task_exists( TASK_CHECK + id ) )
        remove_task( TASK_CHECK + id );
    if( item == iExtraSlotsID )
    {
        CmdBuySlot( id );
        return;
    }
    for( new i; i < iItemNum; i++ )
    {
        if( item == iItem[ i ][ ITEM_ID ] )
        {
            iItemsBought[ id ][ i ]++;
            if( iItem[ i ][ ITEM_BUYTEXT ] )
            {
                if( iItem[ i ][ ITEM_SHOWLIMIT ] == LIMIT_TEXT )
                    client_print_color( id, print_team_red, "%s%l ^3%s^1. %l", ZP_PREFIX, "ZP_ITEM_BOUGHT", szItemName[ i ],"ZP_ITEM_NUMBERS", iItemsBought[ id ][ i ], iItem[ i ][ ITEM_LIMIT ] + iAdditions[ id ][ i ] );
                else
                    client_print_color( id, print_team_red, "%s%l ^3%s^1.", ZP_PREFIX, "ZP_ITEM_BOUGHT", szItemName[ i ] );
            }
            break;
        }
    }
}
INI_Read()
{
    new szDir[ 128 ];
    /*
            enum _:eItems
        {
            ITEM_ID,
            ITEM_RESET,
            ITEM_SHOWLIMIT,
            ITEM_BUYTEXT,
            ITEM_TIME,
            ITEM_LIMIT,
            ITEM_EXSLOT,
            ITEM_EXCOST,
            ITEM_EXINC
        }
    */
    new const szNameName[] = "NAME";
    new const szNames[ eItems ][] = { "", "RESET", "SHOW_LIMIT", "BUY_TEXT", "TIME", "LIMIT", "EXTRA_SLOTS", "EXTRA_COST", "EXTRA_INCREASE"};

    get_localinfo("amxx_configsdir", szDir, charsmax( szDir ) );
    add( szDir, charsmax( szDir ), INI_FILE );

    if( !file_exists( szDir ) )
    {
        set_fail_state( "%s doesn't exist", szDir );
    }
    iItemNum = 0;
    new fp = fopen( szDir, "rt" );
    new szData[ 100 ], szToken[ 35 ], szValue[ 35 ];
    new iItemTemp[ eItems ];
    new szItemNameTemp[ MAX_NAME_LENGTH ];
    new bool:bIsReadingItem = false;
    while( fgets( fp, szData, charsmax( szData ) ) )
    {
        if( szData[ 0 ] == '/' && szData[ 1 ] == '/' )
            continue;
        if( szData[ 0 ] == ';' )
            continue;
        trim( szData );
        if( !szData[ 0 ] )
            continue;

        if( szData[ 0 ] == '[' )
        {
            if( !equali( szData, "[item]" ) )
                continue;
            
            if( !bIsReadingItem )
            {
                bIsReadingItem = true;
                continue;      
            }
            
            //NAME and LIMIT are mandatory
            if( szItemNameTemp[ 0 ] && iItemTemp[ ITEM_LIMIT ] > 0 )
            {
                RegisterItem( szItemNameTemp, iItemTemp );
            }
            szItemNameTemp[ 0 ] = 0;
            iItemTemp[ ITEM_LIMIT ] = 0;
            iItemTemp[ ITEM_SHOWLIMIT ] = LIMIT_NO;
            iItemTemp[ ITEM_RESET ] = RESET_ROUND;
            iItemTemp[ ITEM_BUYTEXT ] = 0;
            iItemTemp[ ITEM_TIME ] = 0;
            iItemTemp[ ITEM_ID ] = 0;
            iItemTemp[ ITEM_EXCOST ] = 0;
            iItemTemp[ ITEM_EXSLOT ] = 0;
            iItemTemp[ ITEM_EXINC ] = 0;
        }
        if( !bIsReadingItem )
            continue;

        strtok2( szData, szToken, charsmax( szToken ), szValue, charsmax( szValue ), '=', TRIM_FULL );
        remove_quotes( szToken );
        remove_quotes( szValue );

        if( equali( szToken, szNameName ) )
        {
            copy( szItemNameTemp, MAX_NAME_LENGTH - 1, szValue );
        }
        else if( equali( szToken, szNames[ ITEM_RESET ] ) )
        {
            if( equali( szValue, "spawn" ) )
                iItemTemp[ ITEM_RESET ] = RESET_SPAWN;
            else
                iItemTemp[ ITEM_RESET ] = RESET_ROUND;
        }
        else if( equali( szToken, szNames[ ITEM_BUYTEXT ] ) )
        {
            if( equali( szValue, "0" ) || equali( szValue, "off" ) )
                iItemTemp[ ITEM_BUYTEXT ] = 0;
            else
                iItemTemp[ ITEM_BUYTEXT ] = 1;
        }
        else if( equali( szToken, szNames[ ITEM_SHOWLIMIT ] ) )
        {
            if( equali( szValue, "text" ) )
                iItemTemp[ ITEM_SHOWLIMIT ] = LIMIT_TEXT;
            else if( equali( szValue, "menu" ) )
                iItemTemp[ ITEM_SHOWLIMIT ] = LIMIT_MENU;
            else if( equali( szValue, "0" ) || equali( szValue, "off" ) )
                iItemTemp[ ITEM_SHOWLIMIT ] = LIMIT_NO;
        }
        else
        {
            for( new i = ITEM_TIME; i < eItems; i++ )
            {
                if( equali( szToken, szNames[ i ] ) )
                {
                    if( !is_str_num( szValue ) )
                        continue;
                    iItemTemp[ i ] = str_to_num( szValue );
                    if( iItemTemp[ i ] < 0 )
                        iItemTemp[ i ] = 0;
                }
            }
        }
    }
    RegisterItem( szItemNameTemp, iItemTemp );
    fclose( fp );
}

RegisterItem( itemName[MAX_NAME_LENGTH], item[ eItems ] )
{
    new const NAMES[][] = { "Antidote", "Infection Bomb" };
    if( iItemNum >= MAX_ITEMS )
    {
        log_amx( "Could not load more items than %d", MAX_ITEMS );
        return;
    }
    iItem[ iItemNum ][ ITEM_ID ] = zp_items_get_id( itemName );
    if( iItem[ iItemNum ][ ITEM_ID ] == ZP_INVALID_ITEM )
    {
        log_amx( "Could not find item %s", itemName );
        return;
    }
    copy( szItemName[ iItemNum ], MAX_NAME_LENGTH - 1, itemName );
    if( equali( itemName, NAMES[ 0 ] ) )
        iAnti = iItemNum;
    else if( equali( itemName, NAMES[ 1 ] ) )
        iBomb = iItemNum;
    iItem[ iItemNum ][ ITEM_LIMIT ] = item[ ITEM_LIMIT ];
    iItem[ iItemNum ][ ITEM_TIME ] = item[ ITEM_TIME ];
    iItem[ iItemNum ][ ITEM_RESET ] = item[ ITEM_RESET ];
    iItem[ iItemNum ][ ITEM_SHOWLIMIT ] = item[ ITEM_SHOWLIMIT ];
    iItem[ iItemNum ][ ITEM_BUYTEXT ] = item[ ITEM_BUYTEXT ];

    if( item[ ITEM_EXSLOT ] && !item[ ITEM_EXCOST ] )
        iItem[ iItemNum ][ ITEM_EXSLOT ] = 0;
    else
        iItem[ iItemNum ][ ITEM_EXSLOT ] = item[ ITEM_EXSLOT ];

    iItem[ iItemNum ][ ITEM_EXCOST ] = item[ ITEM_EXCOST ];
    iItem[ iItemNum ][ ITEM_EXINC ] = item[ ITEM_EXINC ];

    iItemNum++;
}