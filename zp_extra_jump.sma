#include <amxmodx>
#include <zombieplague>
#include <zombieamxdust>

#if AMXX_VERSION_NUM < 183
	#define client_disconnected client_disconnect
#endif




new g_jump_item
new bool:g_hasJump[ 33 ]

new cvar_cost_jump


public plugin_init(){
    register_plugin("[ZP] Extra Slots", "1.0", "DusT")
    cvar_cost_jump = register_cvar("zp_buy_jump", "20")
    g_jump_item = zp_register_extra_item("Extra Jump", get_pcvar_num(cvar_cost_jump), ZP_TEAM_HUMAN & ZP_TEAM_ZOMBIE)
    register_event("HLTV", "roundStart", "a", "1=0", "2=0")
}
public roundStart(){
    static ps[32], num
    get_players(ps, num)
    for(new i = 0, id; i < num; i++){
        id = ps[i]
        if(g_hasJump[id]){
            g_hasJump[id] = false
            zp_add_user_jump(id, -1)
        }
    }
}

public zp_extra_item_selected(id,itemid){
    if(itemid == g_jump_item){
        if(!g_hasJump[id] && !(get_user_flags(id) & ADMIN_RESERVATION)){
            zp_add_user_jump(id, 1)
            g_hasJump[id] = true
            client_print(id, print_chat, "You just bought 1 extra jump")
        }
        else{
            client_print(id, print_chat, "%s", g_hasJump[id]? "You already bought an extra jump.":"Only non-vips can buy. Use vipmenu for extra jump")
            zp_set_user_ammo_packs(id, zp_get_user_ammo_packs(id)+get_pcvar_num(cvar_cost_jump))
        }
    }
}

public client_disconnected( id ){
    if(g_hasJump[id])
        zp_add_user_jump(id, -1)
    g_hasJump[ id ] = false
}
