-module(amkabot_ffi).
-export([get_pid/0, is_alive/1, read_file/1, write_file/2]).

get_pid() ->
    list_to_binary(os:getpid()).

is_alive(PidBin) ->
    PidStr = binary_to_list(PidBin),
    Command = "kill -0 " ++ PidStr ++ " 2>/dev/null; echo $?",
    case os:cmd(Command) of
        "0\n" -> true;
        _ -> false
    end.

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> {ok, Bin};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

write_file(Path, Data) ->
    case file:write_file(Path, Data) of
        ok -> {ok, nil};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.
