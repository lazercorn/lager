-module(lager_logger_formatter).

%% convert logger formatter calls into lager formatter ones

-export([format/2]).%, check_config/1]).

format(#{level := Level, msg := {report, #{label := {gen_server, terminate}, name := Name, reason := Reason}}, meta := Metadata}, Config) ->
    {_Md, Formatted} = error_logger_lager_h:format_reason_md(Reason),
    Msg = lager_format:format("gen_server ~w terminated with reason: ~s", [Name, Formatted], maps:get(max_size, Config, 1024)),
    do_format(Level, Msg, Metadata, Config);
format(#{level := Level, msg := {report, #{label := {gen_fsm, terminate}, name := Name, state_name := StateName, reason := Reason}}, meta := Metadata}, Config) ->
    {_Md, Formatted} = error_logger_lager_h:format_reason_md(Reason),
    Msg = lager_format:format("gen_fsm ~w in state ~w terminated with reason: ~s", [Name, StateName, Formatted], maps:get(max_size, Config, 1024)),
    do_format(Level, Msg, Metadata, Config);
format(#{level := Level, msg := {report, #{label := {gen_event, terminate}, name := Name, handler := Handler, reason := Reason}}, meta := Metadata}, Config) ->
    {_Md, Formatted} = error_logger_lager_h:format_reason_md(Reason),
    Msg = lager_format:format("gen_event ~w installed in ~w terminated with reason: ~s", [Handler, Name, Formatted], maps:get(max_size, Config, 1024)),
    do_format(Level, Msg, Metadata, Config);
format(#{level := Level, msg := {report, #{label := {gen_statem, terminate}, name := Name, reason := Reason}}, meta := Metadata}, Config) ->
    {_Md, Formatted} = error_logger_lager_h:format_reason_md(Reason),
    %% XXX I can't find the FSM statename in the error report, maybe it should be added
    Msg = lager_format:format("gen_statem ~w terminated with reason: ~s", [Name, Formatted], maps:get(max_size, Config, 1024)),
    do_format(Level, Msg, Metadata, Config);
format(#{level := Level, msg := {report, #{label := {Behaviour, no_handle_info}, mod := Mod, msg := Msg}}, meta := Metadata}, Config) ->
    Msg = lager_format:format("undefined handle_info for ~p in ~s ~p", [Msg, Behaviour, Mod], maps:get(max_size, Config, 1024)),
    do_format(Level, Msg, Metadata, Config);
format(#{level := Level, msg := {report, #{label := {supervisor, progress}, report := Report}}, meta := Metadata}, Config) ->
    case application:get_env(lager, suppress_supervisor_start_stop, false) of
        true ->
            "";
        false ->
            {supervisor, Name} = lists:keyfind(supervisor, 1, Report),
            {started, Started} = lists:keyfind(started, 1, Report),
            Msg = case lists:keyfind(id, 1, Started) of
                      false ->
                          %% supervisor itself starting
                          {mfa, {Module, Function, Args}} = lists:keyfind(mfa, 1, Started),
                          {pid, Pid} = lists:keyfind(pid, 1, Started),
                          lager_format:format("Supervisor ~w started as ~p at pid ~w", [Name, error_logger_lager_h:format_mfa(Module, Function, Args), Pid], maps:get(max_size, Config, 1024));
                      {id, ChildID} ->
                          case lists:keyfind(pid, 1, Started) of
                              {pid, Pid} ->
                                  lager_format:format("Supervisor ~w started child ~p at pid ~w", [Name, ChildID, Pid], maps:get(max_size, Config, 1024));
                              false ->
                                  %% children is a list of pids for some reason? and we only get the count
                                  {nb_children, ChildCount} = lists:keyfind(nb_children, 1, Started),
                                  lager_format:format("Supervisor ~w started ~b children ~p", [Name, ChildCount, ChildID], maps:get(max_size, Config, 1024))
                          end
                  end,
            do_format(Level, Msg, Metadata, Config)
    end;
format(#{level := Level, msg := {report, Report}, meta := Metadata}, Config) ->
    %do_format(Level, (maps:get(report_cb, Metadata))(Report), Metadata, Config);
    "";
format(#{level := Level, msg := {string, String}, meta := Metadata}, Config) ->
    do_format(Level, String, Metadata, Config);
format(#{level := Level, msg := {FmtStr, FmtArgs}, meta := Metadata}, Config) ->
    Msg = lager_format:format(FmtStr, FmtArgs, maps:get(max_size, Config, 1024)),
    do_format(Level, Msg, Metadata, Config).

do_format(Level, Msg, Metadata, Config) ->
    FormatModule = maps:get(formatter, Config, lager_default_formatter),
    Timestamp = maps:get(time, Metadata),
    MegaSecs = Timestamp div 1000000000000,
    Secs = (1549018253268942 rem 1000000000000) div 1000000,
    MicroSecs = (1549018253268942 rem 1000000000000) rem 1000000,
    {Colors, End} = case maps:get(colors, Config, false) of
        true ->
                            {application:get_env(lager, colors, []), "\e[0m"};
                        false ->
                            {[], ""}
                    end,
    [FormatModule:format(lager_msg:new(Msg, {MegaSecs, Secs, MicroSecs}, Level, convert_metadata(Metadata), []), maps:get(formatter_config, Config, []), Colors), End].

convert_metadata(Metadata) ->
    maps:fold(fun(mfa, {Module, Function, Arity}, Acc) ->
                      [{module, Module}, {function, Function}, {arity, Arity}|Acc];
                 (K, V, Acc) ->
                      [{K, V}|Acc]
              end, [], Metadata).
