%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_build).

-export([ dispatch/1
        , build/1
        , includes/1
        , filename__remove_prefix/2
        , is_ignored/2
        ]).

-define(log(Str, Args), io:format(Str ++ "\n", Args)).
-define(log(Str), io:format(Str ++ "\n")).

dispatch (Conf) ->
    erldocs_util:maybe_create_xmerl_table(),
    DidBuild = build([{building_otp, is_building_otp(erldocs_util:kf(apps, Conf))} | Conf]),
    ?log("Woot, finished"),
    DidBuild.

build (Conf) ->
    erldocs_util:mkdir_p(erldocs_util:kf(dest, Conf)),
    AppDirs = [Path || Path <- erldocs_util:kf(apps, Conf), filelib:is_dir(Path)],
    IncludePaths = lists:usort(lists:flatmap(fun includes/1, AppDirs)),
    ModuleDocs = lists:flatmap(
                   fun (AppDir) ->
                           AppName = app_name(AppDir),
                           ?log("Building ~s", [AppName]),
                           erldocs_collect:collect_app(Conf, IncludePaths, AppName, AppDir)
                   end, AppDirs),
    case ModuleDocs of
        [] ->
            ?log("No documentation was generated!"),
            false;
        _ ->
            lists:foreach(fun (ModuleDoc) -> ok = erldocs_render:render_module(Conf, ModuleDoc) end,
                          ModuleDocs),
            ok = erldocs_render:write_index(Conf, ModuleDocs),
            ok = erldocs_render:write_javascript_index(Conf, ModuleDocs),
            ok = erldocs_render:copy_static_files(Conf),
            true
    end.

app_name (AppDir) ->
    DotApps = [erldocs_util:bname(AppSrc, ".app")
               || AppSrc <- filelib:wildcard(erldocs_util:jname([AppDir, "ebin", "*.app"]))],
    DotAppSrcs = [erldocs_util:bname(AppSrc, ".app.src")
                  || AppSrc <- filelib:wildcard(erldocs_util:jname([AppDir, "src", "*.app.src"]))],
    case DotApps ++ DotAppSrcs of
        [AppName|_] -> AppName;
        [] ->         erldocs_util:bname(AppDir)
    end.

is_building_otp ([]) -> false;
is_building_otp ([AppDir|Rest]) ->
    case find_erlang_module(AppDir) of
        false -> is_building_otp(Rest);
        Path -> {true, Path}
    end.

find_erlang_module (AppDir) ->
    ExitFast = fun (Fn, _Acc) -> throw({found, Fn}) end,
    try filelib:fold_files(AppDir, "^erlang\\.erl$", true, ExitFast, not_found) of
        not_found -> false
    catch
        {found,Fn} ->
            ?log("building_otp: true"),
            Fn
    end.

includes (AppDir) ->
    erldocs_collect_legacy:includes(AppDir).

filename__remove_prefix (Prefix, Path) ->
    erldocs_collect_legacy:filename__remove_prefix(Prefix, Path).

%% @doc A black list for OTP
is_ignored ("kernel", "init") -> true;
is_ignored ("kernel", "zlib") -> true;
is_ignored ("kernel", "erlang") -> true;
is_ignored ("kernel", "erl_prim_loader") -> true;
is_ignored (_AppName, _Module) -> false.
