/*

    get 100hp if hs
*/
#include < amxmodx >
#include < reapi >


native is_mix();
//#define DEBUG
#define FULL_HP    100

new pActive, pScreenFade;
#if defined DEBUG
new Float:fxTime, Float:holdTime;
#endif
public plugin_init()
{
    register_plugin( "100HP if HeadShot", "1.0", "DusT" );
    register_event_ex( "DeathMsg", "@OnDeath", RegisterEvent_Global, "3>0" );
    bind_pcvar_num( create_cvar( "full_hp_on_hs", "1", _, "You get full HP if you do headshot (not in MIX)", true, 0.0, true, 1.0 ), pActive );
    bind_pcvar_num( create_cvar( "fhos_screenfade", "1", _, "Make screen green when getting HP from HS", true, 0.0, true, 1.0 ), pScreenFade );

    #if defined DEBUG
    register_clcmd( "say /testhp1", "CmdTesti" );
    register_clcmd( "say /testhp", "CmdTest" );
    bind_pcvar_float( create_cvar( "fhos_fxtime", "1", _, "" ), fxTime );
    bind_pcvar_float( create_cvar( "fhos_holdtime", "0.3", _, "" ), holdTime );

    #endif
}

#if defined DEBUG
public CmdTesti( id )
{
    set_entvar( id, var_health, 1.0 );
    return PLUGIN_HANDLED;
}
public CmdTest( id )
{
    set_entvar( id, var_health, float(FULL_HP) );
    UTIL_ScreenFade( id, fxTime, holdTime );
    return PLUGIN_HANDLED;
}
#endif

@OnDeath()
{
    new id = read_data( 1 );
    if( pActive && !is_mix() && is_user_alive( id ) && get_user_health( id ) < FULL_HP )
    {
        set_entvar( id, var_health, float(FULL_HP) );
        if( pScreenFade )
            UTIL_ScreenFade( id, 0.7 );
    }
}

stock UTIL_ScreenFade(const player, const Float:fxTime = 1.0, const Float:holdTime = 0.3, const color[3] = {34, 200, 0}, const alpha = 75) {

    const FFADE_IN = 0x0000;
    static MsgIdScreenFade;
    if( !MsgIdScreenFade )
        MsgIdScreenFade = get_user_msgid("ScreenFade");
        
    message_begin(MSG_ONE_UNRELIABLE, MsgIdScreenFade, .player = player);
    write_short(FixedUnsigned16(fxTime));
    write_short(FixedUnsigned16(holdTime));
    write_short(FFADE_IN);
    write_byte(color[0]);
    write_byte(color[1]);
    write_byte(color[2]);
    write_byte(alpha);
    message_end();
}

stock FixedUnsigned16(Float:value, scale = (1 << 12)) {
	return clamp(floatround(value * scale), 0, 0xFFFF);
}