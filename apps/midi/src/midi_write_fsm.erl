%% @doc The coordinator for stat write opeartions.  This example will
%% show how to properly replicate your data in Riak Core by making use
%% of the _preflist_.
-module(midi_write_fsm).
-behavior(gen_fsm).
-include("midi.hrl").

%% API
-export([start_link/5, start_link/6, write/3, write/4]).

%% Callbacks
-export([init/1, code_change/4, handle_event/3, handle_info/3,
         handle_sync_event/4, terminate/3]).

%% States
-export([prepare/2, execute/2, waiting/2]).

%% req_id: The request id so the caller can verify the response.
%%
%% sender: The pid of the sender so a reply can be made.
%%
%% client: The external entity that wrote the log entry that produced
%% this stat.
%%
%% state_name: The name of the statistic.
%%
%% op: The stat op, one of [set, incr, incr_by, append, sadd]
%%
%% prelist: The preflist for the given {Client, StatName} pair.
%%
%% num_w: The number of successful write replies.
-record(state, {req_id :: pos_integer(),
                coordinator :: node(),
                from :: pid(),
                client :: string(),
                stat_name :: string(),
                op :: atom(),
                val = undefined :: term() | undefined,
                preflist :: riak_core_apl:preflist2(),
                n :: pos_integer(),
                w :: pos_integer(),
                num_w = 0 :: non_neg_integer()}).


-define(SERVICE, midi_stat).

%%%===================================================================
%%% API
%%%===================================================================

start_link(ReqID, From, Client, StatName, Op) ->
    start_link(ReqID, From, Client, StatName, Op, undefined).

start_link(ReqID, From, Client, StatName, Op, Val) ->
    gen_fsm:start_link(?MODULE, [ReqID, From, Client, StatName, Op, Val], []).

write(Client, StatName, Op) ->
    write(Client, StatName, Op, undefined).

write(Client, StatName, Op, Val) ->
    ReqID = midi_utils:mk_reqid(),
    midi_write_fsm_sup:start_write_fsm([ReqID, self(), Client, StatName, Op, Val]),
    receive
        {ReqID, ok} -> 
            ok;
        {ReqID, ok, Val} -> {ok, Val}
    after ?TIMEOUT->
        {error, timeout}
    end.


%%%===================================================================
%%% States
%%%===================================================================

%% @doc Initialize the state data.
init([ReqID, From, Client, StatName, Op, Val]) ->
    N = application:get_env(midi, n, ?DEFAULT_N),
    W = application:get_env(midi, w, ?DEFAULT_W),
    SD = #state{req_id=ReqID,
                coordinator=node(),
                from=From,
                client=Client,
                stat_name=StatName,
                op=Op,
                n=N,
                w=W,
                val=Val},
    {ok, prepare, SD, 0}.

%% @doc Prepare the write by calculating the _preference list_.
prepare(timeout, SD0=#state{client=Client,
                            stat_name=StatName, n=N}) ->
    DocIdx = riak_core_util:chash_key({list_to_binary(Client),
                                       list_to_binary(StatName)}),
    Preflist = riak_core_apl:get_apl(DocIdx, N, ?SERVICE),
    SD = SD0#state{preflist=Preflist},
    {next_state, execute, SD, 0}.

%% @doc Execute the write request and then go into waiting state to
%% verify it has meets consistency requirements.
execute(timeout, SD0=#state{req_id=ReqID,
                            coordinator=Coordinator,
                            stat_name=StatName,
                            op=Op,
                            val=Val,
                            preflist=Preflist}) ->
    case Val of
        undefined ->
            midi_stat_vnode:Op(Preflist, {ReqID, Coordinator}, StatName);
        _ ->
            midi_stat_vnode:Op(Preflist, {ReqID, Coordinator}, StatName, Val)
    end,
    {next_state, waiting, SD0}.

%% @doc Wait for W write reqs to respond.
waiting({ok, ReqID}, SD0=#state{from=From, w=W, num_w=NumW0}) ->
    NumW = NumW0 + 1,
    SD = SD0#state{num_w=NumW},
    case NumW of 
        W ->
            From ! {ReqID, ok},
            {stop, normal, SD};

        _ -> {next_state, waiting, SD}
    end.

handle_info(_Info, _StateName, StateData) ->
    {stop,badmsg,StateData}.

handle_event(_Event, _StateName, StateData) ->
    {stop,badmsg,StateData}.

handle_sync_event(_Event, _From, _StateName, StateData) ->
    {stop,badmsg,StateData}.

code_change(_OldVsn, StateName, State, _Extra) -> {ok, StateName, State}.

terminate(_Reason, _SN, _SD) ->
    ok.
