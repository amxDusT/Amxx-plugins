/*
    send request for nick reg from in-game
*/
#include < amxmodx >
#include < sqlx >
#include < regex >

new Handle:tuple;
native is_user_registered( id );
new const szPrefix[] = "^4[AMXNICKS]^1";
#define MIN_EMAIL_LENGTH            5
#define MIN_PASS_LENGTH             5
#define MAX_EMAIL_LENGTH            64
#define MAX_PASS_LENGTH             64
public plugin_init()
{
    register_plugin( "Nick registration", "1.0.1", "DusT" );
    register_clcmd( "say", "CmdSay" );
    tuple = SQL_MakeDbTuple( "127.0.0.1", "dust", "", "amx_knf" );
}

public plugin_cfg()
{
    set_task( 0.1, "SQL_Init" );
}
public plugin_end()
{
    SQL_FreeHandle( tuple );
}
public SQL_Init()
{
    new query[ 512 ];
    formatex( query, charsmax( query ), "CREATE TABLE IF NOT EXISTS `nickreg_request`(\
        id INT NOT NULL AUTO_INCREMENT,\
        name VARCHAR(63) NOT NULL UNIQUE,\
        steamid VARCHAR(30) NOT NULL UNIQUE,\
        ip VARCHAR(20) NOT NULL UNIQUE,\
        email VARCHAR(128) NOT NULL UNIQUE,\
        password VARCHAR(128) NOT NULL,\
        PRIMARY KEY (id));");
    
    SQL_ThreadQuery( tuple, "IgnoreHandle", query );
}
public IgnoreHandle( failState, Handle:query, error[], errNum )
    if( errNum )    set_fail_state( error );

public CmdSay( id )
{
    new args[ 192 ], cmd[10];
    read_args( args, charsmax( args ) );
    remove_quotes( args ), trim( args );
    strtok2( args, cmd, charsmax( cmd ), args, charsmax( args ), ' ', TRIM_FULL );
    if( equali( cmd, "/reg" ) || equali( cmd, "!reg" ) )
    {
        if( is_user_registered( id ) )
        {
            client_print_color( id, print_team_red, "%s Your nick is already registered!", szPrefix );
            return PLUGIN_HANDLED;
        }

        new email[ 100 ], password[ 64 ];
        strtok2( args, email, charsmax( email ), password, charsmax( password ), ' ', TRIM_FULL );
        remove_quotes( email ); remove_quotes( password );
        if( !email[ 0 ] || !password[ 0 ] )
        {
            client_print_color( id, print_team_red, "%s Usage: /reg < email > < in-game password > (EG: ^4/reg dust.pro@gmail.com dust123^1)", szPrefix );
            return PLUGIN_HANDLED;
        }

        if( strlen( email ) <= MIN_EMAIL_LENGTH )
        {
            client_print_color( id, print_team_red, "%s Email is too short.", szPrefix );
            return PLUGIN_HANDLED;
        }
        if( strlen( password ) <= MIN_PASS_LENGTH )
        {
            client_print_color( id, print_team_red, "%s Password is too short.", szPrefix );
            return PLUGIN_HANDLED;
        }

        static Regex:rEmail;
        if( !rEmail )
            rEmail = regex_compile( "^^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$", _, _, _, "i" );
        
       
        if( regex_match_c( email, rEmail ) == 0 )
        {
            client_print_color( id, print_team_red, "%s Invalid Email.", szPrefix );
            return PLUGIN_HANDLED;
        }
        SendRegRequest( id, email, password );
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

SendRegRequest( id, const email[], const pass[] )
{
    new userip[ MAX_IP_LENGTH ], userid[ MAX_AUTHID_LENGTH ], username[ MAX_NAME_LENGTH * 2 ];
    new escEmail[ MAX_EMAIL_LENGTH * 2 ], escPass[ MAX_PASS_LENGTH * 2 ];

    get_user_ip( id, userip, charsmax( userip ), 1 );
    get_user_authid( id, userid, charsmax( userid ) );
    SQL_QuoteStringFmt( Empty_Handle, username, charsmax( username ), "%n", id );
    SQL_QuoteString( Empty_Handle, escPass, charsmax( escPass ), pass );
    SQL_QuoteString( Empty_Handle, escEmail, charsmax( escEmail ), email );

    new query[ 512 ], data[ 1 ]; data[ 0 ] = get_user_userid( id );
    formatex( query, charsmax( query ), "INSERT IGNORE INTO `nickreg_request` VALUES (NULL,'%s','%s','%s','%s','%s');", username, userid, userip, escEmail, escPass );
    SQL_ThreadQuery( tuple, "CheckAffectedRows", query, data, sizeof data );
}

public CheckAffectedRows( failState, Handle:query, error[], errNum, data[], dataSize )
{
    if( errNum )
        set_fail_state( error );
    
    new id = find_player( "k", data[ 0 ] );
    if( !id )
        return;
    if( !SQL_AffectedRows( query ) )
        client_print_color( id, print_team_red, "%s Couldn't insert your request. You may have requested a registration already!", szPrefix );
    else
        client_print_color( id, print_team_red, "%s Request ^4successfully^1 sent. We will check and register! Please wait max 24hrs.", szPrefix );
}