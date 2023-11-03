/*
    Chat Manager handlerr

    - clarionchat logs
    - say_team + @
*/

#include < amxmodx >
#include < amxmisc >
#include < reapi >


enum _:eLogs
{
    LOG_CHAT = 0,
    LOG_AMXCHAT,
    LOG_AMXPCHAT,
    LOG_PSAY
}
new Array:hPrefix;
new Array:hFlags;
new Trie:hSteamPrefix;

new g_iItems = -1;
new g_szPrefix[ MAX_PLAYERS + 1 ][ 64 ];

new pShowDeadPrefix, pShowPrefix, pShowGreen, pGreenFlag, pShowTeamPrefix;
new pShowDeadChat, pShowTeamChat;
new pChatFlag;
new g_iChatFlag;

new pChatLog, pAmxChatLog, pPsayLog;
new pDelete;
public plugin_init()
{
    register_plugin( "ChatManager", "1.1.5", "DusT" );

    register_clcmd( "say", "CmdSay" );
    register_clcmd( "say_team", "CmdSay" );

    register_concmd( "amx_psay", "CmdPsay", ADMIN_ALL, "< name | steamid | #userid > < message > - Send user a private message." );
    //register_clcmd( "amx_pm", "CmdPsay", ADMIN_ALL, "< name | steamid | #userid > < message > - Send user a private message." );
    
    new index = register_concmd( "amx_chat", "CmdAdminChat", ADMIN_CHAT, "< message > - Send a message to admins." );
    register_concmd( "amx_say", "CmdAdminSay", ADMIN_CHAT, "< message > - Send a message to all players." );
    //register_clcmd( "amx_announce", "CmdAdminSay", ADMIN_CHAT, "< message > - Send a message to all players." );
    register_clcmd( "amx_pchat", "CmdAdminPlayerChat", ADMIN_ALL, "< message > - Send a message to admins." );

    register_concmd( "amx_reloadadmins", "CmdReloadAdmins", ADMIN_CFG );
    
    hook_cvar_change( create_cvar( "chat_amxchat_flag", "d", _, "Who can read amx_chat" ), "@OnChatChange")

    bind_pcvar_num( create_cvar( "chat_show_dead_prefix", "1", _, "Show dead prefix if player is dead", true, 0.0, true, 1.0 ), pShowDeadPrefix );
    bind_pcvar_num( create_cvar( "chat_show_team_prefix", "1", _, "Show team prefix if player using say_team", true, 0.0, true, 1.0 ), pShowTeamPrefix );
    bind_pcvar_num( create_cvar( "chat_show_prefix", "1", _, "Show Custom Prefix", true, 0.0, true, 1.0 ), pShowPrefix );
    bind_pcvar_num( create_cvar( "chat_show_green", "0", _, "Show green text for people with certain flags", true, 0.0, true, 1.0 ), pShowGreen );
    
    bind_pcvar_num( create_cvar( "chat_show_dead", "1", _, "Alive players can read dead chat", true, 0.0, true, 1.0), pShowDeadChat );
    bind_pcvar_num( create_cvar( "chat_show_team", "0", _, "Show everyone the team chat(1) or just to corresponding teams(0)", true, 0.0, true, 1.0 ), pShowTeamChat );
    hook_cvar_change( create_cvar( "chat_green_flag", "b", _, "Which flag player needs to show green chat.\nWorks with chat_show_green cvar" ), "@OnGreenChange" );
    
    bind_pcvar_num( create_cvar( "chat_log", "0", _, "Log chat messages", true, 0.0, true, 1.0 ), pChatLog );
    bind_pcvar_num( create_cvar( "chat_amxchat_log", "0", _, "Log amx_chat/amx_pchat messages", true, 0.0, true, 1.0 ), pAmxChatLog );
    bind_pcvar_num( create_cvar( "chat_psay_log", "0", _, "Log amx_psay messages", true, 0.0, true, 1.0 ), pPsayLog );
    bind_pcvar_num( create_cvar( "chat_delete_logs", "7", _, "Delete logs older than this days.", true, 0.0 ), pDelete );
    AutoExecConfig( true, "ChatManager" );

    new dummy[1];
    get_concmd( index, dummy, 0, g_iChatFlag, dummy, 0, -1 );
}

public plugin_cfg()
{
    set_task(0.5, "OnConfigsExecuted" );
}
@OnGreenChange( pcvar, const old_value[], const new_value[] )
{
    pGreenFlag = read_flags( new_value );
}
@OnChatChange( pcvar, const old_value[], const new_value[] )
{
    pChatFlag = read_flags( new_value );
}
public OnConfigsExecuted()
{
    hPrefix = ArrayCreate( 30, 1 );
    hFlags = ArrayCreate( 1, 1 );
    hSteamPrefix = TrieCreate();
    ReadINI();

    new flags[5];

    get_cvar_string( "chat_green_flag", flags, charsmax( flags ) );
    pGreenFlag = read_flags( flags );

    get_cvar_string( "chat_amxchat_flag", flags, charsmax( flags ) );
    pChatFlag = read_flags( flags );

    if( pDelete )
    {
        new szDataFolder[ 256 ];
        get_localinfo("amx_logdir", szDataFolder, charsmax( szDataFolder ) );
        add( szDataFolder, charsmax( szDataFolder ), "/ChatManager" );

        if( !dir_exists( szDataFolder ) )
            return;
        
        new file[ 64 ], tempDir[ 256 ];
        new dp = open_dir( szDataFolder, file, charsmax( file ) );
        if( !dp )   return;
        new time = get_systime() - pDelete * 60 * 60 * 24;
        do
        {
            if( file[ 0 ] != '.' )
            {
                formatex( tempDir, charsmax( tempDir ), "%s/%s", szDataFolder, file );
                if( GetFileTime( tempDir, FileTime_LastChange ) <= time )
                    delete_file( tempDir );
            }
        }while( next_file( dp, file, charsmax( file ) ) )
        close_dir( dp );
    }
    
}

public CmdAdminPlayerChat( id, level, cid )
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED

    new message[192]

    read_args(message, charsmax(message))
    remove_quotes(message)

    if (!message[0])
        return PLUGIN_HANDLED

    new players[MAX_PLAYERS], inum, pl

    get_players(players, inum, "ch")

    format(message, charsmax(message), "^4[ADMINS] ^1(PLAYER) %n :   ^3%s", id, message)
    console_print(id, "%s", message)

    for (new i = 0; i < inum; ++i)
    {
        pl = players[i]
        if (access(pl, pChatFlag))
            client_print_color(pl, print_team_red, "%s", message)
    }
    if( pAmxChatLog )
        LogMessage( id, message, LOG_AMXPCHAT );
    return PLUGIN_HANDLED;
}



public CmdPsay( id, level, cid )
{
    if( !cmd_access( id, level, cid, 3 ) )
        return PLUGIN_HANDLED;

    new name[MAX_NAME_LENGTH];
    read_argv(1, name, charsmax(name));
    new priv = cmd_target(id, name, CMDTARGET_ALLOW_SELF );

    if (!priv)
        return PLUGIN_HANDLED

    new length = strlen(name) + 1

    new message[192];

    read_args(message, charsmax(message))

    if (message[0] == '"' && message[length] == '"') // HLSW fix
    {
        message[0] = ' '
        message[length] = ' '
        length += 2
    }

    remove_quotes(message[length])

    if (id && id != priv)
        client_print_color( id, print_team_red, "^4[PM]^1 to ^4%n^1 :   ^3%s", priv, message[ length ] );

    client_print_color( priv, print_team_red, "^4[PM]^1 ^4%n^1 :   ^3%s", id, message[ length ] );
    console_print(id, "[PM] to %n from %n :   %s", priv, id, message[length])

    if( pPsayLog )
        LogMessage( id, message[ length ], LOG_PSAY, priv );
    return PLUGIN_HANDLED;
}
// most of the code from default adminchat
public CmdAdminChat( id, level, cid )
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED

    new message[192]

    read_args(message, charsmax(message))
    remove_quotes(message)

    if (!message[0])
        return PLUGIN_HANDLED

    new players[MAX_PLAYERS], inum, pl

    get_players(players, inum, "ch")

    format(message, charsmax(message), "^4[ADMINS] %n^1 :   ^3%s", id, message)
    console_print(id, "%s", message)

    for (new i = 0; i < inum; ++i)
    {
        pl = players[i]
        if (access(pl, pChatFlag))
            client_print_color(pl, print_team_red, "%s", message)
    }
    if( pAmxChatLog )
    {
        LogMessage( id, message, LOG_AMXCHAT )
    }
    return PLUGIN_HANDLED
}

// most of the code from default adminchat
public CmdAdminSay( id, level, cid )
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED

    new message[192], name[ MAX_NAME_LENGTH ];

    get_user_name( id, name, charsmax( name ) );
    read_args(message, charsmax(message))
    remove_quotes(message)

    strtoupper( name );
    format( message, charsmax( message ), "^4%s^1 :   ^3%s", name, message );

    client_print_color( 0, print_team_red, message );
    console_print(id, message );
    if( pChatLog )
        LogMessage( id, message, LOG_CHAT );
    return PLUGIN_HANDLED
}

public CmdSay( id )
{
    new argv[ 10 ];
    new bool:is_say_team;

    read_argv( 0, argv, charsmax( argv ) );
    
    if( equali( argv, "say_team" ) )
        is_say_team = true;
    
    new args[ 192 ];

    read_args( args, charsmax( args ) );
    remove_quotes( args );

    if( !args [ 0 ] )
        return PLUGIN_HANDLED;

    if( args[ 0 ] == '@' )
    {
        /* amx_pchat */
        if( is_say_team )
        {
            if( get_user_flags( id ) & g_iChatFlag )
                amxclient_cmd( id, "amx_chat", args[ 1 ] );
            else
                amxclient_cmd( id, "amx_pchat", args[ 1 ] );
        }
        else //amx_say
            //rg_inter
            amxclient_cmd( id, "amx_say", args[ 1 ] );
        
        return PLUGIN_HANDLED;
    }
    else if( args[ 0 ] == '$' )
    {
        new user[ 32 ];
        new message[ 192 ];
        copy( args, charsmax( args ), args[ 1 ] );

        argbreak( args, user, charsmax( user ), message, charsmax( message ) );
        // parse( args, user, charsmax( user ),  );

        amxclient_cmd( id, "amx_psay", user, message );
        return PLUGIN_HANDLED;
    }
    else if( args[ 0 ] == '#' )
    {
        // amx_chat
        amxclient_cmd( id, "amx_chat", args[ 1 ] );
        return PLUGIN_HANDLED;
    }
    else if( args[ 0 ] == '/' || args[ 0 ] == '!' )
        return PLUGIN_HANDLED_MAIN;
        
    DisplayMessage( id, args, is_say_team );
    return PLUGIN_HANDLED_MAIN;
}

DisplayMessage( id, message[],  bool:is_say_team = false )
{
    if( !is_user_connected( id ) )
        return;
    new szMessage[ 196 ];
    new TeamName:iTeam = get_member( id, m_iTeam );

    static szDeadPrefix[] = "*DEAD* ";
    if( pShowDeadPrefix && !is_user_alive( id ) )
        add( szMessage, charsmax( szMessage ), szDeadPrefix );

    
    static szTeam[][] = { "", "Terrorist", "Counter-Terrorist", "Spectator" };

    if( pShowTeamPrefix && is_say_team )
        add( szMessage, charsmax( szMessage ), fmt( "(%s) ", szTeam[ _:iTeam ] ) );

    if( pShowPrefix && g_szPrefix[ id ][ 0 ]){
        add( szMessage, charsmax( szMessage ), fmt( "%s^1 ", g_szPrefix[ id ] ) );
    }

    if( !szMessage[ 0 ] )
        szMessage[ 0 ] = ' ';
    if( pShowGreen )
        format( szMessage, charsmax( szMessage ), "%s^3%n^1 :  %s%s", szMessage, id, ( get_user_flags( id ) & pGreenFlag )? "^4":"", message );
    else
        format( szMessage, charsmax( szMessage ), "%s^3%n^1 :  %s", szMessage, id, message );

    new players[ 32 ], num;

    if( pShowDeadChat )
    {
        if( !pShowTeamChat && is_say_team )
            get_players( players, num );
        else
        {
            players[ 0 ] = 0; 
            num = 1;
        }
    }  
    else
    {
        if( is_user_alive( id ) )
            get_players( players, num );
        else
            get_players( players, num, "b" );
    }
    
    for( new i, player; i < num; i++ )
    {
        player = players[ i ];
        if( pShowTeamChat || !is_say_team || iTeam == get_member( player, m_iTeam ) )
        {
            client_print_color( player, id, szMessage );
        }
    }

    if( pChatLog )
        LogMessage( id, szMessage, LOG_CHAT );
}

public CmdReloadAdmins( id, level )
{
    if( !id || ( get_user_flags( id ) & level ) )
    {
        new players[ 32 ], num; 
        get_players( players, num );
        for( new i; i < num; i++ )
        {
            UpdatePrefix( id );
        }
    }
    return PLUGIN_CONTINUE;
}

public UpdatePrefix( id )
{
    if( g_iItems > 0 )
    {
        new flags = get_user_flags( id );
        g_szPrefix[ id ][ 0 ] = 0;

        new authid[ 32 ];
        get_user_authid( id, authid, charsmax( authid ) );
        if( !TrieGetString( hSteamPrefix, authid, g_szPrefix[ id ], charsmax( g_szPrefix[] ) ) )
        {
            for( new i; i < g_iItems; i++ )
            {
                if( flags == ArrayGetCell( hFlags, i ) )
                    ArrayGetString( hPrefix, i, g_szPrefix[ id ], charsmax( g_szPrefix[] ) );
            }
        }
        
        if( g_szPrefix[ id ][ 0 ] )
        {
            replace_all( g_szPrefix[ id ], charsmax( g_szPrefix[] ), "!g", "^4" );
            replace_all( g_szPrefix[ id ], charsmax( g_szPrefix[] ), "!t", "^3" );
            replace_all( g_szPrefix[ id ], charsmax( g_szPrefix[] ), "!y", "^1" );
        }
    }
    else if( g_iItems == 0 ) // if readini hasn't finished, retry in 1 second
        set_task( 1.0, "UpdatePrefix", id );
}

public client_putinserver( id )
{
    set_task( 1.0, "UpdatePrefix", id );
}

public client_disconnected( id )
{
    if( task_exists( id ) )
        remove_task( id );
}
public ReadINI()
{
    new szDir[ 128 ];

    get_localinfo("amxx_configsdir", szDir, charsmax( szDir ) );
    add( szDir, charsmax( szDir ), "/CM_Prefix.ini" );

    if( !file_exists( szDir ) )
    {
        return;
    }
    g_iItems = 0;
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

        strtok2( szData, szToken, charsmax( szToken ), szValue, charsmax( szValue ), '=' );
        trim( szValue );
        trim( szToken );

        if( equali( szToken, "STEAM_", 6 ) )
        {
            TrieSetString( hSteamPrefix, szToken, szValue );
        }
        else
        {
            ArrayPushCell( hFlags, read_flags( szToken ) );
            ArrayPushString( hPrefix, szValue );
        }
        
    }
    fclose( fp );
    g_iItems = ArraySize( hFlags );
}

LogMessage( id, message[], LogType, player = 0 )
{
    static szDataFolder[256];

    if( !szDataFolder[ 0 ] )
    {
        get_localinfo("amx_logdir", szDataFolder, charsmax( szDataFolder ) );
        add( szDataFolder, charsmax( szDataFolder ), "/ChatManager" );

        if( !dir_exists( szDataFolder ) )
            mkdir( szDataFolder );
    }
    static szDate[ 32 ];
    if( !szDate[ 0 ] )
    {
        format_time( szDate, charsmax( szDate ), "%Y_%m_%d" );
    }
    new szTime[ 32 ];
    format_time( szTime, charsmax( szTime ), "%H:%M:%S" );

    new szMessage[ 192 ];
    if( LogType != LOG_PSAY )
        formatex( szMessage, charsmax( szMessage ), "[ %s ] User: %N | Message: %s^n", szTime, id, message )
    else
        formatex( szMessage, charsmax( szMessage ), "[ %s ] User: %N | Receiver: %N | Message: %s^n", szTime, id, player, message );
    
    replace_string( szMessage, charsmax( szMessage ), "^4", "" );
    replace_string( szMessage, charsmax( szMessage ), "^3", "" );
    replace_string( szMessage, charsmax( szMessage ), "^1", "" );

    new file[ 255 ];
    switch( LogType )
    {
        case LOG_CHAT:
            formatex( file, charsmax( file ), "%s/%s_chat.log", szDataFolder, szDate );
        case LOG_AMXCHAT, LOG_AMXPCHAT: 
            formatex( file, charsmax( file ), "%s/%s_amx_chat.log", szDataFolder, szDate );
        case LOG_PSAY:
            formatex( file, charsmax( file ), "%s/%s_amx_psay.log", szDataFolder, szDate );
    }

    if( LogType == LOG_AMXPCHAT )
        format( szMessage, charsmax( szMessage ), "(PCHAT)%s", szMessage );
    
    new fp = fopen( file, "a" );
    if( !fp )
        return;
    fputs( fp, szMessage );
    fclose(fp);
}

