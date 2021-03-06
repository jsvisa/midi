-define(PRINT(Var), io:format("DEBUG: ~p:~p - ~p~n~n ~p~n~n", [?MODULE, ?LINE, ??Var, Var])).

-define(TIMEOUT, 5000).

-define(DEFAULT_N, 3).
-define(DEFAULT_R, 2).
-define(DEFAULT_W, 2).
-define(DEFAULT_CRUNCH_N, 3).
-define(DEFAULT_CRUNCH_W, 1).

-define(DEFAULT_TIMEOUT, 10000).
-define(STATEBOX_EXPIRE, 60000).

-record(incr,           {total  :: pos_integer(),
                         counts :: dict:dict()}).
-type incr()            :: #incr{}.

-type val()             :: incr() | statebox:statebox().

-record(midi_obj,        {val    :: val(),
                         vclock :: vclock:vclock()}).

-type midi_obj()         :: #midi_obj{} | not_found.

-record(req, {
         id      :: {integer(), atom()} | integer(),
         request :: term(),
         bucket  :: binary()
         }).

-define(REQ(R), #req{request = R, bucket = ?BUCKET}).
-define(REQ(ID, R), #req{id = ID, request = R, bucket = ?BUCKET}).
