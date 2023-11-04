#include < amxmodx >
#include < zp50_class_human >
#include < zp50_colorchat_const >
#include < zp50_ammopacks >
#include < sqlx >

#define MAX_CLASSES 50
new const INI_FILE[] = "zp50_human_premium.ini";

new const host[] = "";
new const user[] = "";
new const pass[] = "";
new const db[]   = "";

new const table[] = "";

new Handle:hTuple;

enum _:eClassData
{
    CLASS_NAME[ MAX_NAME_LENGTH ],
    CLASS_COST,
    CLASS_ID
}
new iClass[ MAX_CLASSES ][ eClassData ];
new iClassNum;

new bool:bHasClass[ MAX_PLAYERS ][ MAX_CLASSES ];
public plugin_init()
{
    register_plugin( "[ZP] Human Premium Skins", "1.0", "DusT" );

    register_clcmd( "say !skins", "CmdSaySkins" );
    register_clcmd( "say /skins", "CmdSaySkins" );

    iClassNum = -1;
    hTuple = SQL_MakeDbTuple( host, user, pass, db );
}
public plugin_cfg()
{
    INI_Read();
    SQL_Init();
}

public client_putinserver( id )
{
    set_task( 1.0, "SQL_CheckPlayer", id );
}

public client_disconnected( id )
{
    if( task_exists( id ) )
        remove_task( id );
    
    arrayset( bHasClass[ id ], false, iClassNum );
}

public CmdSaySkins( id )
{
    new menu = menu_create( "Skins Menu", "SkinsMenuHandler" );
    new const DISABLED = (1<<27);
    new const ADDITION[] = "\w[\yOWNED\w]";
    new ammo = zp_ammopacks_get( id );
    for( new i, item[ 64 ]; i < iClassNum; i++ )
    {
        if( bHasClass[ id ][ i ] )
        {
            formatex( item, charsmax( item ), "%s %s", iClass[ i ][ CLASS_NAME ], ADDITION );
            menu_additem( menu, item, _, DISABLED );
        }
        else
        {
            formatex( item, charsmax( item ), "%-22.22s\t [\%s%6d]", iClass[ i ][ CLASS_NAME ], ammo>iClass[ i ][CLASS_COST]? "y":"r", iClass[ i ][CLASS_COST] );
            menu_additem( menu, item, _, ammo > iClass[ i ][ CLASS_COST ]? 0:DISABLED );
        }
    }
    menu_display( id, menu );
    return PLUGIN_HANDLED;
}

public SkinsMenuHandler( id, menu, item )
{
    if( item > MENU_EXIT )
    {
        AreYouSureMenu( id, item );
    }
    menu_destroy( menu );
    return PLUGIN_HANDLED;
}
AreYouSureMenu( id, item )
{
    if( !is_user_connected( id ) )
        return;
    
    if( bHasClass[ id ][ item ] )
        return;
    
    if( zp_ammopacks_get( id ) < iClass[ item ][ CLASS_COST ] )
    {
        client_print_color( id, print_team_red, "%s%l", ZP_PREFIX, "ZP_NOT_ENOUGH_AMMO" );
        return;
    }
    new title[ 128 ];
    formatex( title, charsmax( title ), "Are you sure?^n\
        \ySkin: \w%s^n\
        \yCost: \w%dAP", iClass[ item ][ CLASS_NAME ], iClass[ item ][ CLASS_COST ] );
    new menu = menu_create( title, "AreYouSureHandler" );
    new param[ 5 ];
    param[ 0 ] = item;
    menu_additem( menu, "\yYes", param );
    menu_additem( menu, "\rNo" );

    menu_display( id, menu );
}

public AreYouSureHandler( id, menu, item )
{
    if( item == 0 )
    {
        new param[ 5 ];
        menu_item_getinfo( menu, item, _, param, charsmax( param ) );
        
        RegisterClass( id, str_to_num( param ) );
    }
    menu_destroy( menu );
    return PLUGIN_HANDLED;
}
RegisterClass( id, class )
{
    if( !is_user_connected( id ) )
        return;

    new ammo = zp_ammopacks_get( id );
    if( ammo < iClass[ class ][ CLASS_COST ] )
    {
        client_print_color( id, print_team_red, "%s%l", ZP_PREFIX, "ZP_NOT_ENOUGH_AMMO" );
        return;
    }

    zp_ammopacks_set( id, ammo - iClass[ class ][ CLASS_COST ] );
    bHasClass[ id ][ class ] = true;

    SQL_AddClass( id, class );
    client_print_color( id, print_team_red, "%s%l", ZP_PREFIX, "ZP_BOUGHT_SKIN", iClass[ class ][ CLASS_NAME ] );
}
SQL_AddClass( id, class )
{
    new query[ 256 ];
    new escName[ MAX_NAME_LENGTH * 2 ], escClassName[ MAX_NAME_LENGTH * 2 ];
    SQL_QuoteStringFmt( Empty_Handle, escName, charsmax( escName ), "%n", id );
    SQL_QuoteString( Empty_Handle, escClassName, charsmax( escClassName ), iClass[ class ][ CLASS_NAME ] );

    formatex( query, charsmax( query ), "INSERT IGNORE INTO `%s` VALUES(\
        NULL,'%s','%s',%d,%d);", table, escName, escClassName, get_systime(), iClass[ class ][ CLASS_COST ] );
    SQL_ThreadQuery( hTuple, "IgnoreHandle", query );
}
public SQL_CheckPlayer( id )
{
    new escName[ MAX_NAME_LENGTH * 2 ];
    SQL_QuoteStringFmt( Empty_Handle, escName, charsmax( escName ), "%n", id );

    new data[ 2 ];
    data[ 0 ] = id;
    SQL_ThreadQuery( hTuple, "CheckPlayerHandler",fmt( "SELECT `skin_name` FROM `%s` WHERE `player_nick`='%s';", table, escName ), data, sizeof data );
}
public CheckPlayerHandler( failState, Handle:query, error[], errNum, data[], dataSize )
{
    new id = data[ 0 ];
    if( !is_user_connected( id ) )
        return;
   
    if( !SQL_NumResults( query ) )
        return;
    new className[ MAX_NAME_LENGTH ];
    while( SQL_MoreResults( query ) )
    {
        SQL_ReadResult( query, 0, className, charsmax( className ) );
        for( new i; i < iClassNum; i++ )
        {
            if( equali( className, iClass[ i ][ CLASS_NAME ] ) )
                bHasClass[ id ][ i ] = true;
        }
        SQL_NextRow( query );
    }
}

public zp_fw_class_human_select_pre( id, classid )
{
    static const text[ 32 ] = "\w[\ySKIN\w]";

    for( new i; i < iClassNum; i++ )
    {
        if( classid == iClass[ i ][ CLASS_ID ] )
        {
            if( bHasClass[ id ][ i ] )
                return ZP_CLASS_DONT_SHOW;
            
            zp_class_human_menu_text_add( text );
            return ZP_CLASS_AVAILABLE;
        }
    }
    return ZP_CLASS_AVAILABLE;
}
SQL_Init()
{
    new query[ 256 ];
    formatex( query, charsmax( query ), "CREATE TABLE IF NOT EXISTS `%s`(\
        id INT NOT NULL AUTO_INCREMENT,\
        player_nick VARCHAR(32) NOT NULL,\
        skin_name VARCHAR(32) NOT NULL,\
        time_bought INT,\
        cost_bought INT,\
        PRIMARY KEY (id), UNIQUE(`player_nick`,`skin_name`));", table );

    SQL_ThreadQuery( hTuple, "IgnoreHandle", query );
}
public IgnoreHandle( failState, Handle:query, error[], errNum )
{
    if( errNum )
        set_fail_state( error );
}

INI_Read()
{
    new szDir[ 128 ];

    get_localinfo("amxx_configsdir", szDir, charsmax( szDir ) );
    format( szDir, charsmax( szDir ), "%s/%s", szDir, INI_FILE );
    if( !file_exists( szDir ) )
    {
        return;
    }
    iClassNum = 0;
    new fp = fopen( szDir, "rt" );
    new szData[ 100 ], szToken[ 35 ], szValue[ 15 ];
    while( fgets( fp, szData, charsmax( szData ) ) )
    {
        if( szData[ 0 ] == '/' && szData[ 1 ] == '/' )
            continue;
        if( szData[ 0 ] == ';' )
            continue;
        trim( szData );
        if( !szData[ 0 ] )
            continue;

        strtok2( szData, szToken, charsmax( szToken ), szValue, charsmax( szValue ), '=', TRIM_FULL );
        remove_quotes( szToken );
        remove_quotes( szValue );

        new classid = zp_class_human_get_id( szToken );
        if( classid == ZP_INVALID_HUMAN_CLASS )
        {
            log_amx( "class %s is not implemented", szToken );
        }
        else if( !is_str_num( szValue ) || str_to_num( szValue ) <= 0 )
        {
            log_amx( "class %s does not have a vald cost (%s)", szToken, szValue );
        }
        else
        {
            iClass[ iClassNum ][ CLASS_ID ] = classid;
            iClass[ iClassNum ][ CLASS_COST ] = str_to_num( szValue );
            copy( iClass[ iClassNum ][ CLASS_NAME ], MAX_NAME_LENGTH - 1, szToken );
            iClassNum++;
        }
        if( iClassNum >= MAX_CLASSES )
        {
            log_amx( "Could not load more than %d human skins", MAX_CLASSES );
            break;
        }
    }
    fclose( fp );
}