#if defined _zpv_vip_included
  #endinput
#endif
#define _zpv_vip_included

/**
* Set extra damage
*/
native zpv_damage_set( id, Float:damage );

/**
* Get extra damage
*/
native Float:zpv_damage_get( id );

/**
* Reset extra damage
*/
native zpv_damage_reset( id );


/**
* Set extra jumps
*/
native zpv_jumps_set( id, jumps );

/**
* Get extra jumps
*/
native zpv_jumps_get( id );

/**
* Reset extra jumps
*/
native zpv_jumps_reset( id );