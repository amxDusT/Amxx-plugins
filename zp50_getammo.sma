/*
	table: map, name, steamid, ip, ammo_received, time_used
	all in sql

*/
#include < amxmodx >
#include < zp50_colorchat_const >
#include < zp50_ammopacks >
#include < sqlx >

new const FREE_AP[][] = {
	"say get",
	"say /get",
	"say_team get",
	"say_team /get"
}
new pType; 
new pDelete;

new Handle:hTuple;

new const host[] = ""; 
new const user[] = "";
new const pass[] = "";	
new const db[]   = "";

new table[] = "zp_getammo";

new szMap[ 64 ];
new Trie:tNames;
new bool:bCanUse;
new pMin,pMax;
public plugin_init() {
	
	register_plugin( "[ZP] Get Ammo SQL", "1.0", "DusT" );
	
	bind_pcvar_num( create_cvar( "zpd_getammo_type", "0", _, "\
		0 - players can use /get every new map^n\
		1+ - players can use /get every 1+ hours.", true, 0.0 ), pType );
	
	bind_pcvar_num( create_cvar( "zpd_getammo_delete", "1", _, "\
		0 - keep the entries, even if expired^n\
		1 - delete all entries that are outdated in the database.", true, 0.0, true, 1.0 ), pDelete );

	bind_pcvar_num( create_cvar( "zpd_getammo_min", "1", _, "Minimun amount a player can get from /get", true, 0.0 ), pMin );
	bind_pcvar_num( create_cvar( "zpd_getammo_max", "50", _, "Max amount a player can get from /get", true, 0.0 ), pMax );

	hTuple = SQL_MakeDbTuple( host, user, pass, db );
	for( new i; i < sizeof FREE_AP; i++ )
		register_clcmd( FREE_AP[i], "CmdGetAmmo" );
	
	register_dictionary( "zp50_getammo.txt" );
}

public OnConfigsExecuted()
{
	get_mapname( szMap, charsmax( szMap ) );

	new query[ 256 ];
	formatex( query, charsmax( query ), "CREATE TABLE IF NOT EXISTS `%s`(\
		id INT NOT NULL AUTO_INCREMENT,\
		map VARCHAR(64) NOT NULL,\
		player_nick VARCHAR(32) NOT NULL,\
		player_steamid VARCHAR(35),\
		player_ip VARCHAR(20),\
		ammo_received INT,\
		time_used INT, PRIMARY KEY(id));", table );
	
	SQL_ThreadQuery( hTuple, "IgnoreHandle", query );

	if( pDelete )
	{
		if( pType )
			formatex( query, charsmax( query ), "DELETE FROM `%s` WHERE `time_used`<=%d;",table, get_systime()-GetHours() );
		else
			formatex( query, charsmax( query ), "DELETE FROM `%s`;", table );

		SQL_ThreadQuery( hTuple, "IgnoreHandle", query );
	}

	tNames = TrieCreate();
	if( pType )
	{
		formatex( query, charsmax( query ), "SELECT `player_nick`,`time_used` FROM `%s` WHERE `time_used`>%d;", table, get_systime()-GetHours() );
		SQL_ThreadQuery( hTuple, "GetData", query );
	}
	else 
		bCanUse = true;
}


public CmdGetAmmo( id )
{
	if( !bCanUse )
	{
		client_print_color( id, id, "%s%l", ZP_PREFIX, "ZP_CMD_NOT_AVAILABLE" );
		return PLUGIN_HANDLED;
	}

	new value, name[ MAX_NAME_LENGTH ];
	get_user_name( id, name, charsmax( name ) );
	strtolower( name );
	new time = get_systime();
	if( TrieGetCell( tNames, name, value ) )
	{
		if( !pType )
		{
			client_print_color( id, id, "%s%l", ZP_PREFIX, "ZP_CMD_CANNOT_USE_MAP" );
			return PLUGIN_HANDLED;
		}

		
		if( value > time - GetHours() )
		{
			client_print_color( id, id, "%s%l %s", ZP_PREFIX, "ZP_CMD_CANNOT_USE_TIME", GetTime( value + GetHours() - time ) );
			return PLUGIN_HANDLED;
		}
	}
	TrieSetCell( tNames, name, time, true );
	new ammo = random_num( pMin, pMax );
	zp_ammopacks_set( id, zp_ammopacks_get( id ) + ammo );
	SetDbEntry( id, time, ammo );
	if( pType )
		client_print_color( id, id, "%s%l %l", ZP_PREFIX, "ZP_AP_RECEIVED", ammo, "ZP_AP_NEXT_TIME", pType );
	else
		client_print_color( id, id, "%s%l %l", ZP_PREFIX, "ZP_AP_RECEIVED", ammo, "ZP_AP_NEXT_MAP");
	return PLUGIN_HANDLED;
}

SetDbEntry( id, time, ammo )
{
	new escName[ MAX_NAME_LENGTH * 2 ], steamid[ 32 ], ip[ MAX_IP_LENGTH ];
	SQL_QuoteStringFmt( Empty_Handle, escName, charsmax( escName ), "%n", id );
	get_user_authid( id, steamid, charsmax( steamid ) );
	get_user_ip( id, ip, charsmax( ip ), true );

	new query[ 256 ];
	formatex( query, charsmax( query ), "INSERT INTO `%s` VALUES(NULL,'%s','%s','%s','%s',%d,%d);", table, szMap, escName, steamid, ip, ammo, time ); 
	SQL_ThreadQuery( hTuple, "IgnoreHandle", query );
}
public GetData( failState, Handle:query, error[], errNum )
{
	if( errNum )
		set_fail_state( error );
	
	new max = SQL_NumResults( query );
	for( new i, name[ MAX_NAME_LENGTH ]; i < max; i++ )
	{
		SQL_ReadResult( query, 0, name, charsmax( name ) );

		strtolower( name );
		TrieSetCell( tNames, name, SQL_ReadResult( query, 1 ) );
	}
	bCanUse = true;
}

GetHours()
{
	return 60*60*pType;
}
GetTime(time)
{
	new hours = time / (60*60);
	time = time % (60*60);
	new minutes = time / 60;
	time = time % 60;

	new msg[ 64 ];
	if( hours > 0 )
		formatex( msg, charsmax( msg ), "%dh", hours );
	if( minutes > 0 )
		format( msg, charsmax( msg ), "%s%dm", msg, minutes );
	if( time > 0 )
		format( msg, charsmax( msg ), "%s%ds", msg, time );
	
	return msg;
}
public IgnoreHandle( failState, Handle:query, error[], errNum )
{
	if( errNum )
		set_fail_state( error );
}