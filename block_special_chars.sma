/*
    block special chars in name
*/
#include <amxmodx>

public plugin_init()
{
    register_plugin( "Anti Special Nicks", "1.0", "blank" );
    
}

public client_putinserver( id )
{
    new szName[ 32 ];
    get_user_name( id, szName, charsmax( szName ) );

    if( !is_string_category( szName, charsmax( szName ), UTF8C_ALL ))
        server_print( "NOT OK" );
    else
        server_print( "OK" );

    for( new i = 0; i < strlen( szName ); i++ )
    {
        server_print( "%d", szName[ i ] );
        if( szName[ i ] < 32 || szName[ i ] > 126 )
            server_cmd("kick #%d Don't use special chars in your name!", get_user_userid( id ) );
    }
}