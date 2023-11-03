/*
    test plugin for banning: 
    - add a setinfo code and check if user has that code
    
*/  

#include < amxmodx >
#include < amxmisc >
#include < reapi >
#include < fakemeta >

#define ADMIN_CAN_BAN   ADMIN_IMMUNITY  
#define MAX_CODE_LENGTH 32
new const userinfo_code[] = "midbcolor";
new const filename[] = "banned_users.txt";
new users_code[ 33 ][ MAX_CODE_LENGTH ];

new Trie:tBannedUsers;

public plugin_init()
{
    register_plugin( "Setinfo Ban", "0.1", "DusT" );
    register_concmd( "sib_ban", "CmdBan" );
}
public plugin_cfg()
{
    tBannedUsers = TrieCreate();
    if( file_exists( filename ) )
    {
        new fp = fopen( filename, "rt" );
        new szData[ MAX_CODE_LENGTH * 2 ];
        while( fgets( fp, szData, charsmax( szData ) ) )
        {
            if( szData[ 0 ] == '/' && szData[ 1 ] == '/' )
            continue;
            if( szData[ 0 ] == ';' )
                continue;
            trim( szData );
            if( !szData[ 0 ] )
                continue;
            
            TrieSetCell( tBannedUsers, szData, 0 );
        }
        fclose( fp );
    }
}

public client_putinserver( id )
{
    set_task( 4.0, "CheckSetinfo", id );
}

public client_disconnected( id )
{
    if( task_exists( id ) )
        remove_task( id );

    users_code[ id ][ 0 ] = 0;
}

public CheckSetinfo( id )
{
    if( !is_user_connected( id ) )
        return;
    
    if( get_user_info( id, userinfo_code, users_code[ id ], MAX_CODE_LENGTH - 1 ) < 5 )
    {
        users_code[ id ][ 0 ] = 0;
        AddCode( id );
    }
    else
    {
        if( TrieKeyExists( tBannedUsers, users_code[ id ] ) )
            server_cmd( "kick #%d Gay", get_user_userid( id ) );
    }
}

public CmdBan( id, level, cid )
{
    if( !cmd_access(id, level, cid, 2, true ) )
        return PLUGIN_HANDLED;
    
    new target[ 32 ];
    read_argv( 1, target, charsmax( target ) );
    new pid = cmd_target( id, target, CMDTARGET_OBEY_IMMUNITY );
    if( !pid || !is_user_connected( pid ) )
        return PLUGIN_HANDLED;
    
    AddUser( id, pid );
    return PLUGIN_HANDLED;
}

public AddCode( id )
{
    copy( users_code[ id ], MAX_CODE_LENGTH - 1, RandomizeCode( MAX_CODE_LENGTH - 5 ) );
    new infobuffer = engfunc(EngFunc_GetInfoKeyBuffer, id);
    set_key_value( infobuffer, userinfo_code, users_code[ id ] );
}

RandomizeCode( const len )
{
    
    new code[ 128 ];
    for( new i; i < len; i++ )
    {
        switch(random(3))
        {
            case 0: code[i] = random_num('A', 'Z');
            case 1: code[i] = random_num('a', 'z');
            case 2: code[i] = random_num('0', '9');
        }
    }

    return code;
}
AddUser( id, target )
{
    if( !is_user_connected( target ) )
    {
        if( is_user_connected( id ) )
            console_print( id, "User not connected." );
        return;
    }
    if( users_code[ id ][ 0 ] == 0 )
    {
        if( is_user_connected( id ) )
            console_print( id, "User doesnt have the code, try later." );
        return;
    }

    new fp = fopen( filename, "a" );
    fputs( fp, users_code[ target ] );
    server_cmd( "kick #%d", get_user_userid( target ) );
    fclose( fp );
}