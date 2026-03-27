%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_collect).

-export([ collect_app/4
        , use_modern_path/0
        ]).

collect_app (Conf, IncludePaths, AppName, AppDir) ->
    case use_modern_path() of
        true ->
            erldocs_collect_modern:collect_app(Conf, IncludePaths, AppName, AppDir);
        false ->
            erldocs_collect_legacy:collect_app(Conf, IncludePaths, AppName, AppDir)
    end.

use_modern_path () ->
    case erlang:system_info(otp_release) of
        [$R | _] ->
            false;
        Release ->
            case catch list_to_integer(Release) of
                Int when is_integer(Int), Int >= 28 -> true;
                _ -> false
            end
    end.
