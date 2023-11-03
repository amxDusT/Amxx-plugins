/*
    old team_protection, the one UGC has/had.






    ctrl_t = 0 - no team; ctrl_t = 1 - team request; ctrl_t = 2 - teaming 

    v1.8.5 :
        - fixed players not showing in menu (get_players bug) thanks @ahd @< blank >
        - enum for teaming stuff on ctrl_t
        - fixed a bit say check
    v1.8.1 : 
        - fixed error in the native ( style = 1 causes problems )
    v1.8 :
        - rewritten "say" part (more efficient?)
        - removed custom print_color, added cromchat or print_color from 1.9

    v1.7 :
        - fixed various errors with maxplayers
        - myteams command moved to chat instead of console (as console sucks!)
    v1.6.5 :
        - added disable/enable ham fwds to make it more efficient
    v1.6.1 :
        - maybe fix crash? (teamprotection before rush_duel)
    v1.6 : 
        - Support for rush duel with native

    
 */

#include <amxmodx>
#include <amxmisc>
#include <hamsandwich>

#if AMXX_VERSION_NUM < 183
    #define client_disconnected client_disconnect
    #include <cromchat>
#endif

new const VERSION[] = "1.8.5"

#define PREFIX  "[UGC.LT]"


#define TASK_UNTEAM     180399
#define TASK_TIME       031899
#define TASK_ADS        991803


new ctrl_t[ 33 ][ 33 ]  // hold teams and requests
new g_team_i            // count how many teams there are
new bool:g_bInTime      // temp remove teaming if over the cvar time
new pCvarTime
new pCvarAds

enum _:Teaming_Answers  // possible values for ctrl_t
{
    NOTHING = 0,
    REQUEST = 1,
    TEAM = 2,
    PAUSED = 3
}

new HamHook:g_playerKilled
new HamHook:g_traceAttack
new MaxPlayers  //useful for removing teams when someone leaves
public plugin_init(){
    register_plugin("Team Protection", VERSION, "DusT")
    pCvarTime = register_cvar("amx_tremove", "0" ) //time to wait before teams get removed every round.
    pCvarAds = register_cvar("amx_teamads", "300")
    register_cvar( "team_protection", VERSION, FCVAR_SERVER | FCVAR_SPONLY)
    register_clcmd("amx_trem", "editRound", ADMIN_LEVEL_A, "< time > - time before teams auto stop" ) //mods+

    register_clcmd("team_menu", "teamMenu")
    register_clcmd("say /myteams", "ShowMyTeams")
    register_clcmd("say", "SayTeam")
    register_clcmd("unteam", "unTeam", _, "Usage: unteam <nick you're teaming with>" )
    register_clcmd("showteams", "ShowTeams", _, " - Show teamlist") // for normal admins
    //register_srvcmd("showteams","ShowTeams")
    register_clcmd("say /teaminfo", "TeamInfo")
    g_traceAttack = RegisterHam(Ham_TraceAttack, "player", "Forward_TraceAttack");
    g_playerKilled = RegisterHam(Ham_Killed, "player", "fwd_Ham_Killed_post", 1);  
    DisableHamForward( g_traceAttack )
    DisableHamForward( g_playerKilled )
    register_logevent("RoundEnd", 2 , "1=Round_End")
    register_logevent("RoundStart", 2 , "0=World triggered", "1=Round_Start")
    g_bInTime = true;
    if(get_pcvar_num(pCvarAds))
        set_task(get_pcvar_float(pCvarAds), "ShowAds", TASK_ADS, _, _, "b")
    MaxPlayers = get_maxplayers()
}
public plugin_natives(){

    register_native("kf_pause_teaming", "_pause_teaming")   // useful to block teaming in certain situations, like rush_duel. 

}


public ShowAds(){
    client_print_color(0, print_team_red, "^4%s Want to team with your friends? ^3say /team", PREFIX)
    client_print_color(0, print_team_red, "^4%s You can see your teams with ^3say /myteams^4", PREFIX)
}

//loop through all possible players and check if there is any team or request and print
public ShowMyTeams( id ){
    new List[256], ReqList[256]

    for(new i=1; i < MaxPlayers; i++){
        if(ctrl_t[ id ][ i ] == TEAM){
            format(List, charsmax(List), "%s%s%s", List, strlen(List)? ", ":"", GetUserNameReturned( i ))
        }
    }
    client_print(id, print_chat, "Your Team List: %s", strlen(List)? List:"N/A")
    
    for(new i=0; i < MaxPlayers; i++){
        if(ctrl_t[ i ][ id ] == REQUEST)
            format(ReqList, charsmax(ReqList), "%s%s%s", ReqList, strlen(ReqList)? ", ":"", GetUserNameReturned( i ))
    }
    client_print( id, print_chat, "Your Request List: %s", strlen(ReqList)? ReqList:"N/A")
    
    return PLUGIN_HANDLED
}
// "easter egg"
public TeamInfo( id ){
    client_print_color(id, print_team_red, "^4Made with love by DusT <3")
    client_print_color(id, print_team_red, "^4Special thanks to blank, glhf and Here Justitia!")
    client_print_color(id, print_team_red, "^4Shoutout to smmallie, MOCOLONI, Lovell, Aly (just because her b-day), pavel")
    client_print_color(id, print_team_red, "^4Made for ^1UGC-Gaming.NET")
}

// if teaming, block it and show message
public Forward_TraceAttack(iVictim, iKiller, Float:dmg, Float:dir[3], tr, dmgbit)
{ 
    //client_print(0, print_chat, "iKiller : %i    iVictim: %i", iKiller, iVictim)
    if((ctrl_t[iKiller][iVictim] == TEAM || ctrl_t[iVictim][iKiller] == TEAM) && g_bInTime && get_user_team(iVictim)!=get_user_team(iKiller)) {
        client_print_color( iKiller, print_team_red, "^4%s ^1You can't kill %s. Say ^"/unteam %s^" to stop teaming.", PREFIX, GetUserNameReturned(iVictim), GetUserNameReturned(iVictim))
        return HAM_SUPERCEDE;
    }  
    return HAM_IGNORED;
}

public fwd_Ham_Killed_post(){
    //check if there are people teaming. if there are, checks whether those are only ones alive. 
    teamChecker();
    return HAM_HANDLED
}

public teamChecker(){
    static players[ 32 ], iNum
    get_players(players, iNum, "ac")
    //more than 1 player and check if team already removed
    if(iNum < 2 || !g_bInTime ){
        return PLUGIN_HANDLED
    }
    //check if players are from same team
    new numT, numCT
    for(new i = 0; i < iNum; i++){
        if(get_user_team(players[i]) == 1)
            numT++
        else if(get_user_team(players[i]) == 2)
            numCT++
    }
    if(iNum == numT || iNum == numCT)
        return PLUGIN_HANDLED

    //check if all alive players are teaming    
    for(new i = 0; i < iNum - 1; i++ ){
        for(new j = i + 1; j < iNum; j++ ){
            if(ctrl_t[ players[ i ] ][ players[ j ] ] != TEAM && get_user_team( players[ i ] ) != get_user_team( players[ j ] ) ){
                return PLUGIN_HANDLED
            }
        }
    }
    
    tmpUnteam()
    return PLUGIN_HANDLED
}

public client_disconnected( id ){
    stopTeam( id )
} 
public stopTeam( id ){
    for(new i = 1;i < MaxPlayers;i++)
    {
        if(ctrl_t[id][i] && ctrl_t[i][id])
            g_team_i--
        ctrl_t[ id ][ i ] = NOTHING
        ctrl_t[ i ][ id ] = NOTHING
	}
    // if no teams active, disable these forwards to make more efficient.
    if(g_team_i <= 0){
        DisableHamForward( g_playerKilled )
        DisableHamForward( g_traceAttack )
    }
}

public stopSpecificTeam (pars[]){
    remove_task(TASK_UNTEAM)
    new id = pars[0]
    new target = pars[1]
    //client_print(0, print_chat, "working %s %s", GetUserNameReturned(id),GetUserNameReturned(target) )
    client_print_color( target, print_team_red, "^4%s ^3Team with %s over!", PREFIX, GetUserNameReturned( id ))
    client_print_color( id, print_team_red, "^4%s ^3Team with %s over!", PREFIX, GetUserNameReturned( target ))
    ctrl_t[ id ][ target ] = NOTHING
    ctrl_t[ target ][ id ] = NOTHING
    g_team_i--
    if(g_team_i <= 0){
        DisableHamForward( g_playerKilled )
        DisableHamForward( g_traceAttack )
    }
}


public unTeam( id, type ){
    new players = type 
    if(!players){
        new zArgv[ 32 ]
        read_argv ( 1, zArgv, sizeof( zArgv ) - 1 )
        players = cmd_target(id, zArgv, CMDTARGET_NO_BOTS)
    }
        
    if(ctrl_t[ players ][ id ] >= TEAM && players != id && players != 0){
        new pars[2]
        pars[0] = players
        pars[1] = id
        // 2 seconds delay to let player understand what's going on.
        set_task(2.0, "stopSpecificTeam", TASK_UNTEAM, pars, 2 )
        //stopSpecificTeam(id, i)
        client_print_color( id, print_team_red, "^4%s ^3Your team with %s will end in 2 seconds", PREFIX, GetUserNameReturned( players ))
        client_print_color( players, print_team_red, "^4%s ^3Your team with %s will end in 2 seconds", PREFIX, GetUserNameReturned( id ))
        return PLUGIN_HANDLED
    
    }
    client_print_color( id, print_team_red, "^4%s ^1Player not found or you are not teaming with him", PREFIX )
    return PLUGIN_HANDLED
    
}
public unteamMenu( id ){
    static menuid, menu[64]
    menuid = menu_create("Unteam Menu", "unteamHandler")
    new pl[32], num, bool:hasOne, tmp, buffer[2]
    buffer[1] = 0
    get_players(pl, num)
    for(new i = 0; i < num; i++){
        tmp = pl[i]
        if(ctrl_t[id][tmp] >= TEAM || ctrl_t[tmp][id] >= TEAM){
            hasOne = true
            formatex(menu, charsmax(menu), "%s", GetUserNameReturned(tmp))
            buffer[0] = tmp
            menu_additem(menuid, menu, buffer)
        }
    }
    if(!hasOne){
        client_print_color( id, print_team_red, "^4%s ^1No players to unteam with", PREFIX )
        return PLUGIN_HANDLED
    }
    menu_display(id, menuid, 0)
    return PLUGIN_HANDLED    
}
public unteamHandler( id, menuid, item){
    if(!is_user_connected(id) || item == MENU_EXIT){
        menu_destroy(menuid)
        return PLUGIN_HANDLED 
    }
    new dummy, buffer[2], playerid
    menu_item_getinfo(menuid, item, dummy, buffer, charsmax(buffer), _, _, dummy)
    playerid = buffer[0]
    if(ctrl_t[id][playerid] == TEAM || ctrl_t[playerid][id] == TEAM)
        unTeam(id, playerid)
    return PLUGIN_HANDLED
}

public SayTeam( id )
{
    new zArgv[ 196 ], arg1[ 32 ], arg2[ 32 ]
    read_argv ( 1, zArgv, charsmax(zArgv) )
    parse(zArgv,arg1, charsmax(arg1), arg2, charsmax(arg2))
    if(equali(arg1, "/team") || equali(arg1, "/tm") || equali(arg1, "team") || equali(arg1, "tm") ){
        //parse(zArgv,arg1, charsmax(arg1), arg2, charsmax(arg2))

        if(!strlen(arg2)){
            teamMenu( id )
            return PLUGIN_HANDLED
        }

        new players = cmd_target(id, arg2, CMDTARGET_NO_BOTS)
        if( players && !ctrl_t[ players ][ id ] && players != id){
            ctrl_t[ players ][ id ] = REQUEST;
            if(ctrl_t[ id ][ players ])
                DoneTeam( id, players )
            else 
                ShowRequest( id, players );
            
        }
        
        return PLUGIN_HANDLED
    }
    else if(equali(arg1, "/unteam") || equali(arg1, "unteam")){
        //parse(zArgv,arg1, sizeof( arg1 ) -1, arg2, sizeof( arg1 ) -1)
        if(!strlen(arg2)){
            unteamMenu( id )
            return PLUGIN_HANDLED
        }
        new players = cmd_target(id, arg2, CMDTARGET_NO_BOTS)
        if(players)
            unTeam( id, players )
        //client_cmd(id , "unteam %s", arg2)
        return PLUGIN_HANDLED
    }
    else if(containi(zArgv, "steam") == -1 && containi(zArgv, "team") != -1 && containi(zArgv, "unteam") == -1){
        client_print_color( id, print_team_red, "^4%s ^1Want to team with your friends? ^3say /team", PREFIX )
    }
    return PLUGIN_CONTINUE
}

public teamMenu( id ){
    new ids[ 32 ], iNum, bool:hasTeams
    get_players( ids, iNum, "c" )
    
    static menuid, buffer[2]
    static szMenu[ 64 ]
    formatex( szMenu, charsmax( szMenu ), "\rTeam Menu^n")
    menuid = menu_create(szMenu, "MenuPlayer")
    for(new i = 0, pid; i < iNum; i++){
        pid = ids[i]
        // if players are on different team and they're not teaming (and you havemt sent them request already) and teams are not paused by native
        if(get_user_team(id) != get_user_team(pid) && !ctrl_t[ pid ][ id ] && ctrl_t[ pid ][ id ] != PAUSED){
            
            hasTeams = true // to say that at least one player is shown
            formatex( szMenu, charsmax( szMenu ), "\w %s %s", GetUserNameReturned( pid ), ctrl_t[ id ][ pid ]? "\r[ ASKED YOU ]":"")
            buffer[0] = pid
            buffer[1] = 0
            menu_additem(menuid, szMenu, buffer)
        }
    }
    if(!hasTeams){
        client_print_color( id, print_team_red, "^4%s ^1There are no players to team with.", PREFIX )
        return PLUGIN_HANDLED
    }
    menu_display(id, menuid, 0)
    return PLUGIN_HANDLED
}

public MenuPlayer( id, hMenu, item )
{
    if( !is_user_connected( id ) ){
        menu_destroy(hMenu)
        return PLUGIN_HANDLED
    }
    if( item == MENU_EXIT )
    {
        menu_destroy( hMenu );  
        return PLUGIN_HANDLED
    }
    
    static buffer[2], dummy, playerid
    menu_item_getinfo(hMenu, item, dummy, buffer, charsmax(buffer), _, _, dummy)
    playerid = buffer[0]

    menu_destroy( hMenu );
    
    if( !is_user_connected( playerid ) )
    {
        client_print_color(id, print_team_red, "^4%s Player is no longer connected.", PREFIX );
        teamMenu( id );
    }
    else
    {
        //g_playerID = id;
        ctrl_t[ playerid ][ id ] = REQUEST;
        if(ctrl_t[ id ][ playerid ] == REQUEST)
            DoneTeam( id, playerid )
        else 
            ShowRequest( id, playerid );
    }
    return PLUGIN_HANDLED
}

public ShowRequest( id, iTarget )
{
    client_print_color(id, print_team_red, "^4%s ^3Request successfully sent to %s. Wait his response", PREFIX, GetUserNameReturned( iTarget ));
    set_hudmessage( 255, 255, 255, -1.0, -1.0, 1, 0.0, 0.0, 4.0, 0.0, -1 );
    if( !is_user_bot( iTarget ) )
    {
        client_print_color( iTarget, print_team_red, "^4%s ^3%s wants to team with you. To accept write /team and choose him", PREFIX, GetUserNameReturned( id ) );
               
        show_hudmessage( iTarget, "%s wants to team with you. To accept write /team and choose him", GetUserNameReturned( id ) )
        showRequestMenu( iTarget, id )
    }
}

public showRequestMenu( id, player ){
    static menuid, buffer[2]
    static szMenu[ 128 ]
    formatex( szMenu, charsmax( szMenu ), "\y%s \rwants to team with you! Accept?^n", GetUserNameReturned(player))
    menuid = menu_create(szMenu, "showRequestMenuHandler")
    buffer[0] = player
    buffer[1] = 0
    menu_additem(menuid, "Yes", buffer)
    menu_additem(menuid, "No", buffer)

    menu_display(id, menuid, 0)
    return PLUGIN_HANDLED
}
public showRequestMenuHandler( id, menuid, item ){
    if (!is_user_connected(id) || item == MENU_EXIT)
	{
		menu_destroy(menuid)
		return PLUGIN_HANDLED
	}
    static buffer[2], dummy, playerid
    menu_item_getinfo(menuid, item, dummy, buffer, charsmax(buffer), _, _, dummy)
    playerid = buffer[0]
    if( item == 0 )
        DoneTeam( id, playerid )
    menu_destroy(menuid)
    return PLUGIN_HANDLED
}
public DoneTeam( id, iTarget )
{
    ctrl_t[ id ][ iTarget ] = TEAM
    ctrl_t[ iTarget ][ id ] = TEAM
    if(!g_team_i){
        EnableHamForward( g_playerKilled )
        EnableHamForward( g_traceAttack )
    }
    g_team_i++
    client_print_color( 0, print_team_red, "^4%s ^3 %s and %s are now teaming", PREFIX, GetUserNameReturned( id ), GetUserNameReturned( iTarget ) )
    teamChecker()
}

public ShowTeams( id ){
    client_print( id, print_console, "Current Teaming list: ")
    for(new i=0; i < MaxPlayers; i++){
        for(new j=i; j < 32; j++){
            if(ctrl_t[ i ][ j ] == TEAM  )
                client_print( id, print_console, "%s | %s", GetUserNameReturned( i ), GetUserNameReturned( j ))
        }
    }
    client_print( id, print_console, "")
    if(!(get_user_flags(id) & ADMIN_LEVEL_A))
        return PLUGIN_HANDLED
    client_print( id, print_console, "Current Request List: ")
    for(new i=0; i < MaxPlayers; i++){
        for(new j=0; j < 32; j++){
            if(ctrl_t[ i ][ j ] == REQUEST )
                client_print( id, print_console, "%s > %s", GetUserNameReturned( j ), GetUserNameReturned( i ))
        }
    }
    client_print( id, print_console, "" )
    
    return PLUGIN_HANDLED
}

GetUserNameReturned( id )
{
    new szName[ 32 ];
    get_user_name( id, szName, charsmax( szName ) );
    return szName;
}


public RoundEnd(){
    g_bInTime = false;
    remove_task(TASK_TIME)
}

public tmpUnteam(){
    g_bInTime = false;
    client_print_color( 0, print_team_red,"^4%s ^1Teams removed for this round!", PREFIX)
    //remove_task(TASK_TIME)
}

public RoundStart(){
    g_bInTime = true;
    if(get_pcvar_num(pCvarTime))
        set_task(get_pcvar_float(pCvarTime), "tmpUnteam", TASK_TIME)
        
    teamChecker()
}
public editRound( id, level, cid ){
	if(!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED
	new zArgv[8];
	read_argv( 1, zArgv, sizeof ( zArgv ) - 1 );
	if( !equal( zArgv, "" ))
	{
		server_cmd("amx_tremove %i", str_to_num(zArgv))
	}
	return PLUGIN_HANDLED
}


// pause_teaming( player1, player2, unpause = 0)
// unpause = 1, re-adds team if they had it.
// unpause = 0, removes team even if it shows they have.
public _pause_teaming( plugin, argc ){
    new id = get_param(1), id2 = get_param(2), type = get_param(3)
    if(ctrl_t[id][id2] == TEAM + type || ctrl_t[id2][id] == TEAM + type){
        ctrl_t[id][id2] = PAUSED - type
        ctrl_t[id2][id] = PAUSED - type
    }
}
