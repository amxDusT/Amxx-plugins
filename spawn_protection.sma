/*
    automatic protection on spawn 
*/
#include < amxmodx >
#include < reapi >



#define KNIFE_DUELS // uncomment if server doesn't have knife duels plugin
#define ASPEC       // uncomment if server doesn't have aspec

#if defined ASPEC
native is_user_aspec( id );
#endif 

#if defined KNIFE_DUELS
#include < kd_duels >
#endif


#define SetBit(%1,%2)      (%1 |= (1<<(%2&31)))
#define ClearBit(%1,%2)    (%1 &= ~(1<<(%2&31)))
#define GetBit(%1,%2)    (%1 & (1<<(%2&31)))

#define TASK_GLOW 9546

new Float:fCvarProtectionTime;
new bool:bCvarGlow;

new bIsProtected;
public plugin_init()
{
    register_plugin( "Spawn Protection", "1.0", "DusT" );

    RegisterHookChain( RG_CBasePlayer_Spawn, "func_PlayerSpawn", true );
    RegisterHookChain( RG_CBasePlayer_TakeDamage, "func_PlayerTakeDamage", false );
    bind_pcvar_float( create_cvar( "sp_time", "1.0", _, "Spawn protection time", true, 0.0 ), fCvarProtectionTime );
    bind_pcvar_num( create_cvar( "sp_glow", "1", _, "If protection, glow effect?", true, 0.0, true, 1.0 ), bCvarGlow );
}

public func_PlayerTakeDamage( victim, inflictor, attacker, Float:damage, dmgbits )
{
    if( victim == attacker || !is_user_connected( attacker ) )
		return HC_CONTINUE;
    
    #if defined KNIFE_DUELS
    if( kd_is_user_in_duel( victim ) != DUEL_NONE )
        return HC_CONTINUE;
    #endif
    if( GetBit( bIsProtected, victim ) )
    {
        SetHookChainReturn( ATYPE_INTEGER, 0 );
        return HC_SUPERCEDE;
    }
    return HC_CONTINUE;
}
public func_PlayerSpawn( id )
{
    if( fCvarProtectionTime >= 0.1 )
        GiveProtection( id );
}
public client_disconnected( id )
{
    RemoveProtection( id );
}

GiveProtection( id )
{
    if( task_exists( id ) )
        remove_task( id );
    
    if( task_exists( id + TASK_GLOW ) )
        remove_task( TASK_GLOW );
    
    if( is_user_bot( id ) )     return;
    if( is_user_aspec( id ) )   return;
    set_task( fCvarProtectionTime, "RemoveProtection", id );
    SetBit( bIsProtected, id );
    if( bCvarGlow )
        set_task( 0.1, "SetGlow", id + TASK_GLOW );
        
}
public SetGlow( id )
{
    id -= TASK_GLOW;
    
    rg_set_rendering( id, _, _, kRenderTransAdd, 100 );
}
public RemoveProtection( id )
{
    if( task_exists( id ) )
        remove_task( id );
    
    if( is_user_bot( id ) ) return;

    if( task_exists( id + TASK_GLOW ) )
        remove_task( id + TASK_GLOW );

    if( GetBit( bIsProtected, id ) )
    {
        ClearBit( bIsProtected, id );
        if( bCvarGlow )
            rg_set_rendering( id );
    }
}

stock rg_set_rendering(id, fx = kRenderFxNone,  color[3] = {255, 255, 255}, render = kRenderNormal, amount = 0)
{
    set_entvar(id, var_renderfx, fx);
    set_entvar(id, var_rendercolor, color);
    set_entvar(id, var_rendermode, render);
    set_entvar(id, var_renderamt, float(amount));
}

stock LogDebug( string[], any:... )
{
    new msg[ 192 ];
    vformat( msg, charsmax( msg ), string, 2 );
    client_print( 0, print_chat, "[debug] %s", msg );
}