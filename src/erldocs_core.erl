%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_core).

-export([ copy_static_files/1
        , build/1
        , dispatch/1
        , mapreduce/4
        , pmapreduce/4
        , pmapreduce/5
        , maybe_delete_xmerl_table/0
        ]).

-ifdef(TEST).
-export([includes/1]).
-export([filename__remove_prefix/2]).
-endif.

copy_static_files (Conf) ->
    erldocs_render:copy_static_files(Conf).

build (Conf) ->
    erldocs_build:build(Conf).

dispatch (Conf) ->
    erldocs_build:dispatch(Conf).

mapreduce (Map, Reduce, Acc0, L) ->
    erldocs_util:mapreduce(Map, Reduce, Acc0, L).

pmapreduce (Map, Reduce, Acc0, L) ->
    erldocs_util:pmapreduce(Map, Reduce, Acc0, L).

pmapreduce (Map, Reduce, Acc0, L, N) ->
    erldocs_util:pmapreduce(Map, Reduce, Acc0, L, N).

maybe_delete_xmerl_table () ->
    erldocs_util:maybe_delete_xmerl_table().

-ifdef(TEST).
includes (AppDir) ->
    erldocs_build:includes(AppDir).

filename__remove_prefix (Prefix, Path) ->
    erldocs_build:filename__remove_prefix(Prefix, Path).
-endif.
