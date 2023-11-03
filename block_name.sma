/*
    Nick manager: 
    - automatically change name if is in blacklist
    - name is changed as set in amx_base_name, where every "?" will be converted to a number
    - has whitelist / whitelist_steamid
    - command amx_name to change 
*/

#include < amxmodx >
#include < amxmisc >
#include < reapi >
#include < regex >
#include < sqlx >

native is_user_registered( id );
native pt_set_full_stop( id, bool:stop = true );

new const szPrefix[] = "^4[AMXNAME]^1"

new pName[ MAX_NAME_LENGTH ];
new Array:szBlockedNames; new iBlockedNum;
new Array:szWhiteList; new iWhiteNum;
new bool:bCanChange[ MAX_PLAYERS + 1 ];
new Handle:tuple;
new Trie:szWhiteListSteamIDs;

new HookChain:g_hSV_WriteFullClientUpdate;
new iHideNum;
new szSavedNames[ MAX_PLAYERS + 1 ][ MAX_NAME_LENGTH ];
public plugin_init()
{
    register_plugin( "Nick Manager", "1.0.5", "DusT" );

    RegisterHookChain( RG_CBasePlayer_SetClientUserInfoName, "OnChangeName" );
    bind_pcvar_string( create_cvar( "amx_base_name", "[AMX] Player [???]" ), pName, charsmax( pName ) );
    register_concmd( "amx_name", "CmdChangeName", ADMIN_LEVEL_G, "< user > - force user to default nick" );
    szBlockedNames = ArrayCreate( 128, 1 );
    szWhiteList = ArrayCreate( 128, 1 );
    szWhiteListSteamIDs = TrieCreate();
    DisableHookChain((g_hSV_WriteFullClientUpdate = RegisterHookChain(RH_SV_WriteFullClientUpdate, "SV_WriteFullClientUpdate")));
}

public plugin_cfg()
{
    tuple = SQL_MakeDbTuple( "127.0.0.1", "dust", "", "amx_knf" );
    set_task( 0.1, "SQL_Init" );
}
public SQL_Init()
{
    new query[ 512 ];
    copy( query, charsmax( query ), "CREATE TABLE IF NOT EXISTS `blocked_named` (\
        `id` INT NOT NULL AUTO_INCREMENT,\
        `type` INT NOT NULL,\
        `pattern` VARCHAR(128) NOT NULL,\
        PRIMARY KEY(id));" );
    SQL_ThreadQuery( tuple, "IgnoreHandle", query );
    SQL_ThreadQuery( tuple, "SQL_ReadData", "SELECT * FROM blocked_named;" );

}

public IgnoreHandle( failState, Handle:q, error[], errNum )
{
    if( errNum )
        set_fail_state( error );
}
public SQL_ReadData( failState, Handle:query, error[], errNum )
{
    if( errNum )
        set_fail_state( error );
    enum { BLOCKED = 0, WHITELIST, WHITELIST_STEAMID }
    new max = SQL_NumResults( query );
    new pattern[ 128 ];
    for( new i; i < max; i++ )
    {
        SQL_ReadResult( query, 2, pattern, charsmax( pattern ) );
        switch( SQL_ReadResult( query, 1 ) )
        {
            case BLOCKED: ArrayPushString( szBlockedNames, pattern );
            case WHITELIST: ArrayPushString( szWhiteList, pattern );
            case WHITELIST_STEAMID: { strtolower( pattern ); TrieSetCell( szWhiteListSteamIDs, pattern, 0 ); }
        }
        SQL_NextRow( query );
    }
    iWhiteNum = ArraySize( szWhiteList );
    iBlockedNum = ArraySize( szBlockedNames );
}

public client_putinserver( id )
{
    if( !is_user_bot( id ) )
        set_task( 1.0, "CheckName", id );
}

public CheckName( id )
{
    if( is_user_registered( id ) )
        return;

    new name[ MAX_NAME_LENGTH ];    // recycling name for checking first steamid and then name
    get_user_authid( id, name, charsmax( name ) );

    strtolower( name );

    if( TrieKeyExists( szWhiteListSteamIDs, name ) )
        return;

    new Regex:rPattern;
    get_user_name( id, name, charsmax( name ) );

    for( new i; i < iWhiteNum; i++ )
    {
        if( _:( rPattern = regex_match( name, fmt( "%a", ArrayGetStringHandle( szWhiteList, i ) ), _, _, _, "i" ) ) > 0 )
        {
            regex_free( rPattern );
            return; 
        }
    }
    
    for( new i; i < iBlockedNum; i++ )
    {
        if( _:( rPattern = regex_match( name, fmt( "%a", ArrayGetStringHandle( szBlockedNames, i ) ), _, _, _, "i") ) > 0 )
        {
            regex_free( rPattern );
            ChangeName( id );
            return;
        }
    }
    
}

public CmdChangeName( id, level, cid )
{
    if( !cmd_access( id, level, cid, 2, true ) )
        return PLUGIN_HANDLED;
    
    new szPlayer[ MAX_NAME_LENGTH ];
    read_argv( 1, szPlayer, charsmax( szPlayer ) );
    new player = cmd_target( id, szPlayer, CMDTARGET_NO_BOTS );
    if( !player )
        return PLUGIN_HANDLED;

    ChangeName( player );
    console_print( id, "Nick changed successfully" );
    return PLUGIN_HANDLED;
}

ChangeName( id )
{
    //new szNewName[ MAX_NAME_LENGTH ];
    copy( szSavedNames[ id ], charsmax( szSavedNames[] ), pName );
    while( replace_stringex( szSavedNames[ id ], charsmax( szSavedNames[] ), "?", fmt( "%d", random_num( 1,9 ) ) ) != -1 ) {}
    
    bCanChange[ id ] = true; 
    pt_set_full_stop( id, true );
    set_user_info( id, "name", szSavedNames[ id ] );
    //client_cmd( id, "name %s", szNewName );
    iHideNum++;
    CheckHook()
    rh_update_user_info( id );
}

public client_disconnected( id )
{
    if( task_exists( id ) )
        remove_task( id );
    if( bCanChange[ id ] )
        bCanChange[ id ] = false;
}

public OnChangeName( const id, szBuffer[], const szNewName[] )
{
    static msgTextMsg;
    static msgSayText;
    if( msgTextMsg || (msgTextMsg = get_user_msgid("TextMsg") ) ) {}
    if( msgSayText || (msgSayText = get_user_msgid("SayText") ) ) {}

    if( bCanChange[ id ] )
    {
        if( get_entvar( id, var_deadflag ) == DEAD_NO )
        {
            if( equal( szNewName, szSavedNames[ id ] ) )
            {
                client_print_color( id, print_team_red, "%s Your name was changed because it violates our policy.", szPrefix );
                bCanChange[ id ] = false;
                iHideNum--;
                CheckHook();
            }
            else
            {
                //client_print( id, print_chat, "asdsadasddasdasdas" );
                set_user_info( id, "name", szSavedNames[ id ] );
                rh_update_user_info( id );
                SetHookChainReturn( ATYPE_BOOL, 0 );
                return HC_SUPERCEDE;
            }
            
            //rh_update_user_info( id );
        }
        set_msg_block(get_entvar(id, var_deadflag) != DEAD_NO ? msgTextMsg : msgSayText, BLOCK_ONCE)    
        return HC_CONTINUE;
    }
    client_print_color( id, print_team_red, "%s You cannot change name in-game.", szPrefix );
    SetHookChainReturn( ATYPE_BOOL, 0 );
    return HC_SUPERCEDE;
}
CheckHook()
{
    if( iHideNum )
        EnableHookChain( g_hSV_WriteFullClientUpdate );
    else
        DisableHookChain( g_hSV_WriteFullClientUpdate );
}
public SV_WriteFullClientUpdate(const id, buffer, const receiver)
{
	if (bCanChange[id])
	{
		set_key_value(buffer, "", "");
		//set_key_value(buffer, "name",  "");
		//set_key_value(buffer, "model", "");
		//set_key_value(buffer, "*sid",  "");
	}
}

public plugin_end()
{
    TrieDestroy( szWhiteListSteamIDs );
    ArrayDestroy( szBlockedNames );
    ArrayDestroy( szWhiteList );
    SQL_FreeHandle( tuple );
}