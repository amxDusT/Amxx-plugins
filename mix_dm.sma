/*
    Acer Mix Handler

    
    TODO:
    - top 15 api . 

    1.1:
        - added logs
        - store how many players each mix team has.
*/

#include < amxmodx >
#include < amxmisc >
#include < nvault >
#include < reapi >

#define MAX_ROUNDS 20
#define MIN_ROUNDS 3
#define TASK_CHECKVOTES 1256
#define TASK_CHECKUSERS 2256
new const szCmd[][] = 
{
    "!join",
    "/join"
}

#define set_bit(%1,%2)      (%1 |= (1<<(%2&31)))
#define clear_bit(%1,%2)    (%1 &= ~(1<<(%2&31)))
#define check_bit(%1,%2)    (%1 & (1<<(%2&31)))

new const LOG_FILE[] = "mix_dm.log";
new bool:bIsMix;
new pDefaultRounds;
new Float:pCooldown, Float:pVoteRatio;
new pLogs, pTime;
new iMaxRounds;
new iMenuRounds[ 33 ];

new bIsVoting, iTempRounds;
new Float:fPlayerCooldown[ 33 ];
new iVotes; 
new iVault;
new iNumCT, iNumT;
new iSyncMsg;
new TeamName:iMissingTeam;
new isJoining;
new fwOnMixEnd;
enum _:eMixReasons
{
    ROUNDS_ENDED,
    PLAYER_LEFT,
    ADMIN_QUIT
}

enum _:eParams
{
    PARAM_ID = 0,
    PARAM_TIME,
    PARAM_NAME[MAX_NAME_LENGTH],
    PARAM_EMPTY
}

new bHasJoined;
new pPrefix[MAX_NAME_LENGTH];

public plugin_init()
{
    register_plugin( "(VOTE)MIX", "1.2", "DusT" );

    register_clcmd( "say", "CmdSay" );
    register_clcmd( "say /mix", "CmdEnableMix", ADMIN_BAN );
    register_clcmd( "say /dm", "CmdEnableDm", ADMIN_BAN );
    register_clcmd( "say /mixmenu", "CmdMixMenu", ADMIN_BAN );
    register_clcmd( "mix_menu", "CmdMixMenu", ADMIN_BAN );
    register_clcmd( "say /votemix", "CmdVoteMix" );
    for( new i; i < sizeof szCmd; i++ )
        register_clcmd( fmt( "say %s", szCmd[ i ] ), "CmdJoin" );
    register_clcmd( "mix_ban", "BanVoteMix", ADMIN_BAN, "< steamid | name | #id > - Bans user from votemix" );
    register_clcmd( "mix_unban", "UnbanVoteMix", ADMIN_IMMUNITY, "< steamid | name | #id > - unbans from votemix" );

    //hook_cvar_change(get_cvar_pointer("km_respawn"), "OnCvarChange");

    bind_pcvar_num(create_cvar("mix_stop_after", "20", _, 
        "If someone disconnects while in mix, wait this time before stopping in case someone else joins.^n\
        0: disabled", true, 0.0 ), pTime );
    bind_pcvar_num(create_cvar("mix_default_rounds", "12", _, _, true, float(MIN_ROUNDS), true, float(MAX_ROUNDS) ), pDefaultRounds);
    bind_pcvar_num(create_cvar("mix_log", "2", _, "0: no logs. 1: start, end logs. 2: debug logs.", true, 0.0, true, 2.0 ), pLogs );
    bind_pcvar_float(create_cvar("mix_cooldown", "30" ), pCooldown);
    bind_pcvar_float(create_cvar("mix_vote_ratio", "0.4" ), pVoteRatio);
    bind_pcvar_string(create_cvar("mix_prefix", "[KM]"), pPrefix, charsmax(pPrefix));

    RegisterHookChain( RG_ShowVGUIMenu, "ShowVGUIMenu_Pre" );
    RegisterHookChain( RG_HandleMenu_ChooseTeam, "HandleMenu_ChooseTeam_Pre" );
    RegisterHookChain( RG_RoundEnd, "RoundEnd_Post", true );
    //register_logevent("RoundEnd", 2, "1=Round_End");
                                                    // id, winner, kills, deaths
    fwOnMixEnd = CreateMultiForward( "Mix_OnMixEnd", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL, FP_CELL );

    iSyncMsg = CreateHudSyncObj();
    iVault = nvault_open( "mixdm" );
    AutoExecConfig();
    register_dictionary( "mixdm.txt" );
}

public client_putinserver( id )
{
    set_bit( bHasJoined, id );
}
public plugin_cfg()
{
    arrayset( iMenuRounds, pDefaultRounds, sizeof iMenuRounds );
    arrayset( fPlayerCooldown, -100.0, sizeof fPlayerCooldown );
}

public plugin_natives()
{
    register_native( "is_mix", "_is_mix" );
}

public client_disconnected( id )
{
    if( iMenuRounds[ id ] != pDefaultRounds )
        iMenuRounds[ id ] = pDefaultRounds; 
    
    fPlayerCooldown[ id ] = -100.0;
    if(!check_bit(bHasJoined, id))  return;

    clear_bit(bHasJoined, id);
    
    new TeamName:team = get_member( id, m_iTeam )
    /* if mix or votemix and someone leaves */
    if( ( bIsMix || task_exists( TASK_CHECKVOTES ) ) && TEAM_TERRORIST <= team <= TEAM_CT )
    {
        new tempCT = get_playersnum_ex( GetPlayers_MatchTeam, "CT" );
        new tempT = get_playersnum_ex( GetPlayers_MatchTeam, "TERRORIST" );
        if( team == TEAM_CT )
            tempCT--;
        else
            tempT--;
        /*TODO: check*/
        //console_print( 0, "numct: %d - %d, numt: %d - %d ", iNumCT, tempCT, iNumT, tempT );
        if( ( iNumCT != tempCT || iNumT != tempT ) )
        {
            if( bIsMix )
            {
                if( tempCT == tempT && task_exists( TASK_CHECKUSERS ) )
                    remove_task( TASK_CHECKUSERS );
                else if( task_exists( TASK_CHECKUSERS ) )
                {
                    new name[ MAX_NAME_LENGTH ];
                    get_user_name( id, name, charsmax( name ) );
                    EndMix( id, PLAYER_LEFT, get_member_game( m_iNumCTWins ), get_member_game( m_iNumTerroristWins ), name );
                }   
                else
                {
                    new param[ eParams ];
                    param[ PARAM_ID ] = id;
                    param[ PARAM_TIME ] = pTime;
                    get_user_name( id, param[ PARAM_NAME ], MAX_NAME_LENGTH - 1 );
                    iMissingTeam = (iNumCT>tempCT)? TEAM_CT:TEAM_TERRORIST; 
                    set_task( 0.1, "CheckUsers", TASK_CHECKUSERS, param, sizeof param );
                }
            }

            if( task_exists( TASK_CHECKVOTES ) )
            {
                remove_task( TASK_CHECKVOTES );
                client_print_color( 0, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_FAILED_LEFT" );
                bIsVoting = 0;
            }
        }
    }
}
public CheckUsers( param[], taskid )
{
    if( param[ PARAM_TIME ] >= 1 )
    {
        new const szTeam[][] = { "", "TERRORIST", "CT", "" };
        param[ PARAM_TIME ]--;
        set_hudmessage( 179, 179, 179, -1.0, 0.28, 2, 0.02, 1.0, 0.01, 0.1, 10 );	
        ShowSyncHudMsg(0, iSyncMsg, "%l", "MIX_COUNTDOWN", szTeam[ _:iMissingTeam ], param[ PARAM_TIME ] ); 
        set_task( 1.0, "CheckUsers", taskid, param, eParams );
        if( param[ PARAM_TIME ]%3 == 0 )
        {
            new players[ MAX_PLAYERS ], num;
            get_players_ex( players, num );
            for( new i; i < num; i++ )
            {
                if( !(TEAM_TERRORIST<=get_member(players[i], m_iTeam)<=TEAM_CT) )
                    client_print_color( players[ i ], print_team_red, "^4%s^1 %l", pPrefix, "MIX_JOIN", szCmd[ 0 ] );
            }       
        }
    }
    else
        EndMix( param[ PARAM_ID ], PLAYER_LEFT, get_member_game( m_iNumCTWins ), get_member_game( m_iNumTerroristWins ), param[ PARAM_NAME ] );
}
public CmdJoin( id )
{
    if( !task_exists( TASK_CHECKUSERS ) )
        return PLUGIN_CONTINUE;
    
    if( TEAM_TERRORIST<=get_member(id, m_iTeam)<=TEAM_CT )
        return PLUGIN_CONTINUE;
    
    remove_task( TASK_CHECKUSERS );
    isJoining = id;
    set_member( id, m_bTeamChanged, false );
    engclient_cmd( id, "jointeam", iMissingTeam == TEAM_CT? "2":"1" );
    new iClass[2];
    iClass[0] = random_num( '1', '4' );
    engclient_cmd( id, "joinclass", iClass );
    isJoining = 0;
    return PLUGIN_HANDLED;
}
public _is_mix()
{
    return bIsMix;
}
public RoundEnd_Post()
{
    if (!bIsMix)
        return;

    new scoreCT = get_member_game( m_iNumCTWins );
    new scoreT = get_member_game( m_iNumTerroristWins );

    if ((scoreT >= iMaxRounds || scoreCT >= iMaxRounds) && abs(scoreT - scoreCT) >= 2)
        EndMix( 0, ROUNDS_ENDED, scoreCT, scoreT );
}

StartMix( id, rounds, bool:vote = false )
{
    if( bIsMix )
        return; 
    
    server_cmd("mp_forcerespawn 0");
    server_cmd("mp_round_infinite b");
    server_cmd("mp_auto_join_team 1");
    server_cmd("humans_join_team SPEC");
    server_cmd("sv_restart 1");
    server_exec();

    if( rounds < MIN_ROUNDS )
        rounds = MIN_ROUNDS;
    if( rounds > MAX_ROUNDS )
        rounds = MAX_ROUNDS;

    iMaxRounds = rounds; 
    iNumCT = get_playersnum_ex( GetPlayers_MatchTeam, "CT" );
    iNumT = get_playersnum_ex( GetPlayers_MatchTeam, "TERRORIST" );
    bIsMix = true;
    LogStart( id, rounds, vote );
    if( vote ) 
    {
        client_print_color( 0, print_team_red, "^4%s^1 %l", pPrefix, "MIX_START_VOTEMIX", id, rounds );
    }
    else if( id )
        client_print_color( 0, print_team_red, "^4%s^1 %l", pPrefix, "MIX_START_ADMIN", id, rounds );

}

EndMix( id, reason, scoreCT = 0, scoreT = 0, name[MAX_NAME_LENGTH] = "" )
{
    if( !bIsMix )
        return; 
    
    if( task_exists( TASK_CHECKUSERS ) )
        remove_task( TASK_CHECKUSERS );
    
    server_cmd("mp_forcerespawn 1");
    server_cmd("mp_round_infinite abef");
    server_cmd("mp_auto_join_team 0");
    server_cmd("sv_restart 1");
    server_exec();

    bIsMix = false;
    
    LogEnd( id, reason, scoreCT, scoreT, name );
    switch( reason )
    {
        case ADMIN_QUIT:
        {
            client_print_color( 0, print_team_red, "^4%s^1 %l", pPrefix, "MIX_STOP_ADMIN", id );
        }
        case PLAYER_LEFT:
        {
            client_print_color( 0, print_team_red, "^4%s^1 %l", pPrefix, "MIX_STOP_PLAYER", name );
        }
        case ROUNDS_ENDED:
        {
            new bool:bIsWinnerCT = scoreCT > scoreT? true:false;
            client_print_color( 0, bIsWinnerCT? print_team_blue:print_team_red, "^4%s^1 %l", pPrefix, "MIX_STOP_FINISH", bIsWinnerCT? "CT":"Terrorist", bIsWinnerCT? scoreCT:scoreT, bIsWinnerCT? scoreT:scoreCT );
            new players[ MAX_PLAYERS ], num; 
            get_players( players, num );
            for( new i, player, iDeaths, iKills, TeamName:team, bool:bIsWinner, dummy; i < num; i++ )
            {
                player = players[ i ];
                team = get_member( player, m_iTeam );
                if( !(TEAM_TERRORIST <= team <= TEAM_CT) )     continue;
                
                bIsWinner = ((team==TEAM_CT) == bIsWinnerCT)? true:false;

                iDeaths = get_user_deaths( player ); 
                iKills = get_user_frags( player );
                ExecuteForward( fwOnMixEnd, dummy, player, bIsWinner, iKills, iDeaths );
            }
        }
    }
    
}

public CmdEnableMix( id, level, cid )
{
    if( !cmd_access( id, level, cid, 0, true ) )
    {
        client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "MIX_NO_ACCESS" );
        return PLUGIN_HANDLED;
    }
    if( bIsMix )
    {
        client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "MIX_ALREADY_ACTIVE" );
        return PLUGIN_HANDLED;
    }
    StartMix( id, pDefaultRounds );
    return PLUGIN_HANDLED;   
}
public CmdEnableDm( id, level, cid )
{
    if( !cmd_access( id, level, cid, 0, true ) )
    {
        client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "MIX_NO_ACCESS" );
        return PLUGIN_HANDLED;
    }
    if( !bIsMix )
    {
        client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "MIX_ALREADY_ACTIVE" );
        return PLUGIN_HANDLED;
    }
    EndMix( id, ADMIN_QUIT, get_member_game( m_iNumCTWins ), get_member_game( m_iNumTerroristWins ) );
    return PLUGIN_HANDLED;
}

public CmdSay( id )
{
    new args[ 64 ], cmd[ 6 ], rounds[ 4 ];
    read_args( args, charsmax( args ) );
    remove_quotes( args ); trim( args );
    parse( args, cmd, charsmax( cmd ), rounds, charsmax( rounds ) );
    if( cmd[ 0 ] == '!' || cmd[ 0 ] == '/' )
        copy( cmd, charsmax( cmd ), cmd[ 1 ] );
    
    if( equali( cmd, "mix" ) && is_str_num( rounds ) && !bIsMix && access( id, ADMIN_BAN ) )
    {
        StartMix( id, str_to_num( rounds ) );
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public ShowVGUIMenu_Pre( const id, const VGUIMenu:menuType )
{
    if( (menuType != VGUI_Menu_Team && menuType != VGUI_Menu_Class_CT && menuType != VGUI_Menu_Class_T) /*|| get_member( id, m_bJustConnected )*/ )
        return HC_CONTINUE;

    if( !bIsMix )
        return HC_CONTINUE;

    if( isJoining != id )
        client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "MIX_CHANGE_TEAM" );
    set_member( id, m_iMenu, 0 );
    return HC_SUPERCEDE;
}

public HandleMenu_ChooseTeam_Pre( const id, const MenuChooseTeam:slot )
{
    /*if( get_member( id, m_bJustConnected ) )
        return HC_CONTINUE;*/

    if( !bIsMix )
        return HC_CONTINUE;

    if( isJoining == id )
        return HC_CONTINUE;
    client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "MIX_CHANGE_TEAM" );
    if( TEAM_TERRORIST<=get_member(id, m_iTeam)<=TEAM_CT )
        SetHookChainReturn( ATYPE_INTEGER, 0 );
    else
        SetHookChainArg(2, ATYPE_INTEGER, MenuChoose_Spec );
    return HC_SUPERCEDE;
}

public CmdMixMenu( id, level, cid )
{
    if( !cmd_access( id, level, cid, 0, true ) )
    {
        client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "MIX_NO_ACCESS" );
        return PLUGIN_HANDLED;
    }
    MixMenu( id );
    return PLUGIN_HANDLED;
}

MixMenu( id )
{
    //new menu = menu_create( fmt("\yMix Menu^nCurrently Playing: \w%s", bIsMix? "MIX":"DM" ), "MixMenuHandler" );
    new menu;
    if( bIsMix )
        menu = menu_create( fmt("\yMix Menu^nCurrently Playing: \wMIX^n^nRounds: %d", iMaxRounds ), "MixMenuHandler" );
    else
        menu = menu_create( fmt("\yMix Menu^nCurrently Playing: \wDM^n^nRounds: %d", iMenuRounds[ id ]), "MixMenuHandler" );

    menu_additem( menu, fmt( "\wStart \y%s", bIsMix? "DM":"MIX" ) );
    if( !bIsMix )
    {
        //menu_addtext( menu, fmt( "\wRounds: \y%d^n^n", iMenuRounds[ id ] ), 0 );
        menu_additem( menu, "Add Round" );
        menu_additem( menu, "Remove Round" );
    }
    menu_display( id, menu, 0, 10 );
}

public MixMenuHandler( id, menu, item )
{
    if( is_user_connected( id ) && item >= 0 )
    {
        switch( item )
        {
            case 0: // start mix/dm
            {
                if( bIsMix )
                    EndMix( id, ADMIN_QUIT, get_member_game( m_iNumCTWins ), get_member_game( m_iNumTerroristWins ) );
                else
                {
                    if( get_playersnum_ex( GetPlayers_MatchTeam, "CT" ) != get_playersnum_ex( GetPlayers_MatchTeam, "TERRORIST" ) )
                    {
                        client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_NO_TEAM" );
                        MixMenu( id );
                    }
                    else
                        StartMix( id, iMenuRounds[ id ] );
                }
                    
            }
            case 1: // add round
            {
                if( iMenuRounds[ id ] >= MAX_ROUNDS )
                {
                    client_print_color( id, print_team_red, "Max rounds already reached." );
                }
                else
                    iMenuRounds[ id ]++;
            }
            case 2: // remove round
            {
                if( iMenuRounds[ id ] <= MIN_ROUNDS )
                {
                    client_print_color( id, print_team_red, "Min rounds already reached." );
                }
                else
                    iMenuRounds[ id ]--;
            }
        }
        if( item != 0 )
            MixMenu( id );
    }
    menu_destroy( menu );
    return PLUGIN_HANDLED;
}

StartVote( id )
{
    iTempRounds = iMenuRounds[ id ];
    iNumCT = get_playersnum_ex( GetPlayers_MatchTeam, "CT" );
    iNumT = get_playersnum_ex( GetPlayers_MatchTeam, "TERRORIST" );
    bIsVoting = id;
    iVotes = 1;
    client_print_color( 0, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_VOTE", id, iTempRounds );
    new players[ 32 ], num;
    get_players( players, num );
    for( new i, TeamName:team, player; i < num; i++ )
    {
        player = players[ i ];
        if( player == id )  continue;
        team = get_member( player, m_iTeam );
        if( team == TEAM_CT || team == TEAM_TERRORIST )
            AskVote( player, iTempRounds );
    }
    set_task( 10.0, "CheckVotes", TASK_CHECKVOTES );
}

public AskVote( id, rounds )
{
    new menu = menu_create( fmt( "Play MIX? Rounds: %d", rounds ), "AskHandler" );
    menu_additem( menu, "\wYes" );
    menu_additem( menu, "\rNO" );
    
    menu_display( id, menu, _, 10 );
}
public AskHandler( id, menu, item )
{
    if( is_user_connected( id ) && item == 0 && task_exists( TASK_CHECKVOTES ) )
        iVotes++;
    
    menu_destroy( menu );
    return PLUGIN_HANDLED;
}

public CheckVotes()
{
    new player = bIsVoting;
    bIsVoting = 0;
    if( !CanVotemix( player ) )
    {
        client_print_color( 0, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_NO_REQUIREMENTS" );
        return;
    }
    new numplayers = get_playersnum_ex( GetPlayers_MatchTeam, "CT" ) + get_playersnum_ex( GetPlayers_MatchTeam, "TERRORIST" );
    if ((numplayers == 2 && iVotes != 2) || iVotes / numplayers < pVoteRatio)
    {
        client_print_color( 0, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_NO_PLAYERS" );
        return;
    }
    StartMix( player, iTempRounds, true );
}

public CmdVoteMix( id )
{
    if( !CanVotemix( id, true, true ) )
        return PLUGIN_HANDLED;

    VoteMixMenu( id );
    return PLUGIN_HANDLED;
}

VoteMixMenu( id )
{
    new menu = menu_create( fmt("Votemix Menu^n^n\wRounds: \y%d", iMenuRounds[ id ] ), "VoteMixHandler" );
    menu_additem( menu, "Add Round" );
    menu_additem( menu, "Remove Round^n" );
    menu_additem( menu, "Start Vote" );

    menu_display( id, menu, _, 15 );
}

public VoteMixHandler( id, menu, item )
{
    if( is_user_connected( id ) && item >= 0 )
    {
        switch( item )
        {
            case 0:
            {
                if( iMenuRounds[ id ] >= MAX_ROUNDS )
                    client_print_color( id, print_team_red, "^4%s^1 Max rounds already reached.", pPrefix );
                else
                    iMenuRounds[ id ]++;
            }
            case 1:
            {
                if( iMenuRounds[ id ] <= MIN_ROUNDS )
                    client_print_color( id, print_team_red, "^4%s^1 Min rounds already reached.", pPrefix );
                else
                    iMenuRounds[ id ]--;
            }
            case 2: StartVote( id );
        }
        if( item <= 1 )
            VoteMixMenu( id );
    }
    menu_destroy( menu );
    return PLUGIN_HANDLED;
}

bool:CanVotemix( id, bool:message = false, bool:checkCooldown = false )
{
    new authid[ 32 ];
    get_user_authid( id, authid, charsmax( authid ) );
    if( nvault_get( iVault, authid ) )
    {
        if( message ) 
            client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_BANNED" );
        return false;
    }

    if( bIsMix )
    {
        if( message )
            client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "MIX_ALREADY_ACTIVE" );
        return false;
    }
    if( bIsVoting )
    {
        if( message )
            client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_ALREADY");
        return false;
    }
    if( checkCooldown )
    {
        new Float:fCurr = get_gametime();
        if( fPlayerCooldown[ id ] + pCooldown > fCurr )
        {
            if( message )
                client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_COOLDOWN", fPlayerCooldown[ id ] + pCooldown - fCurr );
            return false;
        }
        fPlayerCooldown[ id ] = fCurr;
    }
    if( get_playersnum_ex( GetPlayers_MatchTeam, "CT" ) != get_playersnum_ex( GetPlayers_MatchTeam, "TERRORIST" ) )
    {
        if( message )
            client_print_color( id, print_team_red, "^4%s^1 %l", pPrefix, "VOTEMIX_NO_TEAM" );
        return false;
    }

    return true;
}

public BanVoteMix( id, level, cid )
{
    if( !cmd_access( id, level, cid, 2 ) )
        return PLUGIN_HANDLED;
    
    new target[ 32 ];
    read_argv( 1, target, charsmax( target ) ); 
    new player = cmd_target( id, target, CMDTARGET_OBEY_IMMUNITY | CMDTARGET_ALLOW_SELF );
    if( !player ) 
        return PLUGIN_HANDLED;

    //reusing target var to store steamid
    get_user_authid( player, target, charsmax( target ) );
    if( !nvault_get( iVault, target ) )
    {
        nvault_set( iVault, target, "1" );
        console_print( id, "Player banned from votemix." );
    }
    else
    {
        console_print( id, "Player is already banned from votemix." );
    }
    return PLUGIN_HANDLED;
}

public UnbanVoteMix( id, level, cid )
{
    if( !cmd_access( id, level, cid, 2 ) )
        return PLUGIN_HANDLED;
    
    new target[ 32 ];
    read_argv( 1, target, charsmax( target ) ); 
    new player = cmd_target( id, target, CMDTARGET_ALLOW_SELF );
    if( !player ) 
        return PLUGIN_HANDLED;
    
    get_user_authid( player, target, charsmax( target ) );
    if( !nvault_get( iVault, target ) )
    {
        console_print( id, "Player is not banned from votemix." );
    }
    else
    {
        nvault_remove( iVault, target );
        console_print( id, "Player unbanned from votemix." );
    }
    return PLUGIN_HANDLED;
}

LogStart( id, rounds, bool:vote )
{
    if( !pLogs )    return; 

    log_to_file( LOG_FILE, "[MIX]%N [ROUNDS]%d [VOTEMIX]%s", id, rounds, vote? "Yes":"No" );
    if( pLogs == 2 )
    {
        new players[ MAX_PLAYERS ], num; 
        new msg[ 512 ], len;
        
        get_players_ex( players, num, GetPlayers_MatchTeam, "CT" );
        len = formatex( msg, charsmax( msg ), "[CT] %d : ^n", num );
        for( new i; i < num; i++ )
        {
            len += formatex( msg[ len ], charsmax( msg ), "- %n^n", players[ i ] );
        }
        log_to_file( LOG_FILE, msg );
        get_players_ex( players, num, GetPlayers_MatchTeam, "TERRORIST" );
        len = formatex( msg, charsmax( msg ), "[T] %d : ^n", num );
        for( new i; i < num; i++ )
        {
            len += formatex( msg[ len ], charsmax( msg ), "- %n^n", players[ i ] );
        }
        log_to_file( LOG_FILE, msg );
    }
    log_to_file( LOG_FILE, "^n===================================^n" );

}

LogEnd( id, reason, scoreCT, scoreT, name[] = "" )
{
    if( !pLogs )    return;
    if( reason== PLAYER_LEFT )
    {
        log_to_file( LOG_FILE, "[ENDMIX] Player Left [PLAYER] %s [SCORE] CT: %d VS T: %d", 
                    name, scoreCT, scoreT );
    }
    else
        log_to_file( LOG_FILE, "[ENDMIX] %s [PLAYER] %n [SCORE] CT: %d VS T: %d", 
        reason==ROUNDS_ENDED?"Finish":"Admin", id, scoreCT, scoreT );
    
    if( pLogs == 2 )
    {
        new players[ MAX_PLAYERS ], num; 
        new msg[ 512 ], len;
        
        get_players_ex( players, num, GetPlayers_MatchTeam, "CT" );
        len = formatex( msg, charsmax( msg ), "[CT] %d : ^n", num );
        for( new i; i < num; i++ )
        {
            len += formatex( msg[ len ], charsmax( msg ), "- %n^n", players[ i ] );
        }
        log_to_file( LOG_FILE, msg );
        get_players_ex( players, num, GetPlayers_MatchTeam, "TERRORIST" );
        len = formatex( msg, charsmax( msg ), "[T] %d : ^n", num );
        for( new i; i < num; i++ )
        {
            len += formatex( msg[ len ], charsmax( msg ), "- %n^n", players[ i ] );
        }
        log_to_file( LOG_FILE, msg );
    }
    log_to_file( LOG_FILE, "^n===================================^n" );
}

public plugin_end()
{
    nvault_close( iVault );
    DestroyForward( fwOnMixEnd );
}