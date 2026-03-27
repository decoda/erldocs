%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_util).

-export([ kf/2
        , bname/1
        , bname/2
        , dname/1
        , jname/1
        , jname/2
        , mkdir_p/1
        , copy_path/2
        , cons/2
        , tmp_cd/2
        , maybe_create_xmerl_table/0
        , maybe_delete_xmerl_table/0
        , is_xmerl_table_created/0
        , mapreduce/4
        , pmapreduce/4
        , pmapreduce/5
        , segment/2
        , segment/3
        ]).

-include("erldocs.hrl").

-spec kf (_, list()) -> _.
kf (Key, Conf) ->
    {Key, Val} = lists:keyfind(Key, 1, Conf),
    Val.

bname (Name) ->
    filename:basename(Name).
bname (Name, Ext) ->
    filename:basename(Name, Ext).

dname (Name) ->
    filename:dirname(Name).

jname (Dir1, Dir2) ->
    filename:join(Dir1, Dir2).
jname (ExplodedPath) ->
    filename:join(ExplodedPath).

mkdir_p (Path) ->
    case filelib:ensure_dir(Path) of
        ok -> ok;
        {error, eexist} -> ok
    end.

copy_path (Source, Dest) ->
    case filelib:is_dir(Source) of
        true ->
            ok = mkdir_p(filename:join(Dest, "placeholder")),
            {ok, Entries} = file:list_dir(Source),
            lists:foreach(fun (Entry) ->
                                  copy_path(filename:join(Source, Entry),
                                            filename:join(Dest, Entry))
                          end, Entries);
        false ->
            ok = mkdir_p(Dest),
            {ok, Data} = file:read_file(Source),
            ok = file:write_file(Dest, Data)
    end.

cons (H, T) -> [H | T].

%% @doc run a function with the cwd set, ensuring the cwd is reset once
%% finished (some dumb functions require to be ran from a particular dir)
-spec tmp_cd (file:name(), fun()) -> _.
tmp_cd (Dir, Fun) ->
    {ok, OldDir} = file:get_cwd(),
    mkdir_p(Dir),
    ok = file:set_cwd(Dir),
    try
        Result = Fun(),
        ok = file:set_cwd(OldDir),
        Result
    catch
        Type:Err:ST ->
            ok = file:set_cwd(OldDir),
            throw({Type, Err, ST})
    end.

maybe_create_xmerl_table () ->
    case is_xmerl_table_created() of
        true -> ok;
        false ->
            Opts = [named_table, ordered_set, public],
            ?ERLDOCS_XMERL_ETS_TABLE = ets:new(?ERLDOCS_XMERL_ETS_TABLE, Opts)
    end.

is_xmerl_table_created () ->
    undefined /= ets:info(?ERLDOCS_XMERL_ETS_TABLE, compressed).

maybe_delete_xmerl_table () ->
    case is_xmerl_table_created() of
        false -> ok;
        true -> ets:delete(?ERLDOCS_XMERL_ETS_TABLE)
    end.

-type map_fun(D, R) :: fun((D) -> R).
-type reduce_fun(T) :: fun((T, _) -> _).

-spec pmapreduce (map_fun(T, R), reduce_fun(R), R, L) -> [R] when
      L :: [T].
pmapreduce (Map, Reduce, Acc0, L) ->
    pmapreduce(Map, Reduce, Acc0, L, erlang:system_info(schedulers_online)).

-spec pmapreduce (map_fun(T, R), reduce_fun(R), R, L, pos_integer()) -> [R] when
      L :: [T].
pmapreduce (Map, Reduce, Acc0, L, N) ->
    Keys = [rpc:async_call(node(), ?MODULE, mapreduce,
                           [Map, Reduce, Acc0, Segment])
            || Segment <- segment(L, N)],
    mapreduce(fun rpc:yield/1, Reduce, Acc0, Keys).

-spec mapreduce (map_fun(T, R), reduce_fun(R), R, L) -> [R] when
      L :: [T].
mapreduce (Map, Reduce, Acc0, L) ->
    lists:foldl(fun (Elem, Acc) ->
                        Reduce(Map(Elem), Acc)
                end,
                Acc0, lists:reverse(L)).

-spec segment ([T], pos_integer()) -> [[T]].
segment (List, Segments) ->
    segment(List, length(List) div Segments, Segments).

-spec segment ([T], non_neg_integer(), pos_integer()) -> [[T]].
segment (List, _N, 1) ->
    [List];
segment (List, N, Segments) ->
    {Front, Back} = lists:split(N, List),
    [Front | segment(Back, N, Segments - 1)].
