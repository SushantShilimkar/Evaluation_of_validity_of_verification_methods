-module(wdgm_init_eqc).

-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_statem.hrl").

-compile(export_all).

-include("wdgm_config.hrl").
-define(C_CODE, wdgm_wrapper).
-include_lib("../ebin/wdgm_wrapper.hrl").

%-record('SupervisedEntityMonitorTable', {supervision_entities=[]}). %% [{status, {logicalS, deadlineS, aliveS}}]
-record(state, {initialized,
		currentMode,
		globalstatus,
		originalCfg=#wdgm{},
		aliveTable,
		deadlineTable,
		supervisedentities,
		timer_status,
	       errormsg}).
-record(deadline, {startCP,
		   stopCP,
		   timer_status,
		   timestamp}).
-record(supervisedentity, {seid,
			   localalivestatus,
			   supervision_cycles}).
-record(alive, {cpid,
		alive_counter}).

initial_state() ->
  Rs = wdgm_xml:start(),
  {_, R} = (hd(Rs)), %% why do we get a list of records?
  #state{initialized=false,
	 currentMode=-1,
	 globalstatus='WDGM_GLOBAL_STATUS_OK',
	 originalCfg=R}.

%% -WdgM_Init-------------------------------------------------------------------

init_pre(S) ->
  S#state.initialized /= true.

init_command(_S) ->
  {call, ?MODULE, init, [eqc_c:address_of('Tst_Cfg1')]}.

init(Ptr) ->
  ?C_CODE:'WdgM_Init'(Ptr).

init_post(S, _Args, _Ret) ->
  check_supervisionstatus(eqc_c:value_of('WdgM_SupervisedEntityMonitorTable')) andalso
    eqc_c:value_of('WdgM_GlobalStatus') == 'WDGM_GLOBAL_STATUS_OK' andalso
    eqc_c:value_of('WdgM_CurrentMode') == S#state.originalCfg#wdgm.tst_cfg1#tst_cfg1.initial_mode_id.
%% andalso
%%    additional checks if wdgmdeverrordetect is enabled

init_next(S, _Ret, _Args) ->
  ModeId = S#state.originalCfg#wdgm.tst_cfg1#tst_cfg1.initial_mode_id,
  S#state{initialized=true,
	  currentMode=ModeId,
	  supervisedentities=lists:map(fun (X) ->
					   #supervisedentity{seid=X,
							     localalivestatus=undefined,
							     supervision_cycles=0}
				       end,
				       wdgm_config_params:get_SE_from_LS(ModeId)),
	  deadlineTable=lists:map(fun ({X, Y}) ->
				      #deadline{startCP=wdgm_config_params:get_checkpoint_id(X),
						stopCP=wdgm_config_params:get_checkpoint_id(Y),
						timer_status=undefined,
						timestamp=0}
				  end,
				  wdgm_config_params:get_double_checkpoints_for_mode(ModeId, 'DS')),
	  aliveTable=lists:map(fun (X) ->
				   #alive{cpid=wdgm_config_params:get_checkpoint_id(X),
					  alive_counter=0}
			       end,
			       wdgm_config_params:get_checkpoints_for_mode(ModeId, 'AS'))}.

%% -WdgM_GetMode----------------------------------------------------------------

getmode_pre(S) ->
  S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect orelse
   (not S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect andalso
    S#state.initialized == true).

getmode_command(_S) ->
  {call, ?MODULE, getmode, []}.

getmode() ->
  Mp = eqc_c:alloc("uint8"),
  R = ?C_CODE:'WdgM_GetMode'(Mp),
  {R,eqc_c:deref(Mp)}.

getmode_post(S, _Args, {R, Mode}) ->
  (R == 0 andalso Mode == S#state.currentMode)
    orelse R == 1.
%%    additional checks if wdgmdeverrordetect is enabled

%% -WdgM_SetMode----------------------------------------------------------------

setmode_pre(S) ->
  (S#state.globalstatus == 'WDGM_GLOBAL_STATUS_OK' orelse
   S#state.globalstatus == 'WDGM_GLOBAL_STATUS_FAILED') andalso
    (S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect orelse
    (not S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect andalso
       S#state.initialized == true)).

setmode_command(_S) ->
  {call, ?MODULE, setmode, [choose(0,3), choose(1,2)]}.

setmode(UI8_mode,UI16_callerId) ->
        ?C_CODE:'WdgM_SetMode'(UI8_mode,UI16_callerId).

setmode_post(S, [M, Cid], Ret) ->
  lists:member(Cid, S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.caller_ids) andalso
  case Ret of
    0 -> eq(M, eqc_c:value_of('WdgM_CurrentMode'));
    1 -> M == S#state.currentMode orelse eq(S#state.currentMode, -1)
  end.

setmode_next(S, Ret, [M, _Cid]) ->
  case Ret of
    0 -> S#state{currentMode = M,
		 aliveTable=lists:map(fun (X) ->
				       #alive{cpid=wdgm_config_params:get_checkpoint_id(X),
					      alive_counter=0}
				   end,
				   wdgm_config_params:get_checkpoints_for_mode(M, 'AS'))};
    _ -> S
  end.

%% -WdgM_DeInit-----------------------------------------------------------------

deinit_pre(S) ->
  S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect orelse
  (not S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect andalso
     S#state.initialized == true).

deinit_command(_S) ->
  {call, ?MODULE, deinit, []}.

deinit() ->
  ?C_CODE:'WdgM_DeInit'().

%% [WDGM154] should check something with WdgM_SetMode
deinit_post(_S, _Args, _Ret) ->
  true.

deinit_next(S, _Ret, _Args) ->
  S#state{initialized = false, globalstatus='WDGM_GLOBAL_STATUS_OK', currentMode=-1}.

%% -WdgM_CheckpointReached------------------------------------------------------

checkpointreached_pre(S) ->
  S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect orelse
  (not S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect andalso
    S#state.initialized == true).

checkpointreached_command(_S) ->
  {call, ?MODULE, checkpointreached,
   ?LET(SeID, choose(0,4), checkpoint_gen(SeID))}.

checkpoint_gen(SeID) ->
  [SeID, oneof(wdgm_config_params:get_CPs_of_SE(SeID)++[999])].

%% uint16 SupervisedEntityIdType, uint16 CheckpointIdType
checkpointreached(SeID, CPId) ->
  ?C_CODE:'WdgM_CheckpointReached'(SeID, CPId).

checkpointreached_post(S, Args=[_SeID, CPId], Ret) ->
  case Ret of
    1 -> checkpoint_postcondition(S, Args);
    0 -> case eqc_c:value_of('WdgM_CurrentConfigPtr') of
	   CfgPtr = {ptr, _, _} ->
	     case eqc_c:deref(CfgPtr) of
	       {_,_,_,ModePtr} ->
		 case lists:nth(eqc_c:value_of('WdgM_CurrentMode')+1, eqc_c:read_array(ModePtr, 4)) of
		   {_,_,_,AliveSupCount,_,_,_,AliveSupPtr,_,_,_,_} ->
		     case findKeyIndex(CPId, 6, eqc_c:read_array(AliveSupPtr, AliveSupCount)) of
		       not_found -> %% checkpoint does not exist in alive supervision
				true;
		       Idx -> %% checkpoint exists but need to check it
			 element(3, lists:nth(Idx,
					      eqc_c:read_array(element(4, eqc_c:value_of('WdgM_MonitorTableRef')),
							       AliveSupCount)))
			   == (lists:nth(Idx, S#state.aliveTable))#alive.alive_counter+1
		     end;
		   _ -> true
		 end;
	       _ -> true
	     end;
	   _ -> true
	 end
    end.

checkpoint_postcondition(S, [SeID, CPId]) ->
  S#state.initialized /= true orelse
    not lists:member(CPId, wdgm_config_params:get_CPs_of_SE(SeID)) orelse
    not wdgm_config_params:is_activated_SE_in_mode(S#state.currentMode, SeID).

checkpointreached_next(S, _Ret, Args = [_SeID, CPId]) ->
  case not checkpoint_postcondition(S, Args) of
    true ->
      NewS = case lists:keyfind(CPId, 1, S#state.aliveTable) of
	       false -> S;
	       _ -> AliveTable = [case X#alive.cpid of
				       CPId -> X#alive{alive_counter=X#alive.alive_counter+1};
				       _ -> X
				     end
				     || X <- S#state.aliveTable],
		       S#state{aliveTable=AliveTable}
	     end,
      New2S = case lists:member(CPId,
				lists:map(fun (X) -> wdgm_config_params:get_checkpoint_id(X) end,
					  wdgm_config_params:get_checkpoints_for_mode(NewS#state.currentMode, 'DSstart'))) of
		true -> NewS#state{timer_status = 'WDGM_START'};
		false -> NewS
	      end,
      case lists:member(CPId, lists:map(fun (X) -> wdgm_config_params:get_checkpoint_id(X) end, wdgm_config_params:get_checkpoints_for_mode(New2S#state.currentMode, 'DSstop'))) of
	true -> New2S#state{timer_status = 'WDGM_STOP'};
	false -> New2S
      end;
    false -> S
  end.



%% -WdgM_UpdateAliveCounter-----------------------------------------------------
%% Deprecated

%% -WdgM_GetLocalStatus---------------------------------------------------------

getlocalstatus_pre(S) ->
  S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect orelse
  (not S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect andalso
    S#state.initialized == true).

getlocalstatus_command(_S) ->
  {call, ?MODULE, getlocalstatus, [oneof([0,2])]}.

getlocalstatus(UI16_SEID) ->
  Sp = eqc_c:alloc("WdgM_LocalStatusType"),
  R  = ?C_CODE:'WdgM_GetLocalStatus'(UI16_SEID, Sp),
  {R,eqc_c:deref(Sp)}.

getlocalstatus_post(_S, _Args, _Ret) ->
  true.

getlocalstatus_next(S, _Ret, _Args) ->
  S.

%% -WdgM_GetGlobalStatus--------------------------------------------------------

getglobalstatus_pre(S) ->
  S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect orelse
  (not S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect andalso
    S#state.initialized == true).

getglobalstatus_command(_S) ->
  {call, ?MODULE, getglobalstatus, []}.

getglobalstatus() ->
  Sp = eqc_c:alloc("WdgM_GlobalStatusType"),
  R = ?C_CODE:'WdgM_GetGlobalStatus'(Sp),
  {R, eqc_c:deref(Sp)}.

getglobalstatus_post(S, _Args, Ret) ->
  case Ret of
    {0, R} -> eq(R, S#state.globalstatus);
    {1, _} -> S#state.initialized == false andalso
		S#state.globalstatus == 'WDGM_GLOBAL_STATUS_OK'
	      %% [WDGM344] should also check if pointer is null
	      %% [WDGM258] should optionally check if pointer is null
  end.

getglobalstatus_next(S, _Ret, _Args) ->
  S.

%% -WdgM_PerformReset-----------------------------------------------------------

performreset_pre(S) ->
  S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect orelse
  (not S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.dev_error_detect andalso
    S#state.initialized == true).

performreset_command (_S) ->
  {call, ?MODULE, performreset, []}.

performreset() ->
  ?C_CODE:'WdgM_PerformReset'().


performreset_post(_S, _Args, _Ret) ->
  true.

performreset_next(S, _Ret, _Args) ->
  S.

%% -WdgM_GetFirstExpiredSEID----------------------------------------------------

getfirstexpiredseid_pre(_S) ->
  true.

getfirstexpiredseid_command(_S) ->
  {call, ?MODULE, getfirstexpiredseid, []}.

getfirstexpiredseid() ->
  Sp = eqc_c:alloc("WdgM_SupervisedEntityIdType"),
  R = ?C_CODE:'WdgM_GetFirstExpiredSEID'(Sp),
  {R, eqc_c:deref(Sp)}.

getfirstexpiredseid_post(_S, _Args, Ret) ->
  case Ret of
    {0, _} -> true;
    {1, _} -> true
  end.

getfirstexpiredseid_next(S, _Ret, _Args) ->
  S.

%% -WdgM_MainFunction-----------------------------------------------------------

mainfunction_pre(S) ->
  S#state.originalCfg#wdgm.wdgmgeneral#wdgmgeneral.defensive_behavior andalso
    S#state.initialized == true.

mainfunction_command(_S) ->
  {call, ?MODULE, mainfunction, []}.

mainfunction() ->
  ?C_CODE:'WdgM_MainFunction'().

mainfunction_post(_S, _Args, _Ret) ->
  case eqc_c:value_of('WdgM_CurrentConfigPtr') of
    CfgPtr = {ptr, _, _} ->
      case eqc_c:deref(CfgPtr) of
	{_,_,_,ModePtr} ->
	  case lists:nth(eqc_c:value_of('WdgM_CurrentMode')+1, eqc_c:read_array(ModePtr, 4)) of
	    {_,_,_,_,_DeadlineSupCount,_,_,_,_DeadlineSupPtr,_,_,_} -> true;
	      %% case findKeyIndex(CPId, 6, eqc_c:read_array(DeadlineSupPtr, DeadlineSupCount)) of
	      %% 	not_found -> %% checkpoint does not exist in alive supervision
	      %% 	  true;
	      %% 	Idx -> %% checkpoint exists but need to check it
	      %% 	  element(3, lists:nth(Idx,
	      %% 			       eqc_c:read_array(element(4, eqc_c:value_of('WdgM_MonitorTableRef')),
	      %% 						DeadlineSupCount)))
	      %% 	    == element(2, lists:nth(Idx, S#state.deadlineTable))+1
	      %% end;
	    _ -> true
	  end;
	_ -> true
      end;
    _ -> true
  end.

mainfunction_next(S, _Ret, _Args) ->
  S#state{deadlineTable=[case X#deadline.timer_status of
			   'WDGM_STOP' -> X#deadline{timestamp=0};
			   _ -> X#deadline{timestamp=X#deadline.timestamp+1}
			 end
			 || X <- S#state.deadlineTable]}.


%% -----------------------------------------------------------------------------
%% -----------------------------------------------------------------------------
%% -----------------------------------------------------------------------------
%% -Helper-functions------------------------------------------------------------

calculate_global_status(S) ->
  lists:foldl(fun (AS, NewS) -> monitor_active_entity(NewS, AS) end,
	      S,
	      wdgm_config_params:get_alive_supervision(S#state.currentMode)).

monitor_active_entity(S, AS) ->
  NewS = calculate_alive_supervision(S, AS).

calculate_alive_supervision(S, AS) ->
  CPref = car_xml:get_value("WdgMAliveSupervisionCheckpointRef", AS), %% TODO: lyft ur
  SEid = wdgm_config_params:get_SE_id(CPref),
  SE = lists:keyfind(SEid, 1, S#state.supervisedentities),
  NewSE = SE#supervisedentity{supervision_cycles=SE#supervisedentity.supervision_cycles+1},
  SRC = car_xml:get_value("WdgMSupervisionReferenceCycle", AS), %% TODO: lyft ur
  Status = case NewSE#supervisedentity.supervision_cycles >= SRC of
	     true ->
	       CPid = wdgm_config_params:get_checkpoint_id(CPref),
	       CPstate = lists:keyfind(CPid, 1, S#state.aliveTable),
	       I = algo_alive_correct(CPstate#alive.alive_counter,
			NewSE#supervisedentity.supervision_cycles,
			SRC,
			car_xml:get_value("WdgMExpectedAliveIndications", AS)), %% TODO: lyft ur
	       case I >= car_xml:get_value("WdgMMaxMargin", AS) andalso  %% TODO: lyft ur
		 I =< car_xml:get_value("WdgMMinMargin", AS) of %% TODO: lyft ur
		 true -> 'WDGM_CORRECT';
		 _    -> 'WDGM_INCORRECT'
	       end;
	     _ -> 'WDGM_CORRECT'
	   end,
  S#state{supervisedentities=
	    lists:keyreplace(SEid, 1, S#state.supervisedentities, NewSE#supervisedentity{localalivestatus=Status})}.

algo_alive_correct(AliveCounter, SupervisionCycles, SRC, EAI) ->
  AliveCounter-SupervisionCycles+(SRC-EAI).



check_supervisionstatus([]) -> true;
check_supervisionstatus([L|Ls]) ->
  case L#'WdgM_SupervisedEntityMonitor_Tag'.supervision_status of
    'WDGM_LOCAL_STATUS_OK' ->
      check_supervision_results(L) andalso check_supervisionstatus(Ls);
    'WDGM_LOCAL_STATUS_DEACTIVATED' ->
      check_supervisionstatus(Ls)
  end.

check_supervision_results({_, _, 'WDGM_LOCAL_STATUS_OK', _, 'WDGM_CORRECT', 'WDGM_CORRECT', 'WDGM_CORRECT'}) ->
  true;
check_supervision_results(_) ->
  false.

findKeyIndex(E, P, Ls) -> findKeyIndex(E, P, Ls, 1).
findKeyIndex(_, _, [], _) -> not_found;
findKeyIndex(Elem, P, [Tuple|Ls],N) -> case element(P, Tuple) of
					 Elem -> N;
					 _ -> findKeyIndex(Elem, P, Ls, N+1)
				       end.



%% -Frequency-------------------------------------------------------------------

-spec weight(S :: eqc_statem:symbolic_state(), Command :: atom()) -> integer().
weight(_S, setmode) -> 1;
weight(_S, checkpointreached) -> 1;
weight(_S, init) -> 1;
weight(_S, _Cmd) -> 1.

%% -Properties------------------------------------------------------------------

prop_wdgm_init() ->
  ?SETUP( fun () -> start(),
		    fun () -> ok end
	  end,
	  ?FORALL(Cmds, commands(?MODULE),
		  begin
		    eqc_c:restart(),
		    {H,S,Res} = run_commands(?MODULE,Cmds),
		    pretty_commands(?MODULE,Cmds,{H,S,Res},
				    aggregate(command_names(Cmds),
					      Res == ok))
		  end)).

start () ->
  wdgm_eqc:start().
