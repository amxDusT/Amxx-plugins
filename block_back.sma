/*
    block backstab attacks
*/

#include < amxmodx >
//#include < fakemeta >
#include < hamsandwich >
#include < reapi >
#include < xs >
#define STAB_RELOAD     1.0
//#define DEBUG
native is_user_in_bridge( id );

new pBlockBackstab;
new pKillBlocker; 
new pAllowReload;
new Float:fpDistance;
new Float:fLastStab[ MAX_PLAYERS + 1 ];
new bool:bProtected[ MAX_PLAYERS + 1 ];
new Float:fCvarAmount;
public plugin_init()
{
    register_plugin( "Backstab Block. Kill Blocker.", "1.1.1", "DusT" );

    RegisterHookChain( RG_CBasePlayer_Killed, "fw_PlayerKilledPost", true );
    RegisterHookChain( RG_CBasePlayer_TakeDamage, "fw_TakeDamage", false );
    RegisterHam( Ham_Weapon_SecondaryAttack, "weapon_knife", "fw_SecondaryAttack", 0 );
    // 0: disaled. 1 - block. 2 - kill both.
    bind_pcvar_num( create_cvar( "amx_backstab", "2", _, _, true, 0.0, true, 2.0), pBlockBackstab );
    bind_pcvar_num( create_cvar( "amx_kill_blocker", "1" ), pKillBlocker );
    bind_pcvar_num( create_cvar( "amx_reload_immunity", "1" ), pAllowReload );
    bind_pcvar_float( create_cvar( "amx_block_distance", "40.0", _,_, true, 32.1, true, 50.0 ), fpDistance );
    bind_pcvar_float( create_cvar( "amx_backstab_value", "0.6", _, _, true, 0.0, true, 1.0 ), fCvarAmount );
}

public fw_SecondaryAttack( ent )
{
    new id = get_member( ent, m_pPlayer );
    fLastStab[ id ] = get_gametime();
    if( bProtected[ id ] )
    {
        bProtected[ id ] = false;
        //client_print( 0, print_chat, "%n removed protection", id );
    }
        
}

public fw_PlayerKilledPost( victim, killer )
{
    if( victim == killer )
        return HC_CONTINUE;
    if( !( 1 <= killer <= 32 ) )
        return HC_CONTINUE;
    
    //client_print( find_player( "c", "STEAM_0:0:92151075" ), print_chat, "%d bridge: %d", pKillBlocker, is_user_in_bridge( victim ) );

    if( pKillBlocker && is_user_in_bridge( victim ) )
    {
        new pid = GetNearestTeammate( victim );

        if( pid && IsBackstab( pid, victim ) )
        {
            user_kill( pid );
            client_print_color( pid, print_team_red, "^4[AMXKNIFE]^1 Blocking is not allowed!" );
        }
    }
    #if defined DEBUG
    client_print( find_player("k","STEAM_0:0:92151075"), print_chat, "Is backstab? %d", IsBackstab( killer, victim ) );
    #endif
    return HC_CONTINUE;
}
public fw_TakeDamage( victim, inflictor, attacker, Float:damage, dmgbits )
{
    if( victim == attacker )
        return HC_CONTINUE;
    if( !( 1 <= attacker <= 32 ) )
        return HC_CONTINUE;
    if( !is_user_connected( attacker ) )
        return HC_CONTINUE;
    if( get_user_team( attacker ) == get_user_team( victim ) )
        return HC_CONTINUE;

    if( pBlockBackstab && ( damage == 18.0 || damage == 146.0 || damage == 195.0 || damage == 243.0 || damage == 81.0 ) && is_user_in_bridge( victim ) ) 
    {
        switch( pBlockBackstab )
        {
            case 1: ScreenFade( attacker );
            case 2: 
            {
                user_kill( victim );
                user_kill( attacker );

            }
        }
        SetHookChainReturn( ATYPE_INTEGER, 0 );
        return HC_SUPERCEDE;
    }
    if( pAllowReload )
    {
        if( is_user_in_bridge( victim ) && bProtected[ victim ] && fLastStab[ victim ] + STAB_RELOAD >= get_gametime() )
        {
            client_print_color( attacker, print_chat, "^4[AMXKNIFE]^1 %n has not reloaded yet. Attack BLOCKED.", victim );
            SetHookChainReturn( ATYPE_INTEGER, 0 );
            return HC_SUPERCEDE;
        }

        if( is_user_in_bridge( attacker ) && fLastStab[ attacker ] + 0.1 >= get_gametime() )
        {
                bProtected[ attacker ] = true;
                //client_print( 0, print_chat, "%n protected", attacker );
        }
    }
    return HC_CONTINUE;
}
public ScreenFade( id )
{
    static msgScreenFade;
    if( msgScreenFade || ( msgScreenFade = get_user_msgid( "ScreenFade" ) ) )
        message_begin( MSG_ONE, msgScreenFade, { 0, 0, 0 }, id ); 
    write_short( 1<<12 ); 
    write_short( 1<<12 );
    write_short( 0x0000 );
    write_byte( 255 ); 
    write_byte( 0 ); 
    write_byte( 0 );
    write_byte( 100 ); 
    message_end(); 
}

GetNearestTeammate( id )
{
    static szTeams[][] = { "", "TERRORIST", "CT", "" };
    new players[ MAX_PLAYERS ], num;
    get_players( players, num, "ache", szTeams[ get_user_team( id ) ] );
    new pid = 0, Float:fDistance = 9999.9, Float:fTemp;
    new Float:fOrigin[ 3 ], Float:fOriginP[ 3 ];
    get_entvar( id, var_origin, fOrigin );
    for( new i, player; i < num; i++ )
    {
        player = players[ i ];
        if( id == player ) continue;
        get_entvar( player, var_origin, fOriginP );
        fTemp = get_distance_f( fOrigin, fOriginP );
        if( fTemp < fDistance )
        {
            fDistance = fTemp;
            pid = player;
        }
    }
    //client_print( find_player( "c", "STEAM_0:0:92151075" ), print_chat, "player: %d distance %.2f", pid, fpDistance );
    if( pid && fDistance <= fpDistance )
        return pid;
    else
        return 0;
}


stock bool:IsBackstab( attacker, victim ) 
{
    new Float:vec1[ 3 ];
    new Float:vec2[ 3 ];
    velocity_by_aim( attacker, 1, vec1 );

    new Float:invlen = xs_rsqrt( vec1[ 0 ] * vec1[ 0 ] + vec1[ 1 ] * vec1[ 1 ] );
    vec1[ 0 ] *= invlen;
    vec1[ 1 ] *= invlen;

    get_entvar( victim, var_angles, vec2 );
    angle_vector( vec2, ANGLEVECTOR_FORWARD, vec2 );
    
    return vec1[ 0 ] * vec2[ 0 ] + vec1[ 1 ] * vec2[ 1 ] > fCvarAmount ? true : false;
}