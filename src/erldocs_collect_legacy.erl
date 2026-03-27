%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_collect_legacy).

-export([ collect_app/4
        , includes/1
        , filename__remove_prefix/2
        , merge_specs/1
        , find_spec/3
        , find_type/3
        , make_name/1
        ]).

-ifdef(TEST).
-export([ module_summary/2
        , function_summary/1
        , function_docs/4
        , type_docs/1
        ]).
-endif.

-include_lib("otp_vsn/include/otp_vsn.hrl").
-include("erldocs.hrl").

-define(log(Str, Args), io:format(Str ++ "\n", Args)).

collect_app (Conf, IncludePaths, AppName, AppDir) ->
    Files = ensure_docsrc(Conf, IncludePaths, AppName, AppDir),
    Map = fun (File) -> collect_file(Conf, AppName, erldocs_util:bname(File, ".xml"), File) end,
    erldocs_util:pmapreduce(Map, fun lists:append/2, [], Files).

collect_file (Conf, AppName, Module, File) ->
    case erldocs_build:is_ignored(AppName, Module) of
        true ->
            ?log("HTML generation for ~s skipped - ~p", [Module, File]),
            [];
        false ->
            {Type, _Attr, Content} = read_xml(File),
            case is_buildable(Type) of
                false ->
                    [];
                true ->
                    ?log("Generating HTML - ~s ~p", [Module, File]),
                    Xml = strip_whitespace(Content),
                    TypeSpecs = read_xml_specs(Conf, Module),
                    Summary = lists:flatten(module_summary(Type, Xml)),
                    PageContent = erldocs_render_legacy_xml:render_content(Content, TypeSpecs),
                    Functions = function_docs(AppName, Module, Xml, TypeSpecs),
                    Types = type_docs(TypeSpecs),
                    [erldocs_model:module_doc(AppName, Module, legacy_xml,
                                              Summary, PageContent, Functions, Types, [])]
            end
    end.

module_summary (erlref, Xml) ->
    {_, [], Sum} = lists:keyfind(modulesummary, 1, Xml),
    unicode:characters_to_list([X || X <- Sum, not is_tuple(X)]);
module_summary (cref, Xml) ->
    {_, [], Sum} = lists:keyfind(libsummary, 1, Xml),
    Sum.

function_summary (FuncXml) ->
    case lists:keyfind(fsummary, 1, FuncXml) of
        {fsummary, [], Xml} ->
            shorten(erldocs_render_legacy_xml:xml_to_html(Xml));
        false ->
            ""
    end.

shorten (Str) ->
    Lines = string:tokens(lists:flatten(Str), "\r\n"),
    Clean = string:join(lists:map(fun string:strip/1, Lines), " "),
    string:substr(Clean, 1, 50).

ensure_docsrc (Conf, IncludePaths, AppName, AppDir) ->
    TmpRoot = erldocs_util:jname(erldocs_util:kf(dest, Conf), ?ERLDOCS_SPECS_TMP),
    XMLDir  = erldocs_util:jname(TmpRoot, AppName),
    erldocs_util:mkdir_p(XMLDir ++ "/"),

    Erls = filelib:fold_files(erldocs_util:jname(AppDir, "src"), "\\.erl$", true,
                              fun erldocs_util:cons/2, []),
    XMLFiles = filelib:wildcard(erldocs_util:jname([AppDir, "doc", "src", "*.xml"])),

    case erldocs_util:kf(building_otp, Conf) of
        false ->
            ErlFiles = filelib:wildcard(erldocs_util:jname(AppDir, "*.erl")) ++ Erls,
            HandWritten = [erldocs_util:bname(File, ".xml") || File <- XMLFiles],
            NoXMLs = [File || File <- ErlFiles,
                              not lists:member(erldocs_util:bname(File, ".erl"), HandWritten)],
            F = fun () -> gen_docsrc(IncludePaths, AppName, AppDir, XMLDir, NoXMLs) end,
            MissingXMLFiles = erldocs_util:tmp_cd(XMLDir, F);
        {true,ErlangErl} ->
            ErlFiles = maybe_add_otp_preloaded(AppName, ErlangErl) ++ Erls,
            MissingXMLFiles = []
    end,

    lists:foreach(fun (File) -> gen_type_specs(IncludePaths, TmpRoot, File) end, ErlFiles),
    XMLFiles ++ MissingXMLFiles.

maybe_add_otp_preloaded ("erts", ErlangErl) ->
    ErlangErlAppDir = erldocs_util:dname(erldocs_util:dname(ErlangErl)),
    filelib:wildcard(erldocs_util:jname([ErlangErlAppDir, "src", "*.erl"]));
maybe_add_otp_preloaded (_AppName, _) -> [].

gen_type_specs (IncludePaths, SpecsDest, ErlFile) ->
    case erlang:system_info(otp_release) of
        [$R,$1,Digit|_] when Digit < $5 -> SpecsGenModule = specs_gen__below_R15;
        "R" ++ _ ->                        SpecsGenModule = specs_gen__R15_to_17;
        Vsn when Vsn < "18" ->             SpecsGenModule = specs_gen__R15_to_17;
        _Otherwise ->                      SpecsGenModule = specs_gen__18_and_above
    end,
    ?log("Generating Type Specs - ~p", [ErlFile]),
    Args = ["-o" ++ SpecsDest] ++ ["-I" ++ Inc || Inc <- IncludePaths] ++ [ErlFile],
    try SpecsGenModule:main(Args)
    catch _:_SpecsGenError -> false
    end.

read_xml_specs (Conf, Module) ->
    Fn = "specs_" ++ Module ++ ".xml",
    File = erldocs_util:jname([erldocs_util:kf(dest, Conf), ?ERLDOCS_SPECS_TMP, Fn]),
    case filelib:is_file(File) of
        false -> [];
        true ->
            case read_xml(File) of
                {error, _, _} -> [];
                {module, _, Specs} ->
                    ?log("Read XML Specs for ~s - '~s'", [Fn, File]),
                    strip_whitespace(Specs)
            end
    end.

includes (AppDir) ->
    Hrls = filelib:fold_files(AppDir, "\\.hrl$", true, fun erldocs_util:cons/2, []),
    F = fun (Hrl) -> includes_parents(AppDir, Hrl) end,
    lists:usort([AppDir, erldocs_util:dname(AppDir)] ++
                    lists:flatmap(F, Hrls)).

includes_parents (AppDir, Hrl) ->
    RelativeHrl = filename__remove_prefix(AppDir, Hrl),
    includes_parents(AppDir, erldocs_util:dname(RelativeHrl), []).
includes_parents (_, ".", Acc) -> Acc;
includes_parents (AppDir, Parent, Acc) ->
    case lists:member("test", filename:split(Parent)) of
        true  -> NewAcc = Acc;
        false -> NewAcc = [erldocs_util:jname(AppDir, Parent) | Acc]
    end,
    includes_parents(AppDir, erldocs_util:dname(Parent), NewAcc).

filename__remove_prefix (Prefix, Path) ->
    case lists__remove_prefix(filename:split(Prefix), filename:split(Path)) of
        "" -> "";
        Exploded -> filename:join(Exploded)
    end.

lists__remove_prefix ([A|Prefix], [A|Rest]) ->
    lists__remove_prefix(Prefix, Rest);
lists__remove_prefix (_, Rest) ->
    Rest.

gen_docsrc (IncludePaths, AppName, AppDir, Dest, SrcFiles) ->
    App = list_to_atom(AppName),
    Opts = [ {includes, IncludePaths}
           , {sort_functions, false}
           , {file_suffix, ".xml"}
           , {preprocess, true}
           , {dir, Dest}
           , {packages, false}
           , {layout, docgen_edoc_xml_cb}
           , {application, App}
           ],

    ?log("Generating XML for application ~s ~p -> ~p", [AppName,AppDir,Dest]),
    case catch (edoc:application(App, AppDir, Opts)) of
        ok ->
            XmlFiles = filelib:wildcard(erldocs_util:jname(Dest, "*.xml")),
            ?log("Generated ~s XMLs: ~p", [AppName, XmlFiles]),
            XmlFiles;
        _Error ->
            ?log("Error generating ~s XMLs. Using fallback ...", [AppName]),
            lists:foldl(
              fun (File, Acc) ->
                      Module = erldocs_util:bname(File, ".erl"),
                      DestFile = erldocs_util:jname(Dest, Module ++ ".xml"),
                      ?log("Generating XML ~s - ~s ~p -> ~p", [AppName,Module,File,DestFile]),
                      case catch (edoc:file(File, Opts)) of
                          ok ->
                              [DestFile | Acc];
                          Error ->
                              ?log("Error generating XML (~p): ~p", [File,Error]),
                              Acc
                      end
              end, [], SrcFiles)
    end.

function_docs (App, Mod, Xml, TypeSpecs) ->
    case lists:keyfind(funcs, 1, Xml) of
        false -> [];
        {funcs, [], Funs} ->
            lists:flatmap(fun (X) -> fun_docs(App, Mod, X, TypeSpecs) end, Funs)
    end.

fun_docs (App, Mod, {func, [], Children}, TypeSpecs) ->
    Summary = function_summary(Children),
    [case function_name(Child) of
         ignore ->
             ignore;
         {Name, Arity} ->
             Signature = function_signatures(Name, Arity, TypeSpecs),
             erldocs_model:function_doc(Name, list_to_integer(Arity), Name ++ "/" ++ Arity,
                                        Summary, Name ++ "/" ++ Arity, [], Signature,
                                        [{app, App}, {module, Mod}])
     end || Child <- Children, function_name(Child) =/= ignore];
fun_docs (_App, _Mod, _Else, _TypeSpecs) ->
    [].

function_name ({name, [], Name}) ->
    case make_name(Name) of
        ignore -> ignore;
        NName ->
            split_name_arity(NName)
    end;
function_name ({name, [{name,Name}, {arity,Arity}], []}) ->
    {Name, Arity};
function_name ({name, [{name,Name}, {arity,Arity}, {since,_}], []}) ->
    {Name, Arity};
function_name ({name, [{name,Name}, {arity,Arity}, {clause_i,"1"}], []}) ->
    {Name, Arity};
function_name (_) ->
    ignore.

split_name_arity (Name) ->
    [FName, Arity] = string:tokens(Name, "/"),
    {FName, Arity}.

function_signatures (Name, Arity, TypeSpecs) ->
    Found = find_spec(Name, Arity, TypeSpecs),
    {SpecsFound, _Names} = lists:unzip(Found),
    [lists:flatten(erldocs_render_legacy_xml:xml_to_html(Spec))
     || Spec <- merge_specs(SpecsFound), Spec /= []].

make_name (Name) ->
    Tmp = lists:flatten(Name),
    case string:chr(Tmp, $() of
        0 ->
            ignore;
        Pos ->
            {Name2, Rest2} = lists:split(Pos - 1, Tmp),
            FName          = lists:last(string:tokens(Name2, ":")),
            Args           = string:substr(Rest2, 2, string:chr(Rest2, $)) - 2),
            NArgs          = length(string:tokens(Args, ",")),
            FName ++ "/" ++ integer_to_list(NArgs)
    end.

type_docs (Specs) ->
    [begin
         {_, _, [Name]} = lists:keyfind(name, 1, Type),
         {_, _, [NVars]} = lists:keyfind(n_vars, 1, Type),
         {_, _, TypeDecl} = lists:keyfind(typedecl, 1, Type),
         {_, _, TypeHead} = lists:keyfind(typehead, 1, TypeDecl),
         [{marker,[{id,ID}|_],[NName]} | Child] = TypeHead,
         Signature = lists:flatten(erldocs_render_legacy_xml:xml_to_html([NName | Child])),
         erldocs_model:type_doc(Name, list_to_integer(NVars), ID, Name ++ "/" ++ NVars,
                                [], [Signature], false, [])
     end || {type, [], Type} <- Specs].

merge_specs (Specs) ->
    case Specs of
        []    -> [];
        [H|T] -> merge_specs(T, lists:reverse(H))
    end.
merge_specs ([], Acc) -> lists:reverse(Acc);
merge_specs ([[]|Rest], Acc) ->
    merge_specs(Rest, Acc);
merge_specs ([[Spec|Specs]|Rest], Acc) ->
    case lists:member(Spec, Acc) of
        true  -> merge_specs([Specs|Rest],       Acc );
        false -> merge_specs([Specs|Rest], [Spec|Acc])
    end.

find_spec (_Name, _Arity, []) -> [];
find_spec (Name, Arity, [{spec, [], Specs} |Rest]) ->
    {_, _, [SpecName]}  = lists:keyfind(name, 1, Specs),
    {_, _, [ArityName]} = lists:keyfind(arity, 1, Specs),
    case (SpecName == Name) and (ArityName == Arity) of
        false ->
            find_spec(Name, Arity, Rest);
        true  ->
            {_, _, Contracts} = lists:keyfind(contract, 1, Specs),
            {_, _, Clause}    = lists:keyfind(clause, 1, Contracts),
            {_, _, Head}      = lists:keyfind(head, 1, Clause),
            TheName = lists:map(fun erldocs_render_legacy_xml:xml_to_html/1, Head),
            case lists:keyfind(guard, 1, Clause) of
                false ->
                    TheSpec = [];
                {_, _, Subtypes} ->
                    TheSpec = [ lists:map(fun erldocs_render_legacy_xml:xml_to_html/1, S)
                                || {subtype,[]
                                   , [ {typename,[],_}
                                     , {string,[],S} ] } <- Subtypes]
            end,
            [ {TheSpec,TheName}
              | find_spec(Name, Arity, Rest) ]
    end;
find_spec (Name, Arity, [_ | Rest]) ->
    find_spec(Name, Arity, Rest).

find_type (Name0, NVars0, [{type,[],Type} |Rest]) ->
    {_, _, [Name]}   = lists:keyfind(name, 1, Type),
    {_, _, [NVars]}  = lists:keyfind(n_vars, 1, Type),
    case (Name =:= Name0) and (NVars =:= NVars0) of
        true ->
            {_, _, TypeDecl} = lists:keyfind(typedecl, 1, Type),
            {_, _, TypeHead} = lists:keyfind(typehead, 1, TypeDecl),
            [{marker,[{id,ID}|_],[NName]} |Child] = TypeHead,
            {ID, lists:flatten([NName|Child])};
        false ->
            find_type(Name0, NVars0, Rest)
    end;
find_type (Name, NVars, [_|Rest]) ->
    find_type(Name, NVars, Rest);
find_type (_Name, _NVars, []) ->
    ignore.

strip_whitespace (List) when is_list(List) ->
    [strip_whitespace(X) || X <- List, keeper(X)];
strip_whitespace ({El,Attr,Children}) ->
    {El, Attr, strip_whitespace(Children)};
strip_whitespace (Else) ->
    Else.

keeper (X) when is_tuple(X); is_number(X) ->
    true;
keeper (X) when is_list(X) ->
    not lists:all(fun is_whitespace/1, X).

is_whitespace ($\s) -> true;
is_whitespace ($\n) -> true;
is_whitespace ($\t) -> true;
is_whitespace (_) -> false.

read_xml (XmlFile) ->
    ?log("Reading XML for '~s'", [XmlFile]),
    FetchPath = xml_fetch_path(),
    Opts = [ {fetch_path, FetchPath}
           , {encoding, "latin1"}
           , {rules, ?ERLDOCS_XMERL_ETS_TABLE}
           ],
    try xmerl_scan:file(XmlFile, Opts) of
        {Xml, _Rest} ->
            xmerl_lib:simplify_element(Xml);
        Error ->
            throw({error_in_read_xml, XmlFile, Error})
    catch
        E:R:ST ->
            throw({error_in_read_xml, XmlFile, {E, R, ST}})
    end.

xml_fetch_path () ->
    case code:priv_dir(erl_docgen) of
        {error, bad_name} ->
            case code:lib_dir(edoc) of
                {error, bad_name} ->
                    [];
                EdocDir ->
                    [erldocs_util:jname(EdocDir, "priv")]
            end;
        DocgenDir ->
            [ erldocs_util:jname(DocgenDir, "dtd")
            , erldocs_util:jname(DocgenDir, "dtd_html_entities")
            ]
    end.

is_buildable (erlref) -> true;
is_buildable (cref) -> true;
is_buildable (_Type) -> false.
