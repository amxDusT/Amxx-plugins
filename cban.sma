/*
    OLD version of my Ban System. 
    (last version I deleted by mistake)

    

    changelog:
        - added ini reader.
        - added cfg reader.
        - moved cvars to ini
        - no cookie word showing up
        - added a system to update player bans in case they avoid 
        - added ban command
        - added checking player when he joins if he has bans active
        - added update to various columns in case those are set in .ini
        - added screenshots ( to fix )
        - added screenshots on own plugin.
        - added amx_addban.
        - added forward CBan_OnPlayerBannedPre/Post but not working.
        - forwards work.
        - added offban
        - added forward Cban_OnAddBan
        - added forward CBan_onOffBan
        
        v1.0.5
            - added banmenu
            - added offbanmenu
            - added reasons
            - added bantimes
            - added cbans_menu where you can write your reasons and your bantimes
            - fixed banning showing like server did it instead of user
            - added the max_offban_save when reading the ini ( before it was considering max = 0 )
            - added native for banning with offban
            - added native for banning with addban
        v1.0.6 ( mostly to respect some limitations from web servers that use AMXbans )
            - added default columns for ban table
            - added default values for ip/steamid when banning with amx_addban
            - added value limitation of addban when banning on steamid/ip so it doesn't exceed sql table
            - if sql table has an error, it won't stop the plugin but just give a log error. 
	v1.0.8
	    - banmenu reasons show in words instead of numbers. 


    add all TODO: shits
*/

#include < amxmodx >
#include < amxmisc >
#include < regex >
#include < time >
#include < sqlx >
#include < cban_main >

#define set_bit(%1,%2)      (%1 |= (1<<(%2&31)))
#define clear_bit(%1,%2)    (%1 &= ~(1<<(%2&31)))
#define check_bit(%1,%2)    (%1 & (1<<(%2&31)))

#if AMXX_VERSION_NUM < 183
    set_fail_state( "Plugin requires 1.8.3 or higher." );
#endif

new Handle:hTuple;

new g_ReasonsMenu;
new g_BanTimesMenu;

enum _:eUpdateBits
{
    UCCODE = 0,
    USTEAMID,
    UST_NONSTEAM,
    UIP,
    UNICK
}

enum _:eTasks ( +=1000 )
{
    TASK_KICK = 231,
    TASK_SHOW,
    TASK_DOUBLECHECK
}

enum _:eOffBanData
{
    //OFF_NICK[ MAX_NAME_LENGTH ],
    OFF_STEAMID[ MAX_STEAMID_LENGTH ],
    OFF_CCODE[ MAX_CSIZE ],
    OFF_IP[ MAX_IP_LENGTH ],
    OFF_IMMUNITY
}

enum _:eLateInfo
{
    ID,
    PID,
    LSTEAMID[ MAX_STEAMID_LENGTH ],
    LIP[ MAX_IP_LENGTH ],
    LREASON[ MAX_REASON_LENGTH ],
    LLENGTH
}
new Array:hOffBanData;
new Array:hOffBanName;
new g_iItems = 0;
//new g_OffBanData[ MAX_OFFBAN_SAVE ][ eOffBanData ];
new bHasCode, bHasCheckedCode;
new g_PlayerCode[ MAX_PLAYERS + 1 ][ MAX_CSIZE ];
new g_MotdCheck[ MAX_URL_LENGTH ];
new g_BanTable[ MAX_DB_LENGTH ];
new g_CheckTable[ MAX_DB_LENGTH ];
new g_ComplainUrl[ MAX_URL_LENGTH ];
new g_ServerIP[ MAX_SERVER_IP ];
new g_ServerIPWithoutPort[ MAX_IP_LENGTH ];
new g_ServerNameEsc[ 128 ];
new g_MaxOffBan;
new iUpdate;
new iExpired;
new iBanType;
new iAddBanType, iOffBanType;
new iMaxTries;

new g_IsBanning[ MAX_PLAYERS + 1 ];
new g_isBanningReason[ MAX_PLAYERS + 1 ][ MAX_REASON_LENGTH ];
new iBanTimes[ MAX_BANTIMES ];
new g_isBanningTime[ MAX_PLAYERS + 1 ];
new g_ReasonBanTimes[ MAX_REASONS ];
new bIsOffBan;
new bIsUsingBanReasonTime;
new bIsUsingCustomTime;

new fwPlayerBannedPre, fwPlayerBannedPost;
new fwAddBan;
new fwOffBan;
new fwOnCodeReceived, fwOnCodeFailed;
public plugin_init()
{
    register_plugin( "CBans", VERSION, "DusT" );

    register_cvar( "Ultimate_CBan", VERSION, FCVAR_SPONLY | FCVAR_SERVER );

    register_concmd( "amx_unban", "CmdUnban", ADMIN_FLAG_UNBAN, "< nick | ip | steamid > - removes ban from CBans database." );
    register_concmd( "amx_ban", "CmdBan", ADMIN_FLAG_BAN, "< time > < nick | steamid | #id > < reason > - Bans player." );
    register_concmd( "amx_offban", "CmdOffBan", ADMIN_FLAG_OFFBAN, "< time > < nick > < reason > - Offline ban. Bans player that was ingame earlier." );
    register_concmd( "amx_addban", "CmdAddBan", ADMIN_FLAG_ADDBAN, "< time > < steamid | ip > < reason > - Adds a ban to a player that is not ingame" );
    
    register_clcmd( "amx_offbanmenu", "CmdOffBanMenu", ADMIN_FLAG_OFFBAN );
    register_clcmd( "amx_banmenu", "CmdBanMenu", ADMIN_FLAG_BAN );
    register_clcmd( "_reason_", "CmdReason" );
    register_clcmd( "_ban_length_", "CmdBanLength" );

    fwPlayerBannedPre =  CreateMultiForward( "CBan_OnPlayerBannedPre", ET_CONTINUE, FP_CELL, FP_CELL, FP_VAL_BYREF, FP_STRING );
    fwPlayerBannedPost = CreateMultiForward( "CBan_OnPlayerBannedPost", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL, FP_STRING );
    fwAddBan = CreateMultiForward( "CBan_OnAddBan", ET_CONTINUE, FP_STRING, FP_CELL, FP_VAL_BYREF, FP_STRING );
    fwOffBan = CreateMultiForward( "CBan_OnOffBan", ET_CONTINUE, FP_STRING, FP_CELL, FP_VAL_BYREF, FP_STRING );
    fwOnCodeReceived = CreateMultiForward( "CBan_OnCodeReceived", ET_CONTINUE, FP_CELL, FP_STRING );
    fwOnCodeFailed = CreateMultiForward( "CBan_OnCodeFailed", ET_CONTINUE, FP_CELL, FP_STRING );

    //Cban_OnCodeFailed, Cban_OnCodeReceived
    register_message( get_user_msgid( "MOTD" ), "MessageMotd" );
    
    register_dictionary( "cbans.txt" );
    register_dictionary( "time.txt" );
}

public plugin_natives()
{
    register_native( "CBan_BanPlayer", "_CBan_BanPlayer" );
    register_native( "CBan_UnbanPlayer", "_CBan_UnbanPlayer" );
    register_native( "CBan_OffBanPlayer", "_CBan_OffBanPlayer" );
    register_native( "CBan_AddBanPlayer", "_CBan_AddBanPlayer" );
}
public plugin_cfg()
{
    ReadINI();
    ReadAndMakeMenus();
    set_task( 0.1, "SQL_Init" );
    hOffBanData = ArrayCreate( MAX_STEAMID_LENGTH + MAX_IP_LENGTH + MAX_CSIZE + 3, 1 );
    hOffBanName = ArrayCreate( MAX_NAME_LENGTH, 1 );
}

ReadINI()
{
    new szDir[ 128 ];
    get_configsdir( szDir, charsmax( szDir ) );

    add( szDir, charsmax( szDir ), "/CBans.ini" );

    if( !file_exists( szDir ) )
    {
        set_fail_state( "Couldn't load CBans.ini from configs folder." );
        return;
    }
    new fp = fopen( szDir, "rt" );
    new szData[ 256 ], szToken[ 32 ], szValue[ 224 ];
    new host[ MAX_DB_LENGTH ], user[ MAX_DB_LENGTH ], password[ MAX_DB_LENGTH ], db[ MAX_DB_LENGTH ];
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

        if( equal( szToken, "DB_HOST" ) )
            copy( host, charsmax( host ), szValue );
        else if( equal( szToken, "DB_USER" ) )
            copy( user, charsmax( user ), szValue );
        else if( equal( szToken, "DB_PASS" ) )
            copy( password, charsmax( password ), szValue );
        else if( equal( szToken, "DB_DB" ) )
            copy( db, charsmax( db ), szValue );
        else if( equal( szToken, "DB_BANTABLE" ) )
            copy( g_BanTable, charsmax( g_BanTable ), szValue );
        else if( equal( szToken, "DB_CHECKTABLE" ) )
            copy( g_CheckTable, charsmax( g_CheckTable ), szValue );
        else if( equal( szToken, "MOTD_LINK" ) )
            copy( g_MotdCheck, charsmax( g_MotdCheck ), szValue );
        else if( equal( szToken, "COMPLAIN_URL" ) )
            copy( g_ComplainUrl, charsmax( g_ComplainUrl ), szValue );  
        else if( equal( szToken, "DELETE_EXPIRED" ) )
            iExpired = str_to_num( szValue );  
        else if( equal( szToken, "UPDATE_CCODE" ) )
        {
            if( str_to_num( szValue ) >= 1 )
                set_bit( iUpdate, UCCODE );
        }
        else if( equal( szToken, "UPDATE_STEAMID" ) )
        {
            if( str_to_num( szValue ) == 1 )
                set_bit( iUpdate, UST_NONSTEAM );
            else if( str_to_num( szValue ) > 1 )
                set_bit( iUpdate, USTEAMID );
        }
        else if( equal( szToken, "UPDATE_IP" ) )
        {
            if( str_to_num( szValue ) >= 1 )
                set_bit( iUpdate, UIP );
        }
        else if( equal( szToken, "UPDATE_NICK" ) )
        {
            if( str_to_num( szValue ) >= 1 )
                set_bit( iUpdate, UNICK );
        }
        else if( equal( szToken, "BAN_TYPE" ) )
            iBanType = str_to_num( szValue );
        else if( equal( szToken, "ADDBAN_TYPE" ) )
            iAddBanType = str_to_num( szValue );
        else if( equal( szToken, "OFFBAN_TYPE" ) )
            iOffBanType = str_to_num( szValue );
        else if( equal( szToken, "MAX_OFFBAN_SAVE" ) )
            g_MaxOffBan = str_to_num( szValue );
        else if( equal( szToken, "MAX_TRIES" ) )
            iMaxTries = str_to_num( szValue );
    }
    fclose( fp );

    hTuple = SQL_MakeDbTuple( host, user, password, db );
}

ReadAndMakeMenus()
{
    new szDir[ 128 ];
    get_configsdir( szDir, charsmax( szDir ) );

    add( szDir, charsmax( szDir ), "/CBans_Menu.ini" );
    if( !file_exists( szDir ) )
    {
        set_fail_state( "Couldn't load CBans_Menu.ini from configs folder." );
        return;
    }

    new fp = fopen( szDir, "rt" );
    new szData[ 180 ], szToken[ MAX_REASON_LENGTH ], szValue[ 10 ];

    new bool:isReadingBans = false;
    new reasons[ MAX_REASONS ][ MAX_REASON_LENGTH ];
    new iPosReason, iPosBanTimes;
    while( fgets( fp, szData, charsmax( szData ) ) )
    {
        if( szData[ 0 ] == '/' && szData[ 1 ] == '/' )
            continue;
        if( szData[ 0 ] == ';' )
            continue;
        trim( szData );
        if( !szData[ 0 ] )
            continue;
        
        if( szData[ 0 ] == '[' && szData[ strlen( szData ) - 1 ] == ']' )
        {
            if( equali( szData, "[REASON]" ) )
                isReadingBans = false;
            else if( equali( szData, "[BANTIMES]" ) )
                isReadingBans = true; 
            
            continue;
        }

        strtok2( szData, szToken, charsmax( szToken ), szValue, charsmax( szValue ), '=' );
        trim( szValue );
        trim( szToken );

        if( isReadingBans )
        {
            iBanTimes[ iPosBanTimes++ ] = str_to_num( szToken );
        }
        else
        {
            copy( reasons[ iPosReason ], MAX_REASON_LENGTH - 1, szToken );
            g_ReasonBanTimes[ iPosReason++ ] = str_to_num( szValue );
        }
    }
    fclose( fp );

    g_ReasonsMenu = menu_create( "Reason", "ReasonHandler" );
    menu_additem( g_ReasonsMenu, "Custom" );
    
    for( new i; i < iPosReason; i++ )
        menu_additem( g_ReasonsMenu, reasons[ i ] );
    
    g_BanTimesMenu = menu_create( "Ban Length", "BanLengthHandler" );
    menu_additem( g_BanTimesMenu, "Custom" );

    new szTime[ 64 ];
    for( new i; i < iPosBanTimes; i++ )
    {
        if( iBanTimes[ i ] == 0 )
            menu_additem( g_BanTimesMenu, "Permanent" );
        else
        {
            get_time_length( 0, iBanTimes[ i ], timeunit_minutes, szTime, charsmax( szTime ) );
            menu_additem( g_BanTimesMenu, szTime );
        }        
    }
}

public SQL_Init()
{
    new szQuery[ 800 ];
    
    formatex( szQuery, charsmax( szQuery ), "CREATE TABLE IF NOT EXISTS `%s` (\
                                                `bid` INT NOT NULL AUTO_INCREMENT,\
                                                `player_ip` VARCHAR(16) NOT NULL,\
                                                `player_last_ip` VARCHAR(16) NOT NULL DEFAULT 'Unknown',\
                                                `player_id` VARCHAR(30) NOT NULL,\
                                                `player_nick` VARCHAR(32) NOT NULL,\
                                                `admin_ip` VARCHAR(16) NOT NULL DEFAULT 'Unknown',\
                                                `admin_id` VARCHAR(30) NOT NULL DEFAULT 'Unknown',\
                                                `admin_nick` VARCHAR(32) NOT NULL,\
                                                `ban_type` VARCHAR(7) NOT NULL,\
                                                `ban_reason` VARCHAR(100) NOT NULL,\
                                                `ban_created` INT NOT NULL,\
                                                `ban_length` INT NOT NULL,\
                                                `server_ip` VARCHAR(%d) NOT NULL DEFAULT 'IP_LAN',\
                                                `server_name` VARCHAR(64) NOT NULL DEFAULT 'WEBSITE',\
                                                `ban_kicks` INT NOT NULL DEFAULT 0,\
                                                `expired` INT(1) NOT NULL,\
                                                `c_code` VARCHAR(%d) NOT NULL DEFAULT 'unknown',\
                                                `update_ban` INT(1) NOT NULL DEFAULT 0,\
                                                PRIMARY KEY (bid)\
                                            );", g_BanTable, MAX_SERVER_IP, MAX_CSIZE );

    SQL_ThreadQuery( hTuple, "IgnoreHandle", szQuery );

    formatex( szQuery, charsmax( szQuery ), "CREATE TABLE IF NOT EXISTS `%s` (\
                                                `id` INT NOT NULL AUTO_INCREMENT,\
                                                `uid` INT NOT NULL,\
                                                `c_code` VARCHAR( %d ) NOT NULL UNIQUE,\
                                                `server` VARCHAR(%d) NOT NULL,\
                                                PRIMARY KEY ( id )\
                                            );", g_CheckTable, MAX_CSIZE, MAX_SERVER_IP );

    SQL_ThreadQuery( hTuple, "IgnoreHandle", szQuery );

    if( iExpired )
    {
        formatex( szQuery, charsmax( szQuery ), "DELETE FROM `%s` WHERE (`ban_created`+`ban_length`<UNIX_TIMESTAMP() AND `ban_length`<>0 AND `update_ban`=0) OR `expired`=1;", g_BanTable );
        SQL_ThreadQuery( hTuple, "IgnoreHandle", szQuery );
    }


    get_user_ip( 0, g_ServerIP, charsmax( g_ServerIP ), 0 );
    get_user_ip( 0, g_ServerIPWithoutPort, charsmax( g_ServerIPWithoutPort ), 0 );
    new ServerName[ 64 ];
    get_user_name( 0, ServerName, charsmax( ServerName ) );
    SQL_QuoteString( Empty_Handle, g_ServerNameEsc, charsmax( g_ServerNameEsc ), ServerName );

    /* TO_TEST: check if have to delete from g_CheckTable the server? */
    formatex( szQuery, charsmax( szQuery ), "DELETE FROM `%s` WHERE server='%s'", g_ServerNameEsc, g_ServerIP );
    SQL_ThreadQuery( hTuple, "IgnoreHandle", szQuery );
}

public IgnoreHandle( failState, Handle:query, error[], errNum )
{
    SQLCheckError( errNum, error );
}

public client_putinserver( id )
{
    if( !is_user_bot( id ) )
        set_task( 3.5, "SQL_CheckPlayer", id );
}

public client_disconnected( id )
{
    if( task_exists( id ) )
        remove_task( id );
    
    if( task_exists( id + TASK_KICK ) )
        remove_task( id + TASK_KICK );
    if( task_exists( id + TASK_SHOW ) )
        remove_task( id + TASK_SHOW );
    if( task_exists( id + TASK_DOUBLECHECK ) )
        remove_task( id + TASK_DOUBLECHECK );
        
    if( !g_PlayerCode[ id ][ 0 ] )
        return;
    new name[ MAX_NAME_LENGTH ];
    get_user_name( id, name, charsmax( name ) );
    //strtolower( name );

    new pos = ArrayFindStringi( hOffBanName, name );

    if( pos == -1 )
    {
        new data[ eOffBanData ];
        get_user_authid( id, data[ OFF_STEAMID ], charsmax( data[ OFF_STEAMID ] ) );
        get_user_ip( id, data[ OFF_IP ], charsmax( data[ OFF_IP ] ), 1 );
        copy( data[ OFF_CCODE ], charsmax( data[ OFF_CCODE ] ), g_PlayerCode[ id ] );
        if( get_user_flags( id ) & ADMIN_FLAG_IMMUNITY )
            data[ OFF_IMMUNITY ] = 1;
        ArrayPushArray( hOffBanData, data, sizeof data );
        ArrayPushString( hOffBanName, name );
        if( g_iItems >= g_MaxOffBan )
        {
            ArrayDeleteItem( hOffBanData, 0 );
            ArrayDeleteItem( hOffBanName, 0 );
        }
        else
            g_iItems++;
    }

    g_PlayerCode[ id ][ 0 ] = 0;
}


public plugin_end()
{
    SQL_ThreadQuery( hTuple, "IgnoreHandle", fmt( "DELETE FROM `%s`", g_CheckTable ) );

    DestroyForward( fwAddBan );
    DestroyForward( fwOffBan );
    DestroyForward( fwPlayerBannedPre );
    DestroyForward( fwPlayerBannedPost );

    SQL_FreeHandle( hTuple );
}

public SQL_CheckPlayer( param[], id )
{
    new data[ 3 ];
    if( id > 32 )
    {
        id -= TASK_DOUBLECHECK;
        data[ 1 ] = param[ 0 ];
    }

    if( !is_user_connected( id ) )
        return;

    data[ 0 ] = id;

    SQL_ThreadQuery( hTuple, "SQL_CheckProtectorHandle", fmt( "SELECT `c_code` FROM `%s` WHERE `uid`=%d AND `server`='%s';", g_CheckTable, get_user_userid( id ), g_ServerIP ), data, sizeof data );
}


/*
TO_TEST:
+ add cvar check max tries
+ don't kick after max tries
+ add forward fwOnCodeReceived (Cban_OnCodeFailed, Cban_OnCodeReceived)
+ if has code, do a certain check, else do another

*/
public SQL_CheckProtectorHandle( failState, Handle:query, error[], errNum, data[], dataSize )
{
    SQLCheckError( errNum, error );

    new id = data[ 0 ];
    new results = SQL_NumResults( query );
    if( !is_user_connected( id ) )
        return;
    new dummy;
    if( !results )
    {
        if( data[ 1 ] >= iMaxTries )
        {
            ExecuteForward( fwOnCodeFailed, dummy, id, g_PlayerCode[ id ] );
            if( dummy == CBAN_CODE_HANDLED )
                set_bit( bHasCode, id );
        }
        else    // check again for user's cookie
        {
            new param[ 3 ];
            param[ 0 ] = data[ 1 ] + 1;
            set_task( 2.0, "SQL_CheckPlayer", id + TASK_DOUBLECHECK, param, sizeof param );
            return; 
        }
    }
    else if( results > 1 )
    {
        ExecuteForward( fwOnCodeFailed, dummy, id, g_PlayerCode[ id ] );
        if( dummy == CBAN_CODE_HANDLED )
            set_bit( bHasCode, id );
    }
    else
    {
        SQL_ReadResult( query, 0, g_PlayerCode[ id ], MAX_CSIZE - 1 );
        ExecuteForward( fwOnCodeReceived, dummy, id, g_PlayerCode[ id ] );
        set_bit( bHasCode, id );
    }
    new query[ 512 ];
    new authid[ MAX_STEAMID_LENGTH ], ip[ MAX_IP_LENGTH ];

    get_user_authid( id, authid, charsmax( authid ) );
    get_user_ip( id, ip, charsmax( ip ), 1 );
    set_bit( bHasCheckedCode, id );
    if( check_bit( bHasCode, id ) )
    {
        formatex( query, charsmax( query ), "SELECT * FROM `%s` WHERE ((c_code='%s') OR (player_id='%s' AND ban_type LIKE '%%S%%') \
            OR ( ( player_ip='%s' OR player_last_ip='%s') AND ban_type LIKE '%%I%%')) AND expired=0;", g_BanTable, g_PlayerCode[ id ],
            authid, ip, ip );
    }
    else
    {
    	formatex(query, charsmax( query ), "SELECT * FROM `%s` WHERE ((player_id='%s' AND ban_type LIKE '%%S%%') \
            OR ( ( player_ip='%s' OR player_last_ip='%s') AND ban_type LIKE '%%I%%')) AND expired=0;", g_BanTable, authid, ip, ip);
    }
    
    SQL_ThreadQuery( hTuple, "SQL_CheckBanHandle", query, data, dataSize );
    
}

public SQL_CheckBanHandle( failState, Handle:query, error[], errNum, data[], dataSize )
{
    SQLCheckError( errNum, error );

    new id = data[ 0 ];
    if( !is_user_connected( id ) || !SQL_NumResults( query ) )
        return;

    new max = SQL_NumResults( query );

    new bid, ban_created, ban_length, current_time, update_ban;
    new player_ip[ MAX_IP_LENGTH ], player_id[ MAX_STEAMID_LENGTH ], player_nick[ MAX_NAME_LENGTH ];
    new admin_nick[ MAX_NAME_LENGTH ], ban_reason[ MAX_REASON_LENGTH ];
    new server_name[ 64 ];
    new ccode[ MAX_CSIZE ];
    new ip[ MAX_IP_LENGTH ];
    new szQuery[ 512 ];

    for( new i; i < max; i++ )
    {
        bid = SQL_ReadResult( query, 0 );
        ban_created = SQL_ReadResult( query, 10 );
        ban_length = SQL_ReadResult( query, 11 );
        current_time = get_systime();
        update_ban = SQL_ReadResult( query, 17 );

        // let's avoid random admins to ban immunity flag people through a "workaround"
        if( update_ban > 0 && ( get_user_flags( id ) & ADMIN_FLAG_IMMUNITY ) )   
        {
            SQL_ThreadQuery( hTuple, "IgnoreHandle", fmt( "DELETE FROM `%s` WHERE `bid`=%d", g_BanTable, bid ) );
            SQL_NextRow( query )
            continue;
        }

        if( ban_created + (ban_length*60) < current_time && ban_length && ( update_ban != 1 || !iAddBanType ) && ( update_ban != 2 || !iOffBanType ) )      // ban has expired. 
        {
            // update expired to be 1, so next time it doesn't check it.
            SQL_ThreadQuery( hTuple, "IgnoreHandle", fmt( "UPDATE `%s` SET `expired`=1 WHERE `bid`=%d", g_BanTable, bid ) );
            SQL_NextRow( query );
            continue;
        }

        get_user_ip( id, ip, charsmax( ip ), 1 );

        formatex( szQuery, charsmax( szQuery ), "UPDATE `%s` SET player_last_ip='%s',ban_kicks=ban_kicks+1", g_BanTable, ip );
        
        SQL_ReadResult( query, 1, player_ip, charsmax( player_ip ) );
        SQL_ReadResult( query, 3, player_id, charsmax( player_id ) );
        SQL_ReadResult( query, 4, player_nick, charsmax( player_nick ) );
        SQL_ReadResult( query, 7, admin_nick, charsmax( admin_nick ) );
        SQL_ReadResult( query, 9, ban_reason, charsmax( ban_reason ) );
        SQL_ReadResult( query, 13, server_name, charsmax( server_name ) );
        SQL_ReadResult( query, 16, ccode, charsmax( ccode ) );

        if( (!ccode[ 0 ] || containi( ccode, "unknown" ) != -1) && check_bit( bHasCode, id ) )
        {
            add( szQuery, charsmax( szQuery ), fmt( ",c_code='%s'", g_PlayerCode[ id ] ) );
            copy( ccode, charsmax( ccode ), g_PlayerCode[ id ] );
        }


        if( update_ban == 1 )    // if addban
        {
            new nick[ MAX_NAME_LENGTH * 2 ], authid[ MAX_STEAMID_LENGTH ];
            
            get_user_authid( id, authid, charsmax( authid ) );
            SQL_QuoteString( Empty_Handle, nick, charsmax( nick ), fmt( "%n", id ) );

            add( szQuery, charsmax( szQuery ), fmt( ",player_nick='%s',player_id='%s',player_ip='%s',update_ban=0", nick, authid, ip ) );
            copy( player_nick, charsmax( player_nick ), fmt( "%n", id ) );
            copy( player_ip, charsmax( player_ip ), ip );
            copy( player_id, charsmax( player_id ), authid );

            new szBanType[ 3 ];
            switch( iBanType )
            {
                case 0: szBanType[ 0 ] = 'S';
                case 1: szBanType[ 0 ] = 'I';
                case 2: copy( szBanType, charsmax( szBanType ), "SI" );
                case 3:
                {
                    if( is_user_steam( id ) )
                        szBanType[ 0 ] = 'S';
                    else
                        szBanType[ 0 ] = 'I';
                }
                default: copy( szBanType, charsmax( szBanType ), "SI" );
            }
            
            add( szQuery, charsmax( szQuery ), fmt(",ban_type='%s'", szBanType ) );
        
            if( iAddBanType )
            {
                add( szQuery, charsmax( szQuery ), fmt( ",ban_created=%d", current_time ) );
                ban_created = current_time;
            }
        }
        else
        {
            if( update_ban == 2 )
            {
                if( iOffBanType )
                {
                    add( szQuery, charsmax( szQuery ), fmt( ",ban_created=%d", current_time ) );
                    ban_created = current_time;
                }
                add( szQuery, charsmax( szQuery ), ",update_ban=0" );
            }
            if( iUpdate )
            {
                if( check_bit( iUpdate, UCCODE ) )
                {
                    if( (!ccode[ 0 ] || !equal( ccode, g_PlayerCode[ id ] )) && check_bit( bHasCode, id ) )
                        add( szQuery, charsmax( szQuery ), fmt( ",c_code='%s'", g_PlayerCode[ id ] ) );
                }
                if( check_bit( iUpdate, USTEAMID ) || ( check_bit( iUpdate, UST_NONSTEAM ) && !is_user_steam( id ) ) )
                {
                    new authid[ MAX_STEAMID_LENGTH ];
                    get_user_authid( id, authid, charsmax( authid ) );
                    if( !equal( player_id, authid ) )
                    {
                        copy( player_id, charsmax( player_id ), authid );
                        add( szQuery, charsmax( szQuery ), fmt( ",player_id='%s'", authid ) );
                    }
                }
                if( check_bit( iUpdate, UNICK ) )
                {
                    new nnick[ MAX_NAME_LENGTH ];
                    get_user_name( id, nnick, charsmax( nnick ) );
                    if( !equal( player_nick, nnick ) )
                    {
                        new nick[ MAX_NAME_LENGTH * 2 ];
                        copy( player_nick, charsmax( player_nick ), nnick );
                        SQL_QuoteString( Empty_Handle, nick, charsmax( nick ), nnick );
                        add( szQuery, charsmax( szQuery ), fmt( ",player_nick='%s'", nick ) );
                    }
                }
                if( check_bit( iUpdate, UIP ) )
                {
                    if( !equal( player_ip, ip ) )
                    {
                        copy( player_ip, charsmax( player_ip ), ip );
                        add( szQuery, charsmax( szQuery ), fmt( ",player_ip='%s'", ip ) );
                    }
                }
            }
        }

        add( szQuery, charsmax( szQuery ), fmt( " WHERE bid=%d;", bid ) );
        SQL_ThreadQuery( hTuple, "IgnoreHandle", szQuery );
        
        console_print( id, "[CBAN] ===============================================" );
        console_print( id, "[CBAN] %L", id, "MSG_1" );
        console_print( id, "[CBAN] %L: %n.", id, "MSG_NICK", id );
        console_print( id, "[CBAN] %L: %s.", id, "MSG_IP", player_ip );
        console_print( id, "[CBAN] %L: %s.", id, "MSG_STEAMID", player_id );
        console_print( id, "[CBAN] %L: %s.", id, "MSG_ADMIN", admin_nick );
        console_print( id, "[CBAN] %L: %s.", id, "MSG_REASON", ban_reason );
        if( ban_length == 0 )
            console_print( id, "[CBAN] %L: %L", id, "MSG_LENGTH", id, "MSG_PERMANENT" );
        else
        {
            new szTimeLeft[ 128 ];
            get_time_length( id, ban_length, timeunit_minutes, szTimeLeft, charsmax( szTimeLeft ) );
            console_print( id, "[CBAN] %L: %s.", id, "MSG_LENGTH", szTimeLeft );
            get_time_length( id, ban_length*60 + ban_created - current_time, timeunit_seconds, szTimeLeft, charsmax( szTimeLeft ) );
            console_print( id, "[CBAN] %L: %s.", id, "MSG_TIMELEFT", szTimeLeft );
        }
        console_print( id, "[CBAN] %L: %s.", id, "MSG_SERVERNAME", server_name );
        console_print( id, "[CBAN] %L %s.", id, "MSG_COMPLAIN", g_ComplainUrl );
        console_print( id, "[CBAN] ===============================================" );

        set_task( 1.0, "KickPlayer", id + TASK_KICK );
        return;
    }   
}


public KickPlayer( id )
{
    id -= TASK_KICK;

    if( is_user_connected( id ) )
    {
        emessage_begin( MSG_ONE, SVC_DISCONNECT, _, id );
        ewrite_string( "You are BANNED. Check your console." );
        emessage_end();
        //server_cmd( "kick #%d You are BANNED. Check your console.", get_user_userid( id ) );
    }
}

public MessageMotd( msgId, msgDest, msgEnt)
{
    set_msg_arg_int( 1, ARG_BYTE, 1 );
    set_msg_arg_string( 2, fmt( "%s?uid=%d&srv=%s", g_MotdCheck, get_user_userid( msgEnt ), g_ServerIP ) );
    
    return PLUGIN_CONTINUE;
}

public CmdUnban( id, level, cid )
{
    if( !cmd_access( id, level, cid, 2 ) )
        return PLUGIN_HANDLED;
    
    new target[ MAX_NAME_LENGTH ];
    read_argv( 1, target, charsmax( target ) );

    new type = UT_NICK;

    static Regex:pPattern;
    if( !pPattern )
        pPattern = regex_compile( "^^(\d{1,3}\.){3}\d{1,3}$" );
    
    if( regex_match_c( target, pPattern ) ) 
        type = UT_IP;
    else if( strlen( target ) > MIN_STEAMID_LENGTH && ( containi( target, "VALVE_") != -1 || containi( target, "STEAM_" ) != -1 ) )
        type = UT_STEAMID;

    UnbanPlayer( id, target, type );
    return PLUGIN_HANDLED;   
}

public CmdBan( id, level, cid )
{
    if( !cmd_access( id, level, cid, 4 ) )
        return PLUGIN_HANDLED;
    
    new ban_length = abs( read_argv_int( 1 ) );
    new target[ 32 ];
    
    read_argv( 2, target, charsmax( target ) );

    new pid = cmd_target( id, target, CMDTARGET_ALLOW_SELF | CMDTARGET_OBEY_IMMUNITY );

    if( !pid )
        return PLUGIN_HANDLED;

    if( !check_bit( bHasCheckedCode, id ) )
    {
        console_print( id, "[CBAN] Cannot do this operation. Retry in few seconds." );
        return PLUGIN_HANDLED;
    }
    new args[ 160 ], ban_reason[ MAX_REASON_LENGTH ];

    read_args( args, charsmax( args ) );
    remove_quotes( args ); trim( args );

    new iReasonPos = containi( args, target );
    iReasonPos += strlen( target ) + 1 + iReasonPos;
    copy( ban_reason, charsmax( ban_reason ), args[ iReasonPos ] );
    /*TODO: fix replace_string???*/
    //replace_string( ban_reason, charsmax( ban_reason ), "^"", "" ); 
    BanPlayer( id, pid, ban_length, ban_reason );
    console_print( id, "[CBAN] Player %n successfully banned.", pid );
    return PLUGIN_HANDLED;
}

BanPlayer( id, pid, ban_length, ban_reason[] )
{
    if( pid > 0 && !is_user_connected( pid ) )
        return;
    
    new authid[ MAX_STEAMID_LENGTH ], ip[ MAX_IP_LENGTH ];
    new admin_id[ MAX_STEAMID_LENGTH ], admin_ip[ MAX_IP_LENGTH ];
    new admin_nick[ MAX_NAME_LENGTH * 2 ], player_nick[ MAX_NAME_LENGTH * 2 ];  
    new ccode[ MAX_CSIZE ];
    if( pid > 0 )
    {
            get_user_authid( pid, authid, charsmax( authid ) );
            get_user_ip( pid, ip, charsmax( ip ), 1 );
            //get_user_name( pid, pnick, charsmax( pnick ) );
            SQL_QuoteStringFmt( Empty_Handle, player_nick, charsmax( player_nick ), "%n", pid );
            copy( ccode, charsmax( ccode ), g_PlayerCode[ pid ] );
            new returnType;
            ExecuteForward( fwPlayerBannedPre, returnType, pid, id, ban_length, ban_reason );
            if( returnType == PLUGIN_HANDLED )
                return;
    }
    else
    {

        new data[ eOffBanData ];
        ArrayGetArray( hOffBanData, -pid, data, sizeof data );
        if( data[ OFF_IMMUNITY ] == 1 )
        {
            console_print( id, "Player has immunity!" );
            return;
        }

        copy( ip, charsmax( ip ), data[ OFF_IP ] );
        copy( authid, charsmax( authid ), data[ OFF_STEAMID ] );
        copy( ccode, charsmax( ccode ), data[ OFF_CCODE ] );  
        SQL_QuoteStringFmt( Empty_Handle, player_nick, charsmax( player_nick ), "%a", ArrayGetStringHandle( hOffBanName, -pid ) ); 

        add( ban_reason, MAX_REASON_LENGTH - 1, " [OFFBAN]" );

        new returnType;
        ExecuteForward( fwOffBan, returnType, data[ OFF_STEAMID ], id, ban_length, ban_reason );
        if( returnType == PLUGIN_HANDLED )
            return;
    }

    new bool:bIsId = false;
    if( id && is_user_connected( id ) )
    {
        bIsId = true;
        get_user_authid( id, admin_id, charsmax( admin_id ) );
        get_user_ip( id, admin_ip, charsmax( admin_ip ) );
        SQL_QuoteStringFmt( Empty_Handle, admin_nick, charsmax( admin_nick ), "%n", id );
    }
    else 
    {
        copy( admin_ip, charsmax( admin_ip ), "IP_LAN" );
        copy( admin_id, charsmax( admin_id ), "ID_LAN" );
    }

    new szBanType[ 3 ];
    switch( iBanType )
    {
        case 0: szBanType[ 0 ] = 'S';
        case 1: szBanType[ 0 ] = 'I';
        case 2: copy( szBanType, charsmax( szBanType ), "SI" );
        case 3:
        {
            if( is_user_steam( id ) )
                szBanType[ 0 ] = 'S';
            else
                szBanType[ 0 ] = 'I';
        }
        default: copy( szBanType, charsmax( szBanType ), "SI" );
    }
    
    if( pid > 0 )
    {
        new data[ eLateInfo ];
        data[ ID ] = id;
        data[ PID ] = pid;
        data[ LLENGTH ] = ban_length;
        copy( data[ LREASON ], MAX_REASON_LENGTH - 1, ban_reason );
        copy( data[ LIP ], MAX_IP_LENGTH - 1, ip );
        copy( data[ LSTEAMID ], MAX_STEAMID_LENGTH - 1, authid );
        
        ExecuteForward( fwPlayerBannedPost, _, pid, id, ban_length, ban_reason );
        set_task( 1.0, "DisplayMessage", pid + TASK_SHOW, data, sizeof data );
        set_task( 2.0, "KickPlayer", pid + TASK_KICK );
    }

    new szQuery[ 512 ];
    new ban_created = get_systime();
    /*
    TODO:
    	formatex(szQuery, 1023, "INSERT INTO `%s` (player_ip, player_last_ip, player_id, player_nick, admin_ip, admin_id, admin_nick, ban_type, ban_reason, ban_created, ban_length, server_ip, server_name, ban_kicks, expired, c_code, update_ban)SELECT '%s','%s','%s','%s','%s','%s','%s','%s','%s',%d,%d,'%s','%s',0,0,'%s',0 FROM dual WHERE NOT EXISTS (SELECT * FROM `%s` WHERE ((ban_type LIKE '%%I%%' AND player_ip='%s') or (ban_type LIKE '%%s%%' AND player_id='%s')) and expired=0 LIMIT 1);", g_BanTable, ip, ip, authid, player_nick, admin_ip, admin_id, var3, szBanType, ban_reason, ban_created, ban_length, g_ServerIPWithoutPort, g_ServerNameEsc, ccode, g_BanTable, ip, authid);

    */
    formatex( szQuery, charsmax( szQuery ), "INSERT INTO `%s` VALUES(NULL,'%s','%s','%s','%s','%s','%s','%s','%s','%s',%d,%d,'%s','%s',0,0,'%s',0);\
                                            ", g_BanTable, ip, ip, authid, player_nick, admin_ip, admin_id, bIsId==false? g_ServerNameEsc:admin_nick, szBanType, ban_reason, ban_created, ban_length,
                                             g_ServerIPWithoutPort, g_ServerNameEsc, ccode );
    
    // TODO: handleban instead of ignorehandle
    SQL_ThreadQuery( hTuple, "IgnoreHandle", szQuery );
    //debug
    //server_print( "%d", strlen( szQuery ) );   
}

/*
TODO: HandleBan from above
public HandleBan(failState, Handle:query, error[], errNum, data[], datasize)
{
	if (errNum)
	{
		set_fail_state(error);
	}
	if (SQL_AffectedRows(query))
	{
		new var1;
		if (is_user_connected(data[1]) && !task_exists(data[1] + 1231, MaxClients))
		{
			set_task(1065353216, "DisplayMessage", data[1] + 1231, data, datasize, 27836, MaxClients);
		}
	}
	return 0;
}
*/
public DisplayMessage( data[] )
{
    if( !is_user_connected( data[ PID ] ) )
        return;

    static ServerName[ 64 ];
    if( !ServerName[ 0 ] )
        get_user_name( 0, ServerName, charsmax( ServerName ) );
    new szTimeLeft[ 128 ];
    new nick[ MAX_NAME_LENGTH ];
    if( data[ ID ] > 0 && is_user_connected( data[ ID ] ) )
        get_user_name( data[ ID ], nick, charsmax( nick ) );
    else
        data[ ID ] = 0;

    console_print( data[ PID ], "[CBAN] ===============================================" );
    console_print( data[ PID ], "[CBAN] %L", data[ PID ], "MSG_1" );
    console_print( data[ PID ], "[CBAN] %L: %n.", data[ PID ], "MSG_NICK", data[ PID ] );
    console_print( data[ PID ], "[CBAN] %L: %s.", data[ PID ], "MSG_IP", data[ LIP ] );
    console_print( data[ PID ], "[CBAN] %L: %s.", data[ PID ], "MSG_STEAMID", data[ LSTEAMID ] );
    console_print( data[ PID ], "[CBAN] %L: %s.", data[ PID ], "MSG_ADMIN", data[ ID ]==0? ServerName:nick );
    console_print( data[ PID ], "[CBAN] %L: %s.", data[ PID ], "MSG_REASON", data[ LREASON ] );
    if( data[ LLENGTH ] == 0 )
        console_print( data[ PID ], "[CBAN] %L: %L", data[ PID ], "MSG_LENGTH", data[ PID ], "MSG_PERMANENT" );
    else
    {
        get_time_length( data[ PID ], data[ LLENGTH ], timeunit_minutes, szTimeLeft, charsmax( szTimeLeft ) );
        console_print( data[ PID ], "[CBAN] %L: %s.", data[ PID ], "MSG_LENGTH", szTimeLeft );
    }
    console_print( data[ PID ], "[CBAN] %L: %s.", data[ PID ], "MSG_SERVERNAME", ServerName );
    console_print( data[ PID ], "[CBAN] %L %s.", data[ PID ], "MSG_COMPLAIN", g_ComplainUrl );
    console_print( data[ PID ], "[CBAN] ===============================================" );
    client_print_color( 0, print_team_red, "^4[CBAN]^1 Admin ^4%s^1 Banned: ^3%n^1 Reason: ^3%s^1 Time: ^3%s^1", data[ ID ]==0? "SERVER":nick, data[ PID ], data[ LREASON ], data[ LLENGTH ]==0? "Permanent":szTimeLeft );
}
UnbanPlayer( id, target[ MAX_NAME_LENGTH ], type )
{
    if( !target[ 0 ] || strlen( target ) < MIN_TARGET_LENGTH )
        return; 
    new szUnban[ 74 ];
    SQL_QuoteString( Empty_Handle, szUnban, charsmax( szUnban ), target );
    switch( type )
    {
        case UT_NICK: format( szUnban, charsmax( szUnban ), "nick='%s'", szUnban );
        case UT_IP: format( szUnban, charsmax( szUnban ), "ip='%s'", szUnban );
        case UT_STEAMID: format( szUnban, charsmax( szUnban ), "id='%s'", szUnban );
        default: 
        {
            console_print( id, "[CBAN] Couldn't understand type." );
            return;
        }
    }

    SQL_ThreadQuery( hTuple, "IgnoreHandle", fmt( "DELETE FROM `%s` WHERE player_%s;", g_BanTable, szUnban ) );

    console_print( id, "Player(s) with %s = '%s' is unbanned.", type == UT_NICK? "nick": type == UT_IP? "IP":"SteamID", target );
}

public CmdAddBan( id, level, cid )
{
    if( !cmd_access( id, level, cid, 4 ) )
        return PLUGIN_HANDLED;

    new ban_length = abs( read_argv_int( 1 ) );
    new target[ 32 ];
    
    read_argv( 2, target, charsmax( target ) );

    new args[ 160 ], ban_reason[ MAX_REASON_LENGTH ];
    read_args( args, charsmax( args ) );
    remove_quotes( args ); trim( args );

    new iReasonPos = containi( args, target );
    iReasonPos += strlen( target ) + 1;
    copy( ban_reason, charsmax( ban_reason ), args[ iReasonPos ] );
    new pid = find_player( "cl", target );

    if( !pid )
        pid = find_player( "d", target );

    if( pid )
    {
        if( !( get_user_flags( pid ) & ADMIN_FLAG_IMMUNITY ) )
            BanPlayer( id, pid, ban_length, ban_reason );
        else
            console_print( id, "Player has immunity!" );
        return PLUGIN_HANDLED;
    }

    AddBanPlayer( id, target, ban_length, ban_reason );

    return PLUGIN_HANDLED;
}

AddBanPlayer( admin, target[], ban_length, ban_reason[ MAX_REASON_LENGTH ] )
{
    static Regex:pPattern;
    if( !pPattern )
        pPattern = regex_compile( "^^(\d{1,3}\.){3}\d{1,3}$" );

    new szBanType[ 2 ];
    
    if( regex_match_c( target, pPattern ) ) 
    {
        szBanType[ 0 ] = 'I';
        target[ MAX_IP_LENGTH - 1 ] = 0;    // to avoid the string being too long for the database
    }
    else if( strlen( target ) > MIN_STEAMID_LENGTH && ( containi( target, "VALVE_") != -1 || containi( target, "STEAM_" ) != -1 ) )
    {
        szBanType[ 0 ] = 'S';
        target[ MAX_STEAMID_LENGTH - 1 ] = 0;
    }
    else
    {
        console_print( admin, "Invalid argument. Must be IP or steamid." );
        return;
    }

    add( ban_reason, charsmax( ban_reason ), " [ADDBAN]" );

    new returnType;
    ExecuteForward( fwAddBan, returnType, target, admin, ban_length, ban_reason );
    if( returnType == PLUGIN_HANDLED )
        return;

    new admin_ip[ MAX_IP_LENGTH ], admin_id[ MAX_STEAMID_LENGTH ], admin_nick[ MAX_NAME_LENGTH * 2 ];
    new targetEsc[ 64 ];

    
    SQL_QuoteString( Empty_Handle, targetEsc, charsmax( targetEsc ), target );
    new bool:bIsId = false;
    if( admin && is_user_connected( admin ) )
    {
        bIsId = true;
        get_user_ip( admin, admin_ip, charsmax( admin_ip ), 1 );
        get_user_authid( admin, admin_id, charsmax( admin_id ) );
        SQL_QuoteStringFmt( Empty_Handle, admin_nick, charsmax( admin_nick ), "%n", admin );
    }
    else 
    {
        copy( admin_ip, charsmax( admin_ip ), "IP_LAN" );
        copy( admin_id, charsmax( admin_id ), "ID_LAN" );
    }
    
    new query[ 512 ];
    formatex( query, charsmax( query ), "INSERT INTO `%s` VALUES(NULL,'%s','0','%s','AddBanPlayer','%s','%s','%s','%s','%s',%d,%d,'%s','%s',0,\
                                        0,'',1);", g_BanTable, szBanType[0]=='I'? targetEsc:"1.1.1.1", szBanType[0]=='S'? targetEsc:"STEAM_0:0:1", admin_ip, admin_id, bIsId==false? g_ServerNameEsc:admin_nick, szBanType,
                                        ban_reason, get_systime(), ban_length, g_ServerIPWithoutPort, g_ServerNameEsc );
    SQL_ThreadQuery( hTuple, "IgnoreHandle", query );
}

public CmdOffBan( id, level, cid )
{
    if( !cmd_access( id, level, cid, 4 ) )
        return PLUGIN_HANDLED;
    
    new ban_length = read_argv_int( 1 );

    new target[ MAX_NAME_LENGTH ];

    read_argv( 2, target, charsmax( target ) );

    new pid = find_player( "bl", target );
    new bool:isInGame = true;
    if( pid && ( get_user_flags( pid ) & ADMIN_FLAG_IMMUNITY ) )
    {
        console_print( id, "Player has immunity" );
        return PLUGIN_HANDLED;
    }
    if( !pid )
    {
        isInGame = false;
        pid = ArrayFindStringContaini( hOffBanName, target );
        if( pid == -1 )
        {
            console_print( id, "Player not found!" );
            return PLUGIN_HANDLED;
        }
    }

    new ban_reason[ MAX_REASON_LENGTH ], args[ 160 ];

    read_args( args, charsmax( args ) );
    remove_quotes( args );

    new iReasonPos = containi( args, target );
    iReasonPos += strlen( target ) + 1;
    copy( ban_reason, charsmax( ban_reason ), args[ iReasonPos ] );
    
    BanPlayer( id, isInGame? pid:-pid, ban_length, ban_reason );
    return PLUGIN_HANDLED;
}
public CmdBanMenu( id, level, cid )
{
    if( cmd_access( id, level, cid, 0 ) )
    {
        clear_bit( bIsUsingCustomTime, id );
        clear_bit( bIsOffBan, id );
        clear_bit( bIsUsingBanReasonTime, id );
        g_IsBanning[ id ] = 0;
        g_isBanningTime[ id ] = 0;
        g_isBanningReason[ id ][ 0 ] = 0;
        OpenMainMenu( id );
    }
    return PLUGIN_HANDLED;
}

OpenMainMenu( id )
{
    new menuid = menu_create( "Ban Menu", "MainMenuHandler" );

    new players[ 32 ], num;
    get_players( players, num );
    clear_bit( bIsOffBan, id );
    new buff[ 10 ];
    for( new i; i < num; i++ )
    {
        num_to_str( get_user_userid( players[ i ] ), buff, charsmax( buff ) );
        menu_additem( menuid, fmt( "%n%c", players[ i ], is_user_admin( players[ i ] )? '*':' ' ), buff, (get_user_flags( players[ i ] ) & ADMIN_FLAG_IMMUNITY)? (1<<26):0 );
    }
    menu_display( id, menuid );
}
public MainMenuHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item >= 0 )
    {
        new buff[ 10 ];
        menu_item_getinfo( menuid, item, _, buff, charsmax( buff ) );
        buff[ 0 ] = str_to_num( buff );
        new pid = find_player( "k", buff[ 0 ] );
        if( pid )
        {
            g_IsBanning[ id ] = buff[ 0 ];
            if( g_isBanningReason[ id ][ 0 ] )
                ConfirmMenu( id );
            else
                menu_display( id, g_ReasonsMenu );       
        }
        else
        {
            client_print_color( id, print_team_red, "^4[CBAN]^1 Player left. You can use ^3amx_offbanmenu^1 instead." );
        }
    }
    else
        g_IsBanning[ id ] = 0;

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

public ReasonHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item >= 0 && g_IsBanning[ id ] )
    {
        if( item == 0 )
            client_cmd( id, "messagemode _reason_" );
        else
        {
            menu_item_getinfo( menuid, item, _, _, _, g_isBanningReason[ id ], MAX_REASON_LENGTH - 1 );
            g_isBanningTime[ id ] = item - 1;
            set_bit( bIsUsingBanReasonTime, id );
            clear_bit( bIsUsingCustomTime, id );
            ConfirmMenu( id );
        }
    }
    else
    {
        clear_bit( bIsUsingCustomTime, id );
        clear_bit( bIsUsingBanReasonTime, id );
        clear_bit( bIsOffBan, id );
        g_isBanningTime[ id ] = 0;
        g_IsBanning[ id ] = 0;
        g_isBanningReason[ id ][ 0 ] = 0;
    }
    //menu_cancel( id );
    return PLUGIN_HANDLED;
}

ConfirmMenu( id )
{
    new menuid = menu_create( "Confirm Ban", "ConfirmHandler" );
    
    new pid;

    if( !g_IsBanning[ id ] )
        return;

    if( check_bit( bIsOffBan, id ) )
    {
        pid = g_IsBanning[ id ] - 1;
    }
    else
    {
        pid = find_player( "k", g_IsBanning[ id ] );
        if( !pid )
        {
            client_print_color( id, print_team_red, "^4[CBAN]^1 Player left. You can use ^3amx_offbanmenu^1 instead." );
            return;
        }
    }

    if( check_bit( bIsOffBan, id ) )
        menu_additem( menuid, fmt( "\yPlayer: \w%a", ArrayGetStringHandle( hOffBanName, pid ) ) );
    else
        menu_additem( menuid, fmt( "\yPlayer: \w%n", pid ) );
    
    menu_additem( menuid, fmt( "\yReason: \w%s", g_isBanningReason[ id ] ) );
    
    new time; 
    if( check_bit( bIsUsingCustomTime, id ) )
        time = g_isBanningTime[ id ];
    else if( check_bit( bIsUsingBanReasonTime, id ) )
        time = g_ReasonBanTimes[ g_isBanningTime[ id ] ];
    else
        time = iBanTimes[ g_isBanningTime[ id ] ];

    if( time == 0 )
        menu_additem( menuid, "\yBan Length: \wPermanent^n")
    else
    {
        new szTime[ 64 ];
        get_time_length( 1, time, timeunit_minutes, szTime, charsmax( szTime ) );
        menu_additem( menuid, fmt( "\yBan Length: \w%s^n", szTime ) );
    }

    menu_additem( menuid, "\rConfirm" );

    menu_display( id, menuid );
}

public ConfirmHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item >= 0 && g_IsBanning[ id ] )
    {
        switch( item )
        {
            case 0:
            {
                if( check_bit( bIsOffBan, id ) )
                    OffBanMenu( id );
                else
                    OpenMainMenu( id );
            }
            case 1: 
                menu_display( id, g_ReasonsMenu );
            case 2: 
                menu_display( id, g_BanTimesMenu );
            case 3: 
            {
                new time;
                if( check_bit( bIsUsingCustomTime, id ) )
                    time = g_isBanningTime[ id ];
                else if( check_bit( bIsUsingBanReasonTime, id ) )
                    time = g_ReasonBanTimes[ g_isBanningTime[ id ] ];
                else
                    time = iBanTimes[ g_isBanningTime[ id ] ];
                
                if( check_bit( bIsOffBan, id ) )
                    BanPlayer( id, -(g_IsBanning[ id ] - 1), time, g_isBanningReason[ id ] );
                else
                    BanPlayer( id, find_player( "k", g_IsBanning[ id ] ), time, g_isBanningReason[ id ] );  
                
                clear_bit( bIsUsingCustomTime, id );
                clear_bit( bIsUsingBanReasonTime, id );
                clear_bit( bIsOffBan, id );
                g_IsBanning[ id ] = 0;
                g_isBanningTime[ id ] = 0;
                g_isBanningReason[ id ][ 0 ] = 0;
            }
        }   
    }
    else
    {
        clear_bit( bIsUsingBanReasonTime, id );
        clear_bit( bIsUsingCustomTime, id );
        clear_bit( bIsOffBan, id );
        g_IsBanning[ id ] = 0;
        g_isBanningTime[ id ] = 0;
        g_isBanningReason[ id ][ 0 ] = 0;
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

public CmdOffBanMenu( id, level, cid )
{
    if( cmd_access( id, level, cid, 0 ) )
    {
        clear_bit( bIsUsingBanReasonTime, id );
        clear_bit( bIsUsingCustomTime, id );
        clear_bit( bIsOffBan, id );
        g_IsBanning[ id ] = 0;
        g_isBanningTime[ id ] = 0;
        g_isBanningReason[ id ][ 0 ] = 0;
        OffBanMenu( id );
    }
    
    return PLUGIN_HANDLED;
}
public OffBanMenu( id )
{
    new menuid = menu_create( "OffBan Menu", "OffBanHandler" );

    new max = ArraySize( hOffBanName );

    for( new i; i < max; i++ )
    {
        menu_additem( menuid, fmt( "%a", ArrayGetStringHandle( hOffBanName, i ) ) );
    }
    menu_display( id, menuid, _, 10 );
}

public OffBanHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item >= 0 )
    {
        set_bit( bIsOffBan, id );
        g_IsBanning[ id ] = item + 1;
        if( g_isBanningReason[ id ][ 0 ] )
            ConfirmMenu( id );
        else
            menu_display( id, g_ReasonsMenu );
    }
    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

public CmdReason( id )
{
    if( !g_IsBanning[ id ] )
        return PLUGIN_HANDLED;
    
    read_args( g_isBanningReason[ id ], MAX_REASON_LENGTH - 1 );
    remove_quotes( g_isBanningReason[ id ] );
    trim( g_isBanningReason[ id ] );
    clear_bit( bIsUsingBanReasonTime, id );
    if( !g_isBanningReason[ id ][ 0 ] )
        client_cmd( id, "messagemode _reason_" );
    else
        menu_display( id, g_BanTimesMenu );
    return PLUGIN_HANDLED;
}

public BanLengthHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item >= 0 && g_IsBanning[ id ] )
    {
        if( item == 0 )
            client_cmd( id, "messagemode _ban_length_" );
        else
        {
            clear_bit( bIsUsingCustomTime, id );
            clear_bit( bIsUsingBanReasonTime, id );
            g_isBanningTime[ id ] = item - 1;
            ConfirmMenu( id );
        }
    }
    else
    {
        g_IsBanning[ id ] = 0;
        g_isBanningReason[ id ][ 0 ] = 0;
    }

    return PLUGIN_HANDLED;
}

public CmdBanLength( id )
{
    if( !g_IsBanning[ id ] )
        return PLUGIN_HANDLED;
    
    new time[ 12 ];
    read_args( time, charsmax( time ) );
    remove_quotes( time );
    trim( time );

    set_bit( bIsUsingCustomTime, id );
    g_isBanningTime[ id ] = str_to_num( time );
    ConfirmMenu( id );
    return PLUGIN_HANDLED;
}

stock bool:is_user_steam( id )
{
	static dp_pointer;

	if(dp_pointer || (dp_pointer = get_cvar_pointer("dp_r_id_provider")))
	{ 
		server_cmd("dp_clientinfo %d", id);
		server_exec();
		return (get_pcvar_num(dp_pointer) == 2);
	}

	return false;
}

SQLCheckError( errNum, error[] )
{
    if( errNum )
        log_amx( error );
}

// admin, player, ban_length, ban reason 
public _CBan_BanPlayer( plugin, argc )
{
    if( argc <= 4 )
    {
        log_error( 1, "CBan_BanPlayer needs at least 4 parameters ( %d ).", argc );
        return;   
    }
    new pid = get_param( 2 );
    if( !is_user_connected( pid ) )
    {
        log_error( 1, "CBan_BanPlayer: Player not connected ( %d ).", pid );
        return;
    }
    new ban_length = abs( get_param( 3 ) );
    new ban_reason[ MAX_REASON_LENGTH ];
    get_string( 4, ban_reason, charsmax( ban_reason ) );

    BanPlayer( get_param( 1 ), pid, ban_length, ban_reason );
}
// admin, target[], targetType 
public _CBan_UnbanPlayer( plugin, argc )
{
    if( argc <= 3 )
    {
        log_error( 1, "CBan_BanPlayer needs 3 parameters ( %d ).", argc );
        return;  
    }

    new target[ MAX_NAME_LENGTH ];
    get_string( 2, target, charsmax( target ) );

    UnbanPlayer( get_param( 1 ), target, get_param( 3 ) );
}

// admin, target[], ban_length, ban_reason[]
public _CBan_OffBanPlayer( plugin, argc )
{
    if( argc <= 4 )
    {
        log_error( 1, "CBan_BanPlayer needs at least 4 parameters ( %d ).", argc );
        return 0;
    }
    new target[ MAX_NAME_LENGTH ];
    get_string( 2, target, charsmax( target ) );

    new pid = find_player( "bl", target );
    if( pid && ( get_user_flags( pid ) & ADMIN_FLAG_IMMUNITY ) )
        return 0;
    new bool:isInGame = true;
    if( !pid )
    {
        isInGame = false;
        pid = ArrayFindStringContaini( hOffBanName, target );
        if( pid == -1 )
            return 0;
    }

    new ban_reason[ MAX_REASON_LENGTH ];
    get_string( 4, ban_reason, charsmax( ban_reason ) );
    
    BanPlayer( get_param( 1 ), isInGame? pid:-pid, abs( get_param( 3 ) ), ban_reason );
    return 1;
}

// admin, target[], ban_length, ban_reason
public _CBan_AddBanPlayer( plugin, argc )
{
    if( argc <= 4 )
    {
        log_error( 1, "CBan_BanPlayer needs at least 4 parameters ( %d ).", argc );
        return 0;
    }
    
    new target[ MAX_NAME_LENGTH ];
    get_string( 2, target, charsmax( target ) );
    
    new ban_reason[ MAX_REASON_LENGTH ];
    get_string( 4, ban_reason, charsmax( ban_reason ) );

    new pid = find_player( "cl", target );

    if( !pid )
        pid = find_player( "d", target );

    if( pid )
    {
        if( get_user_flags( pid ) & ADMIN_FLAG_IMMUNITY )
            return 0;
        else
            BanPlayer( get_param( 1 ), pid, abs( get_param( 3 ) ), ban_reason );
    }
    else
        AddBanPlayer( get_param( 1 ), target, abs( get_param( 3 ) ), ban_reason );
    
    return 1;
}

ArrayFindStringContaini( Array:which, const item[] )
{
    new max = ArraySize( which );
    for(new i, val[ MAX_NAME_LENGTH ]; i < max; i++ )
    {
        ArrayGetString( which, i, val, charsmax( val ) );

        if( containi( val, item ) != -1 )
            return i;
    }
    return -1;
}

ArrayFindStringi( Array:which, const item[] )
{
    new max = ArraySize( which );
    for(new i, val[ MAX_NAME_LENGTH ]; i < max; i++ )
    {
        ArrayGetString( which, i, val, charsmax( val ) );

        if( equali( val, item ) )
            return i
    }
    return -1;
}
