#include < amxmodx >
#include < zp50_items >
#include < zp50_colorchat_const >
#define LIBRARY_SURVIVOR "zp50_class_survivor"
#include <zp50_class_survivor>
#define LIBRARY_NEMESIS "zp50_class_nemesis"
#include <zp50_class_nemesis>
#define LIBRARY_SNIPER "zp50_class_sniper"
#include <zp50_class_sniper>

#pragma compress 1

enum _:eModes
{
    MODE_NONE       = -10,
    MODE_SURVIVOR   = 0,
    MODE_NEMESIS    = 1,
    MODE_SNIPER     = 2
}
new Float:fShown[ MAX_PLAYERS + 1 ];
new bool:pActive[ eModes ];
public plugin_init()
{
    register_plugin( "[ZP] Disable Extra Items", "1.0", "DusT" );

    bind_pcvar_num( create_cvar( "zp_disabled_survivor", "1", _, 
        "Disable Extra Items menu for survivors", true, 0.0, true, 1.0 ), pActive[ MODE_SURVIVOR ] );
    bind_pcvar_num( create_cvar( "zp_disabled_survivor", "1", _, 
        "Disable Extra Items menu for nemesis", true, 0.0, true, 1.0 ), pActive[ MODE_NEMESIS ] );
    bind_pcvar_num( create_cvar( "zp_disabled_survivor", "1", _, 
        "Disable Extra Items menu for sniper", true, 0.0, true, 1.0 ), pActive[ MODE_SNIPER ] );
    arrayset( fShown, -10.0, sizeof fShown );
}

public zp_fw_items_select_pre( id, itemid, ignorecost )
{
    new ireturn = ZP_ITEM_AVAILABLE;
    if( pActive[ MODE_SURVIVOR ] && LibraryExists(LIBRARY_SURVIVOR, LibType_Library) && zp_class_survivor_get( id ) )
        ireturn = ZP_ITEM_DONT_SHOW;
    else if( pActive[ MODE_NEMESIS ] && LibraryExists(LIBRARY_NEMESIS, LibType_Library) && zp_class_nemesis_get( id ) )
        ireturn = ZP_ITEM_DONT_SHOW;
    else if( pActive[ MODE_SNIPER ] && LibraryExists(LIBRARY_SNIPER, LibType_Library) && zp_class_sniper_get( id ) )
        ireturn = ZP_ITEM_DONT_SHOW;
    
    return ireturn;
}

public module_filter(const module[])
{
	if (equal(module, LIBRARY_SNIPER) || equal(module, LIBRARY_NEMESIS) || equal(module, LIBRARY_SURVIVOR))
		return PLUGIN_HANDLED;
	
	return PLUGIN_CONTINUE;
}
public native_filter(const name[], index, trap)
{
	if (!trap)
		return PLUGIN_HANDLED;
		
	return PLUGIN_CONTINUE;
}
public plugin_natives()
{
	set_module_filter("module_filter")
	set_native_filter("native_filter")
}
