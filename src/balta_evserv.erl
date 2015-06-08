-module(balta_evserv).
-compile(export_all).

-record(state, {events,
                clients}).
-record(event, {name='',
                description='',
                pid,
                timeout={{1970,1,1},{0,0,0}}}).
init() ->
  loop(#state{events=orddict:new(),
              clients=orddict:new()}).

loop(S = #state{}) ->
  receive
    %for client
    {Pid, MsgRef, {subscribe, Client}} ->
      Ref = erlang:monitor(process, Client),
      NewClients = orddict:store(Ref, Client, S#state.clients),
      Pid ! {MsgRef, ok},
      loop(S#state{clients=NewClients});

    {Pid, MsgRef, {add, Name, Description, TimeOut}} ->
      case valid_datetime(TimeOut) of
        true ->
          EventPid = balta_event:start_link(Name, TimeOut),
          NewEvents = orddict:store(Name, #event{name=Name,
                                                 description=Description,
                                                 pid=EventPid,
                                                 timeout=TimeOut},
                                          S#state.events),
          Pid ! {MsgRef, ok},
          loop(S#state{events=NewEvents});
        false ->
          Pid ! {MsgRef, {error, bad_timeout}},
          loop(S)
      end;

    {Pid, MsgRef, {cancel, Name}} ->
      Events = case orddict:find(Name, S#state.events) of
                 {ok, E} ->
                   balta_event:cancel(E#event.pid),
                   orddict:erase(Name, S#state.events);
                 error ->
                   S#state.events
               end,
      Pid ! {MsgRef, ok},
      loop(S#state{events=Events});

    %for event
    {done, Name} ->
      case orddict:find(Name, S#state.events) of
        {ok, E} ->
          send_to_clients({done, E#event.name, E#event.description}, S#state.clients),
          NewEvents = orddict:erase(Name, S#state.events),
          loop(S#state{events=NewEvents});
        error ->
          loop(S)
      end;

    %for self
    {shutdown} ->
      exit(shutdown);

    %
    {'DOWN', Ref, process, _Pid, _Reason} ->
      loop(S#state{clients=orddict:erase(Ref, S#state.clients)});

    code_change ->
      ?MODULE:loop(S);

    Unknown ->
      io:format("Unknown message: ~p~n", [Unknown]),
      loop(S)
  end.

valid_datetime({Date, Time}) ->
  try
    calendar:valid_date(Date) andalso valid_time(Time)
  catch
    error:function_clause ->
      false
  end;
valid_datetime(_) ->
  false.

valid_time({H,M,S}) -> valid_time(H,M,S).
valid_time(H,M,S) when H >= 0,  H < 24,
                       M >= 0,  M < 60,
                       S >= 0,  S < 60 -> true;
valid_time(_,_,_) -> false.

send_to_clients(Msg, ClientDist) ->
  orddict:map(fun(_Ref, Pid) -> Pid ! Msg end, ClientDist).

