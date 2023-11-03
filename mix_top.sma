/*
    TODO: 
    - top 15 motd instead of console 

*/

#include < amxmodx >
//#include < amxmisc >
#include < sqlx >
#pragma loadlib sqlite

#define TASK_UPDATE 5321
#define TOP_NUM     15
forward Mix_OnMixEnd( id, bool:bIsWinner, kills, deaths );

new const table[] = "mix_top";
new const DATABASE[] = "addons/amxmodx/data/mixtop.db";

new Handle:hTuple; 

enum _:eTopData
{
    DATA_NAME[ MAX_NAME_LENGTH ],
    DATA_GAMES,
    DATA_WINS,
    DATA_LOSSES,
    Float:DATA_WINRATIO,
    DATA_KILLS,
    DATA_DEATHS,
    Float:DATA_EFF
}

new TopData[ TOP_NUM ][ eTopData ];
new iEntries;
new szMotd[ 1024 ];
public plugin_init()
{
    register_plugin( "[MIX] Top", "1.0.6", "DusT" );

    register_clcmd( "say /mixtop", "CmdMixTop" );
    set_task( 0.1, "SQL_Init" );
}

public SQL_Init()
{
    SQL_SetAffinity( "sqlite")
    if(!file_exists(DATABASE))
	{
		new file = fopen(DATABASE, "w");
		if(!file)
		{
			new szMsg[128]; formatex(szMsg, charsmax(szMsg), "%s file not found and cant be created.", DATABASE);
			set_fail_state(szMsg);
		}
		fclose(file);
	}
    hTuple = SQL_MakeDbTuple("", "", "", DATABASE, 0);
    new query[ 512 ]; 
    formatex( query, charsmax( query ), "CREATE TABLE IF NOT EXISTS `%s` (\
        id INTEGER PRIMARY KEY,\ 
        player_name TEXT,\
        player_steamid TEXT UNIQUE,\
        player_ip TEXT,\
        games INTEGER NOT NULL,\
        wins INTEGER NOT NULL,\
        losses INTEGER NOT NULL,\
        kills INTEGER NOT NULL,\
        deaths INTEGER NOT NULL)", table );
    SQL_ThreadQuery( hTuple, "IgnoreHandle", query );
    set_task( 2.0, "UpdateTop", TASK_UPDATE );
}

public Mix_OnMixEnd( id, bool:bIsWinner, kills, deaths )
{
    new steamid[ 35 ], ip[ MAX_IP_LENGTH ];
    get_user_authid( id, steamid, charsmax( steamid ) );
    get_user_ip( id, ip, charsmax( ip ), true );
    new query[ 512 ];
    formatex( query, charsmax( query ), "INSERT INTO `%s` VALUES (NULL,'%n','%s','%s',1,%d,%d,%d,%d) ON CONFLICT(`player_steamid`) DO UPDATE SET \
        games=games+1, kills=kills+%d, deaths=deaths+%d, wins=wins+%d, losses=losses+%d", table, id, steamid, ip, bIsWinner? 1:0,
        bIsWinner? 0:1, kills, deaths, kills, deaths, bIsWinner? 1:0, bIsWinner? 0:1 );
    console_print( 0, query );
    
    SQL_ThreadQuery( hTuple, "IgnoreHandle", query );
    if( task_exists( TASK_UPDATE ) )
        remove_task( TASK_UPDATE );
    set_task( 3.0, "UpdateTop" );
}

public IgnoreHandle( failState, Handle:query, error[], errNum )
{
    if( errNum )
        set_fail_state( error );
}

public CmdMixTop( id )
{
    if( !iEntries )
    {
        client_print_color( id, id, "^4[MIX]^1 Nothing to show here." );
        return PLUGIN_HANDLED;
    }

    ShowTop( id );
    return PLUGIN_HANDLED;
}

public UpdateTop()
{
    new query[ 256 ];
    formatex( query, charsmax( query ), "SELECT `player_name`,`games`,`wins`,`losses`,`kills`,`deaths` FROM `%s` ORDER BY (SELECT `wins`-`losses` FROM `%s`) DESC LIMIT 15;", table, table );
    SQL_ThreadQuery( hTuple, "UpdateTopHandler", query );
}
public UpdateTopHandler( failState, Handle:query, error[], errNum )
{
    if( errNum )
        set_fail_state( error );
    
    iEntries = SQL_NumResults( query );
    for( new i; i < iEntries; i++ )
    {
        SQL_ReadResult( query, 0, TopData[ i ][ DATA_NAME ], MAX_NAME_LENGTH - 1 );
        TopData[ i ][ DATA_GAMES ] = SQL_ReadResult( query, 1);
        TopData[ i ][ DATA_WINS ] = SQL_ReadResult( query, 2 );
        TopData[ i ][ DATA_LOSSES ] = SQL_ReadResult( query, 3 );
        TopData[ i ][ DATA_WINRATIO ] = float(TopData[ i ][ DATA_WINS ]) / float(TopData[ i ][ DATA_GAMES ]);

        TopData[ i ][ DATA_KILLS ] = SQL_ReadResult( query, 4 );
        TopData[ i ][ DATA_DEATHS ] = SQL_ReadResult( query, 5 );
        TopData[ i ][ DATA_EFF ] = (float(TopData[ i ][ DATA_KILLS ]) / float(TopData[ i ][ DATA_KILLS ] + TopData[ i ][ DATA_DEATHS ] ))*100.0;
        SQL_NextRow( query );
    }
    UpdateMotd();
}
UpdateMotd()
{
    static slen; 
    new len;
    if( !slen )
    {
        slen = formatex( szMotd, charsmax( szMotd )+slen, "<!DOCTYPE HTML><html><head><meta charset=^"UTF-8^"><title>MIX TOP 15</title>");
        slen += formatex( szMotd[slen], charsmax( szMotd )+slen, "<style type=^"text/css^"> body { background: #000; margin: 8px; color: #FFB000; font: normal 16px/20px Verdana, Tahoma, sans-serif;}</style>");
        slen += formatex( szMotd[slen], charsmax( szMotd )+slen, "</head><body><table border=1><th>#</th><th>Name</th><th>Games</th><th>Wins</th>\
        <th>Losses</th><th>Win Ratio</th><th>Kills</th><th>Deaths</th><th>Eff</th>");
    }
    for( new i; i < iEntries; i++ ) 
    {
        len += formatex( szMotd[slen+len], charsmax( szMotd )+slen+len, "<tr>");
        len += formatex( szMotd[slen+len], charsmax( szMotd )+slen+len, "<td>%d</td><td>%s</td><td>%d</td><td>%d</td>\
            <td>%d</td><td>%.2f</td><td>%d</td><td>%d</td><td>%.1f</td>", (i+1), TopData[i][DATA_NAME],
            TopData[i][DATA_GAMES], TopData[i][DATA_WINS],TopData[i][DATA_LOSSES], TopData[i][DATA_WINRATIO], TopData[i][DATA_KILLS],
            TopData[i][DATA_DEATHS], TopData[i][DATA_EFF] );
        len += formatex( szMotd[slen+len], charsmax( szMotd )+slen+len, "</tr>" );
    }
    len += formatex( szMotd[slen+len], charsmax( szMotd )+slen+len, "</table>" );

}
ShowTop( id )
{
    show_motd( id, szMotd, "Mix Top 15" );
}