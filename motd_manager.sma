#include < amxmodx >

new Trie:tInfoMotds;

public plugin_init()
{
    register_plugin( "MOTD Manager", "1.0", "DusT" );

    register_clcmd( "say", "CmdSay" );
    tInfoMotds = TrieCreate();
    ReadINI();
}

ReadINI()
{
    new szDir[ 128 ];

    get_localinfo("amxx_configsdir", szDir, charsmax( szDir ) );
    add( szDir, charsmax( szDir ), "/motd_manager.ini" );
    if( !file_exists( szDir ) )
    {
        return;
    }
    //g_iItems = 0;
    new fp = fopen( szDir, "rt" );
    new szData[ 100 ], szToken[ 32 ], szValue[ 32 ];
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

        TrieSetString( tInfoMotds, szToken, szValue );
    }
    fclose( fp );
}


public CmdSay( id )
{
    new message[ 128 ];
    read_args( message, charsmax( message ) );
    remove_quotes( message ); trim( message );
    new file_motd[ 64 ];
    if( TrieGetString( tInfoMotds, message, file_motd, charsmax( file_motd ) ) )
    {
        show_motd( id, file_motd, "MOTD" );
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}