%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_collect_modern).

-compile({nowarn_unused_function, [{collect_file, 3}]}).

-export([ collect_app/4
        , rewrite_standalone_links/2
        ]).

-ifdef(TEST).
-export([ collect_file/3
        , collect_file/5
        , extract_content/1
        , support_files/1
        ]).
-endif.

-include("erldocs.hrl").
-include_lib("xmerl/include/xmerl.hrl").

-define(log(Str, Args), io:format(Str ++ "\n", Args)).

collect_app (Conf, IncludePaths, AppName, AppDir) ->
    ErlFiles = maybe_add_otp_preloaded(AppName, AppDir)
        ++ filelib:wildcard(erldocs_util:jname(AppDir, "*.erl"))
        ++ filelib:fold_files(erldocs_util:jname(AppDir, "src"), "\\.erl$", true,
                              fun erldocs_util:cons/2, []),
    PreferExistingHtml = erldocs_util:kf(building_otp, Conf) =/= false,
    Map = fun (File) -> collect_file(AppName, AppDir, File, IncludePaths, PreferExistingHtml) end,
    erldocs_util:pmapreduce(Map, fun lists:append/2, [], lists:usort(ErlFiles)).

maybe_add_otp_preloaded ("erts", AppDir) ->
    filelib:fold_files(erldocs_util:jname([AppDir, "preloaded", "src"]), "\\.erl$", true,
                       fun erldocs_util:cons/2, []);
maybe_add_otp_preloaded (_AppName, _AppDir) ->
    [].

collect_file (AppName, File, IncludePaths) ->
    collect_file(AppName, filename:dirname(filename:dirname(File)), File, IncludePaths, false).

collect_file (AppName, AppDir, File, IncludePaths, PreferExistingHtml) ->
    Module = erldocs_util:bname(File, ".erl"),
    case erldocs_build:is_ignored(AppName, Module) of
        true ->
            [];
        false ->
            case collect_from_existing_html(AppName, AppDir, Module, PreferExistingHtml) of
                {ok, Docs} ->
                    Docs;
                false ->
                    collect_from_source(AppName, AppDir, File, Module, IncludePaths)
            end
    end.

collect_from_existing_html (AppName, AppDir, Module, PreferExistingHtml) ->
    HtmlFile = erldocs_util:jname([AppDir, "doc", "html", Module ++ ".html"]),
    case {PreferExistingHtml, file:read_file(HtmlFile)} of
        {true, {ok, Data}} ->
            Html = binary_to_list(Data),
            Summary = extract_html_summary(Html),
            Functions = extract_function_docs_from_html(Html),
            Types = extract_type_docs_from_html(Html),
            Metadata = standalone_metadata(AppName, AppDir, HtmlFile),
            {ok, [erldocs_model:module_doc(AppName, Module, modern_edoc, standalone,
                                           Summary, [], Functions, Types, Metadata)]};
        {true, {error, _}} ->
            {ok, []};
        _ ->
            false
    end.

collect_from_source (AppName, AppDir, File, Module, IncludePaths) ->
    Opts = [ {includes, IncludePaths}
           , {preprocess, true}
           , return_entries
           , private
           , hidden
           ],
    try edoc:get_doc(File, Opts) of
        {_M, Doc, _Entries} ->
            Html = edoc:layout(Doc),
            Summary = module_summary(Doc),
            Functions = function_docs(Doc),
            Content = extract_content(Html),
            [erldocs_model:module_doc(AppName, Module, modern_edoc,
                                      Summary, Content, Functions, [], [])]
    catch
        Class:Reason ->
            ?log("Error generating modern docs for ~s (~p): ~p", [File, Class, Reason]),
            fallback_to_existing_html(AppName, AppDir, Module)
    end.

fallback_to_existing_html (AppName, AppDir, Module) ->
    HtmlFile = erldocs_util:jname([AppDir, "doc", "html", Module ++ ".html"]),
    case file:read_file(HtmlFile) of
        {ok, _Data} ->
            Html = read_html(HtmlFile),
            Summary = extract_html_summary(Html),
            Functions = extract_function_docs_from_html(Html),
            Types = extract_type_docs_from_html(Html),
            Metadata = standalone_metadata(AppName, AppDir, HtmlFile),
            [erldocs_model:module_doc(AppName, Module, modern_edoc, standalone,
                                      Summary, [], Functions, Types, Metadata)];
        {error, _} ->
            []
    end.

standalone_metadata (AppName, AppDir, HtmlFile) ->
    HtmlRoot = erldocs_util:jname([AppDir, "doc", "html"]),
    [ {source_file, HtmlFile}
    , {standalone_root, HtmlRoot}
    , {support_files, support_files(HtmlRoot)}
    , {link_strategy, rewrite}
    , {public_module, true}
    , {app, AppName}
    ].

support_files (HtmlRoot) ->
    Candidates = [ erldocs_util:jname(HtmlRoot, "assets")
                 , erldocs_util:jname(HtmlRoot, "dist")
                 , erldocs_util:jname(HtmlRoot, "docs_config.js")
                 ],
    [Path || Path <- Candidates, filelib:is_dir(Path) orelse filelib:is_file(Path)].

read_html (HtmlFile) ->
    {ok, Data} = file:read_file(HtmlFile),
    binary_to_list(Data).

module_summary (Doc) ->
    normalize_text(xpath_string("string(description/briefDescription)", Doc)).

function_docs (Doc) ->
    [begin
         Name = attr_value(name, Fun),
         Arity = attr_value(arity, Fun),
         Label = attr_value(label, Fun),
         Summary = normalize_text(xpath_string("string(description/briefDescription)", Fun)),
         Signature = case xpath_string("string(typespec)", Fun) of
                         [] -> [];
                         TypeSpec -> [normalize_text(TypeSpec)]
                     end,
         erldocs_model:function_doc(Name, list_to_integer(Arity), Name ++ "/" ++ Arity,
                                    Summary, normalize_heading(Label, Name, Arity),
                                    [], Signature, [])
     end || Fun <- xmerl_xpath:string("//functions/function", Doc)].

normalize_heading ([], Name, Arity) ->
    Name ++ "/" ++ Arity;
normalize_heading (Heading, _Name, _Arity) ->
    string:replace(Heading, "-", "/", leading).

attr_value (Name, #xmlElement{attributes = Attrs}) ->
    case lists:keyfind(Name, #xmlAttribute.name, Attrs) of
        #xmlAttribute{value = Value} -> Value;
        false -> ""
    end.

xpath_string (Path, Node) ->
    case xmerl_xpath:string(Path, Node) of
        {xmlObj, string, Value} -> Value;
        Value when is_list(Value) -> Value;
        _ -> ""
    end.

normalize_text (Text) when is_list(Text) ->
    Cleaned = re:replace(Text, "[\\x{00A0}\\x{2007}\\x{202F}]", " ", [global, unicode, {return, list}]),
    Stripped = string:trim(Cleaned),
    Lines = string:tokens(Stripped, "\r\n"),
    string:join([string:trim(Line) || Line <- Lines, Line =/= ""], " ");
normalize_text (_) ->
    "".

extract_content (Html) ->
    Content = case re:run(Html,
                          "(<h1>.*)<div class=\"navbar\"><a name=\"#navbar_bottom\">",
                          [dotall, ungreedy, {capture,[1],list}]) of
                  {match, [Section]} ->
                      Section;
                  nomatch ->
                      case re:run(Html, "<body[^>]*>(.*)</body>",
                                  [dotall, ungreedy, {capture,[1],list}]) of
                          {match, [Body]} -> Body;
                          nomatch -> Html
                      end
              end,
    string:trim(Content).

extract_html_summary (Html) ->
    case re:run(Html, "<p>([^<]+)</p>", [dotall, ungreedy, {capture,[1],list}]) of
        {match, [Summary]} ->
            normalize_text(Summary);
        nomatch ->
            ""
    end.

extract_function_docs_from_html (Html) ->
    [begin
         {Name, Arity} = split_name_and_arity(Id),
         Summary = normalize_text(strip_tags(SummaryHtml)),
         erldocs_model:function_doc(Name, list_to_integer(Arity), Id,
                                    Summary, Label, [], [], [])
     end || {Id, Label, SummaryHtml} <- extract_summary_rows(Html), not lists:prefix("t:", Id)].

extract_type_docs_from_html (Html) ->
    [begin
         {Name, Arity} = split_type_id(Id),
         Summary = normalize_text(strip_tags(SummaryHtml)),
         erldocs_model:type_doc(Name, list_to_integer(Arity), Id,
                                Label, [], [], false, [{summary, Summary}])
     end || {Id, Label, SummaryHtml} <- extract_summary_rows(Html), lists:prefix("t:", Id)].

extract_summary_rows (Html) ->
    SummaryHtml = extract_summary_section(Html),
    SummaryRows = extract_summary_row_chunks(SummaryHtml, []),
    lists:reverse(lists:foldl(fun extract_summary_row/2, [], SummaryRows)).

extract_summary_section (Html) ->
    case re:run(Html, "<section id=\"summary\">(.*?)</section>",
                [dotall, ungreedy, {capture, [1], list}]) of
        {match, [SummaryHtml]} ->
            SummaryHtml;
        nomatch ->
            Html
    end.

extract_summary_row_chunks (Html, Acc) ->
    case string:str(Html, "<div class=\"summary-row\">") of
        0 ->
            lists:reverse(Acc);
        Pos ->
            Start = lists:nthtail(Pos - 1, Html),
            {Chunk, Rest} = take_balanced_div(Start),
            extract_summary_row_chunks(Rest, [Chunk | Acc])
    end.

take_balanced_div (Html) ->
    take_balanced_div(Html, 0, []).

take_balanced_div (Html, Depth, Acc) ->
    OpenPos = string:str(Html, "<div"),
    ClosePos = string:str(Html, "</div>"),
    case choose_next_div_tag(OpenPos, ClosePos) of
        open ->
            PrefixLen = OpenPos + length("<div") - 1,
            {Prefix, Rest} = lists:split(PrefixLen, Html),
            take_balanced_div(Rest, Depth + 1, [Acc, Prefix]);
        close when Depth =:= 1 ->
            PrefixLen = ClosePos + length("</div>") - 1,
            {Prefix, Rest} = lists:split(PrefixLen, Html),
            {lists:flatten([Acc, Prefix]), Rest};
        close ->
            PrefixLen = ClosePos + length("</div>") - 1,
            {Prefix, Rest} = lists:split(PrefixLen, Html),
            take_balanced_div(Rest, Depth - 1, [Acc, Prefix])
    end.

choose_next_div_tag (0, _ClosePos) ->
    close;
choose_next_div_tag (OpenPos, 0) when OpenPos > 0 ->
    open;
choose_next_div_tag (OpenPos, ClosePos) when OpenPos < ClosePos ->
    open;
choose_next_div_tag (_OpenPos, _ClosePos) ->
    close.

extract_summary_row (Chunk, Acc) ->
    LinkPattern = "<a href=\"#([^\"]+)\"[^>]*translate=\"no\">([^<]+)</a>",
    SummaryPattern = "<div class=\"summary-synopsis\"><p>(.*?)</p>",
    case re:run(Chunk, LinkPattern, [dotall, ungreedy, {capture, [1,2], list}]) of
        {match, [Id, Label]} ->
            SummaryHtml =
                case re:run(Chunk, SummaryPattern, [dotall, ungreedy, {capture, [1], list}]) of
                    {match, [Captured]} -> Captured;
                    nomatch -> []
                end,
            [{Id, Label, SummaryHtml} | Acc];
        _ ->
            Acc
    end.

split_type_id ("t:" ++ Rest) ->
    split_name_and_arity(Rest).

split_name_and_arity (Id) ->
    case re:run(Id, "^(.*)/([0-9]+)$", [{capture, [1,2], list}]) of
        {match, [Name, Arity]} ->
            {Name, Arity};
        nomatch ->
            {Id, "0"}
    end.

strip_tags (Html) ->
    re:replace(Html, "<[^>]+>", "", [global, {return, list}]).

rewrite_standalone_links (Html, AppName) ->
    Rewrites =
        [ {"(href|src)=\"assets/([^\"]+)\"", "\\1=\"./_assets/assets/\\2\""}
        , {"(href|src)=\"dist/([^\"]+)\"", "\\1=\"./_assets/dist/\\2\""}
        , {"(href|src)=\"docs_config\\.js\"", "\\1=\"./_assets/docs_config.js\""}
        , {"action=\"search\\.html\"", "action=\"../index.html\""}
        , {"href=\"\\.\\./\\.\\./\\.\\./\\.\\./doc/index\\.html\"", "href=\"../index.html#app-" ++ AppName ++ "\""}
        , {"href=\"\\.\\./\\.\\./\\.\\./\\.\\./lib/\\.\\./([^/\"]+)/doc/html/([^\"]+)\"", "href=\"../\\1/\\2\""}
        , {"href=\"\\.\\./\\.\\./\\.\\./\\.\\./lib/([^/\"]+)/doc/html/([^\"]+)\"", "href=\"../\\1/\\2\""}
        ],
    lists:foldl(fun ({Pattern, Replacement}, Acc) ->
                        re:replace(Acc, Pattern, Replacement, [global, {return, list}])
                end, Html, Rewrites).
