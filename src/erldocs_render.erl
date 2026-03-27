%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_render).

-export([ render_module/2
        , write_index/2
        , write_javascript_index/2
        , copy_static_files/1
        , index_items/1
        ]).

-include("erldocs.hrl").

copy_static_files (Conf) ->
    Dest = erldocs_util:kf(dest, Conf),
    {ok, ErlDocsCSS} = erldocs_css_dtl:render([]),
    edoc_lib:write_file(ErlDocsCSS, Dest, "erldocs.css"),
    {ok, ErlDocsJS } =  erldocs_js_dtl:render([]),
    edoc_lib:write_file(ErlDocsJS,  Dest, "erldocs.js"),
    {ok, Jquery    } =   jquery_js_dtl:render([]),
    edoc_lib:write_file(Jquery,     Dest, "jquery.js"),
    ok.

render_module (Conf, #module_doc{render_mode = standalone} = ModuleDoc) ->
    render_standalone_module(Conf, ModuleDoc);
render_module (Conf, #module_doc{app = App, module = Mod, blocks = Content}) ->
    render_fragment_module(Conf, App, Mod, Content).

render_fragment_module (Conf, App, Mod, Content) ->
    File = erldocs_util:jname([erldocs_util:kf(dest, Conf), App, Mod ++ ".html"]),
    erldocs_util:mkdir_p(erldocs_util:dname(File) ++ "/"),
    Base = case erldocs_util:kf(base, Conf) of
               "./" -> "../";
               Other -> Other
           end,
    Args = [ {base, Base}
           , {search_base, "../"}
           , {title, Mod ++ " (" ++ App ++ ") - "}
           , {content, Content}
           , {ga, erldocs_util:kf(ga, Conf)}
           ],
    {ok, Data} = erldocs_dtl:render(Args),
    ok = file:write_file(File, Data).

render_standalone_module (Conf, #module_doc{app = App, module = Mod, summary = Summary,
                                            metadata = Metadata}) ->
    DestRoot = erldocs_util:kf(dest, Conf),
    HtmlFile = proplists:get_value(source_file, Metadata),
    SupportFiles = proplists:get_value(support_files, Metadata, []),
    Html0 = read_text_file(HtmlFile),
    Html = erldocs_collect_modern:rewrite_standalone_links(Html0, App),
    Content = normalize_standalone_fragment(Mod, Summary, Html),
    ok = render_fragment_module(Conf, App, Mod, Content),
    copy_support_files(erldocs_util:jname([DestRoot, App, "_assets"]), SupportFiles).

copy_support_files (_DestRoot, []) ->
    ok;
copy_support_files (DestRoot, [Source|Rest]) ->
    BaseName = erldocs_util:bname(Source),
    Dest = erldocs_util:jname(DestRoot, BaseName),
    ok = erldocs_util:copy_path(Source, Dest),
    copy_support_files(DestRoot, Rest).

read_text_file (Path) ->
    {ok, Data} = file:read_file(Path),
    binary_to_list(Data).

normalize_standalone_fragment (Mod, Summary, Html) ->
    Moduledoc = strip_summary_paragraph(extract_moduledoc(Html), Summary),
    Details = extract_detail_sections(Html),
    Types = [render_standalone_detail(Mod, type, Chunk)
             || Chunk <- Details, detail_kind(Chunk) =:= type],
    Functions = [render_standalone_detail(Mod, function, Chunk)
                 || Chunk <- Details, detail_kind(Chunk) =:= function],
    [ "<h1>", Mod, "</h1>\n"
    , case Summary of
          [] -> [];
          _  -> ["<h2 class=\"modsummary\">", Summary, "</h2>\n"]
      end
    , "<div class=\"description\">\n", Moduledoc, "\n</div>\n"
    , render_standalone_category("types", "Types", Types)
    , render_standalone_category("functions", "Functions", Functions)
    ].

render_standalone_category (_Id, _Title, []) ->
    [];
render_standalone_category (Id, Title, Items) ->
    [ "<div id=\"", Id, "\" class=\"category\"><h4><a href=\"#", Id, "\">", Title,
      "</a></h4><hr/>\n"
    , Items
    , "</div>\n"
    ].

render_standalone_detail (Mod, Kind, Chunk) ->
    Id = detail_id(Chunk),
    Heading = detail_heading(Mod, Kind, Chunk),
    TypeDesc = detail_type_desc(Kind, Chunk),
    Description = detail_description(Chunk),
    KindClass = case Kind of
                    type -> "type";
                    function -> "function"
                end,
    [ "<div class=\"", KindClass, "\">\n"
    , "<h3 id=\"", Id, "\">", Heading, "</h3>\n"
    , TypeDesc
    , "<div class=\"description\">\n", Description, "\n</div>\n"
    , "</div>\n"
    ].

detail_kind (Chunk) ->
    case detail_id(Chunk) of
        "t:" ++ _ -> type;
        _ -> function
    end.

detail_id (Chunk) ->
    case re:run(Chunk, "<section class=\"detail\" id=\"([^\"]+)\"",
                [{capture, [1], list}]) of
        {match, [Id]} -> Id;
        nomatch -> ""
    end.

detail_heading (Mod, function, Chunk) ->
    case {multi_clause_spec(detail_spec_html(Chunk)), detail_signature_heading(Chunk)} of
        {true, Heading} when Heading =/= [] ->
            maybe_prefix_module(Mod, Heading);
        _ ->
            case function_spec_parts(detail_spec_html(Chunk)) of
                {Header, _Args} when Header =/= [] ->
                    maybe_prefix_module(Mod, Header);
                _ ->
                    case detail_signature_heading(Chunk) of
                        [] -> detail_id(Chunk);
                        Heading -> maybe_prefix_module(Mod, Heading)
                    end
            end
    end;
detail_heading (_Mod, type, Chunk) ->
    case type_spec_heading(detail_spec_html(Chunk)) of
        [] ->
            case re:run(Chunk, "<h1 class=\"signature\"[^>]*>(.*?)</h1>",
                        [dotall, ungreedy, {capture, [1], list}]) of
                {match, [HeadingHtml]} -> strip_tags(HeadingHtml);
                nomatch -> detail_id(Chunk)
            end;
        Heading ->
            cleanup_type_heading(Heading)
    end.

detail_type_desc (function, Chunk) ->
    case multi_clause_spec(detail_spec_html(Chunk)) of
        true ->
            [];
        false ->
            case function_spec_parts(detail_spec_html(Chunk)) of
                {_Header, []} ->
                    [];
                {Header, Args} ->
                    FilteredArgs = filter_function_args(Header, Args),
                    ReturnArgs = function_return_args(Header, Args),
                    DisplayArgs0 = FilteredArgs ++ ReturnArgs,
                    DisplayArgs = expand_type_desc_args(DisplayArgs0, Args),
                    case DisplayArgs of
                        [] ->
                            [];
                        _ ->
                            RenderArgs = normalize_type_desc_args(DisplayArgs),
                            [ "<ul class=\"type_desc\">"
                            , [[ "<li><code>", legacy_type_desc(Arg), "</code></li>" ] || Arg <- RenderArgs]
                            , "</ul>\n"
                            ]
                    end
            end
    end;
detail_type_desc (type, _Chunk) ->
    [].

maybe_prefix_module (Mod, Heading) ->
    case string:find(strip_tags(Heading), ":") of
        nomatch -> Mod ++ ":" ++ Heading;
        _ -> Heading
    end.

detail_signature_heading (Chunk) ->
    case re:run(Chunk, "<h1 class=\"signature\"[^>]*>(.*?)</h1>",
                [dotall, ungreedy, {capture, [1], list}]) of
        {match, [HeadingHtml]} -> strip_tags(HeadingHtml);
        nomatch -> []
    end.

legacy_type_desc (Arg) ->
    Arg1 = replace_top_level_type_separator(Arg),
    Arg2 = re:replace(Arg1,
                      "<a href=\"[^\"]*#t:pos_integer/0\">pos_integer</a>\\(\\)",
                      "integer() >= 1",
                      [{return, list}]),
    Arg3 = re:replace(Arg2,
                      "<a href=\"[^\"]*#t:non_neg_integer/0\">non_neg_integer</a>\\(\\)",
                      "integer() >= 0",
                      [{return, list}]),
    Arg4 = re:replace(Arg3, "pos_integer\\(\\)", "integer() >= 1", [{return, list}]),
    re:replace(Arg4, "non_neg_integer\\(\\)", "integer() >= 0", [{return, list}]).

replace_top_level_type_separator (Arg) ->
    case re:run(Arg,
                "^\\s*([A-Za-z_][A-Za-z0-9_]*(?:\\s*=\\s*[A-Za-z_][A-Za-z0-9_]*)*)\\s*::\\s*(.*)$",
                [{capture, [1, 2], list}]) of
        {match, [Lhs, Rhs]} ->
            Lhs ++ " = " ++ Rhs;
        nomatch ->
            Arg
    end.

normalize_type_desc_args (Args) ->
    normalize_type_desc_args(Args, []).

normalize_type_desc_args ([], Acc) ->
    lists:reverse(Acc);
normalize_type_desc_args ([Arg | Rest], Acc) ->
    case same_rhs_group(Arg, Rest) of
        {Merged, Remaining} ->
            normalize_type_desc_args(Remaining, [Merged | Acc]);
        false ->
            normalize_type_desc_args(Rest, [Arg | Acc])
    end.

same_rhs_group (Arg, Rest) ->
    case arg_assignment(Arg) of
        {Names, Rhs} ->
            {MoreNames, Remaining} = same_rhs_group(Rest, rhs_key(Rhs), []),
            case MoreNames of
                [] ->
                    false;
                _ ->
                    {string:join(Names ++ MoreNames, " = ") ++ " = " ++ Rhs, Remaining}
            end;
        false ->
            false
    end.

same_rhs_group ([], _RhsKey, Acc) ->
    {[], lists:reverse(Acc)};
same_rhs_group ([Arg | Rest], RhsKey, Acc) ->
    case arg_assignment(Arg) of
        {Names, Rhs} ->
            case rhs_key(Rhs) =:= RhsKey of
                true ->
                    {MoreNames, Remaining} = same_rhs_group(Rest, RhsKey, Acc),
                    {Names ++ MoreNames, Remaining};
                false ->
                    same_rhs_group(Rest, RhsKey, [Arg | Acc])
            end;
        _ ->
            same_rhs_group(Rest, RhsKey, [Arg | Acc])
    end.

rhs_key (Rhs) ->
    normalize_text(strip_tags(Rhs)).

arg_assignment (Arg) ->
    case re:run(Arg,
                "^\\s*([A-Za-z_][A-Za-z0-9_]*(?:\\s*=\\s*[A-Za-z_][A-Za-z0-9_]*)*)\\s*(::|=)\\s*(.*)$",
                [{capture, [1, 3], list}]) of
        {match, [Lhs, Rhs]} ->
            {split_assignment_names(Lhs), string:trim(Rhs)};
        nomatch ->
            false
    end.

split_assignment_names (Lhs) ->
    [string:trim(Name) || Name <- string:split(Lhs, "=", all), Name =/= []].

detail_description (Chunk) ->
    Notes = detail_notes(Chunk),
    Docstring = detail_docstring(Chunk),
    [Notes, Docstring].

detail_notes (Chunk) ->
    Matches = case re:run(Chunk, "<span class=\"note\">(.*?)</span>",
                          [global, dotall, ungreedy, {capture, [1], list}]) of
                  {match, List} -> List;
                  nomatch -> []
              end,
    Notes = [Normalized
             || [Note] <- Matches,
                Normalized <- [normalize_note(strip_tags(Note))],
                Normalized =/= []],
    [[ "<p>", Note, "</p>\n" ] || Note <- Notes].

normalize_note (Text) ->
    Normalized = normalize_text(Text),
    Lower = string:to_lower(Normalized),
    case lists:any(fun (Needle) ->
                           string:str(Lower, Needle) > 0
                   end,
                   ["allowed in guard tests",
                    "allowed in guards tests",
                    "guard-bif"]) of
        true ->
            "Allowed in guard tests.";
        false ->
            []
    end.

detail_docstring (Chunk) ->
    case re:run(Chunk, "<section class=\"docstring\">(.*)</section>\\s*</section>",
                [dotall, ungreedy, {capture, [1], list}]) of
        {match, [Docstring]} ->
            normalize_docstring(strip_standalone_noise(Docstring));
        nomatch ->
            []
    end.

normalize_docstring (Html) ->
    Rewrites =
        [ {"<h2[^>]*class=\"section-heading\"[^>]*>.*?<span class=\"text\">Examples?</span></h2>",
           "<p><strong>Examples:</strong></p>"}
        , {"<a[^>]*class=\"hover-link\"[^>]*>.*?</a>", ""}
        , {"<a[^>]*class=\"detail-link\"[^>]*>.*?</a>", ""}
        , {"<a[^>]*class=\"icon-action\"[^>]*>.*?</a>", ""}
        , {"<i class=\"ri-[^\"]+\"[^>]*></i>", ""}
        , {"<span class=\"sr-only\">.*?</span>", ""}
        , {"<section role=\"note\" class=\"admonition info\">", "<div class=\"note\">"}
        , {"<section role=\"note\" class=\"admonition warning\">", "<div class=\"warning\">"}
        , {"<section role=\"note\" class=\"admonition note\">", "<div class=\"note\">"}
        , {"<h4 class=\"admonition-title info\">Change</h4>", "<h2>Note!</h2>"}
        , {"<h4 class=\"admonition-title info\">Note</h4>", "<h2>Note!</h2>"}
        , {"<h4 class=\"admonition-title warning\">Warning</h4>", "<h2>Warning!</h2>"}
        , {"</section>", "</div>"}
        ],
    Html1 =
        lists:foldl(fun ({Pattern, Replacement}, Acc) ->
                            re:replace(Acc, Pattern, Replacement,
                                       [global, dotall, {return, list}])
                    end, Html, Rewrites),
    re:replace(Html1, "Allowed in guards tests", "Allowed in guard tests",
               [global, {return, list}]).

detail_spec_html (Chunk) ->
    case re:run(Chunk, "<div class=\"specs\">(.*?)</div>",
                [dotall, ungreedy, {capture, [1], list}]) of
        {match, [SpecHtml]} ->
            normalize_spec_html(SpecHtml);
        nomatch ->
            []
    end.

normalize_spec_html (SpecHtml) ->
    Html0 = re:replace(SpecHtml, "<pre[^>]*>|</pre>", "", [global, {return, list}]),
    Html1 = re:replace(Html0, "<span class=\"attribute\">-spec</span>\\s*", "", [{return, list}]),
    Html2 = re:replace(Html1, "<span class=\"attribute\">-type</span>\\s*", "", [{return, list}]),
    Html3 = string:trim(Html2),
    case lists:reverse(Html3) of
        [$.|Rest] -> lists:reverse(Rest);
        _ -> Html3
    end.

multi_clause_spec (SpecHtml) ->
    string:str(SpecHtml, ";") > 0.

function_spec_parts ([]) ->
    {[], []};
function_spec_parts (SpecHtml) ->
    case split_when_clause(SpecHtml) of
        {Header, WhenPart} ->
            {string:trim(Header), split_spec_args(WhenPart)};
        false ->
            {string:trim(SpecHtml), []}
    end.

split_when_clause (SpecHtml) ->
    case re:run(SpecHtml, "^(.*?)\\s+when\\s+(.*)$",
                [dotall, ungreedy, {capture, [1,2], list}]) of
        {match, [Header, WhenPart]} ->
            {Header, WhenPart};
        nomatch ->
            false
    end.

filter_function_args (_Header, []) ->
    [];
filter_function_args (Header, Args) ->
    case header_arg_names(Header) of
        [] -> Args;
        Names ->
            [Arg || Arg <- Args, lists:member(arg_name(Arg), Names)]
    end.

function_return_args (_Header, []) ->
    [];
function_return_args (Header, Args) ->
    Names = header_return_names(Header),
    [Arg || Name <- Names,
            Arg <- Args,
            arg_name(Arg) =:= Name].

expand_type_desc_args (DisplayArgs, AllArgs) ->
    NamesByArg = [{arg_name(Arg), Arg} || Arg <- AllArgs],
    expand_type_desc_args(DisplayArgs, NamesByArg, used_type_vars(DisplayArgs, NamesByArg)).

expand_type_desc_args (DisplayArgs, NamesByArg, NeededNames) ->
    ExtraArgs = [Arg || {Name, Arg} <- NamesByArg,
                        Name =/= [],
                        lists:member(Name, NeededNames),
                        not lists:member(Arg, DisplayArgs)],
    case ExtraArgs of
        [] ->
            [Arg || {_Name, Arg} <- NamesByArg, lists:member(Arg, DisplayArgs)];
        _ ->
            NewDisplayArgs = DisplayArgs ++ ExtraArgs,
            expand_type_desc_args(NewDisplayArgs, NamesByArg, used_type_vars(NewDisplayArgs, NamesByArg))
    end.

used_type_vars (Args, NamesByArg) ->
    Names = [Name || {Name, _Arg} <- NamesByArg, Name =/= []],
    lists:usort(
      lists:append([referenced_type_vars(Arg, Names) || Arg <- Args])).

header_arg_names (Header) ->
    case re:run(Header, "^[^(]+\\((.*)\\)\\s*->", [{capture, [1], list}]) of
        {match, [ArgsStr]} ->
            [string:trim(strip_tags(Name))
             || Name <- split_spec_args(ArgsStr),
                Name =/= []];
        nomatch ->
            []
    end.

header_return_names (Header) ->
    case re:run(Header, "->\\s*(.*?)\\s*$", [{capture, [1], list}]) of
        {match, [ReturnPart]} ->
            Names = case re:run(strip_tags(ReturnPart), "([A-Z_][A-Za-z0-9_]*)",
                                [global, {capture, [1], list}]) of
                        {match, Matches} -> [Name || [Name] <- Matches];
                        nomatch -> []
                    end,
            lists:usort(Names);
        nomatch ->
            []
    end.

arg_name (Arg) ->
    case re:run(Arg, "^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*(::|=)", [{capture, [1], list}]) of
        {match, [Name]} -> Name;
        nomatch -> ""
    end.

referenced_type_vars (Arg, KnownNames) ->
    case re:run(Arg, "(::|=)\\s*(.*)$", [{capture, [2], list}]) of
        {match, [Rhs]} ->
            Tokens = case re:run(strip_tags(Rhs), "([A-Z_][A-Za-z0-9_]*)",
                                 [global, {capture, [1], list}]) of
                         {match, Matches} -> [Token || [Token] <- Matches];
                         nomatch -> []
                     end,
            [Token || Token <- Tokens, lists:member(Token, KnownNames)];
        nomatch ->
            []
    end.

type_spec_heading ([]) ->
    [];
type_spec_heading (SpecHtml) ->
    case split_once(SpecHtml, " :: ") of
        {Name, Rest} ->
            string:trim(Name) ++ " = " ++ string:trim(Rest);
        false ->
            string:trim(SpecHtml)
    end.

cleanup_type_heading (Heading) ->
    case re:run(Heading, "^([a-zA-Z0-9_]+\\(\\)) = <a href=\"#t:[^\"]+\">([a-zA-Z0-9_]+)</a>\\(\\)$",
                [{capture, [1,2], list}]) of
        {match, [Lhs, Rhs]} ->
            case Lhs =:= Rhs ++ "()" of
                true -> Lhs;
                false -> Heading
            end;
        _ ->
            Heading
    end.

split_once (Str, Sep) ->
    case string:split(Str, Sep, leading) of
        [L, R] -> {L, R};
        _ -> false
    end.

split_spec_args (WhenPart) ->
    split_spec_args(WhenPart, [], [], 0, false, false).

split_spec_args ([], Current, Acc, _Depth, _InTag, _InEntity) ->
    finalize_spec_arg(Current, Acc);
split_spec_args ([$<|Rest], Current, Acc, Depth, false, InEntity) ->
    split_spec_args(Rest, [$<|Current], Acc, Depth, true, InEntity);
split_spec_args ([$>|Rest], Current, Acc, Depth, true, InEntity) ->
    split_spec_args(Rest, [$>|Current], Acc, Depth, false, InEntity);
split_spec_args ([$&|Rest], Current, Acc, Depth, InTag, false) ->
    split_spec_args(Rest, [$&|Current], Acc, Depth, InTag, true);
split_spec_args ([$;|Rest], Current, Acc, Depth, InTag, true) ->
    split_spec_args(Rest, [$;|Current], Acc, Depth, InTag, false);
split_spec_args ([$(|Rest], Current, Acc, Depth, InTag, InEntity) ->
    split_spec_args(Rest, [$(|Current], Acc, Depth + 1, InTag, InEntity);
split_spec_args ([$[|Rest], Current, Acc, Depth, InTag, InEntity) ->
    split_spec_args(Rest, [$[|Current], Acc, Depth + 1, InTag, InEntity);
split_spec_args ([${|Rest], Current, Acc, Depth, InTag, InEntity) ->
    split_spec_args(Rest, [${|Current], Acc, Depth + 1, InTag, InEntity);
split_spec_args ([$)|Rest], Current, Acc, Depth, InTag, InEntity) when Depth > 0 ->
    split_spec_args(Rest, [$)|Current], Acc, Depth - 1, InTag, InEntity);
split_spec_args ([$]|Rest], Current, Acc, Depth, InTag, InEntity) when Depth > 0 ->
    split_spec_args(Rest, [$]|Current], Acc, Depth - 1, InTag, InEntity);
split_spec_args ([$}|Rest], Current, Acc, Depth, InTag, InEntity) when Depth > 0 ->
    split_spec_args(Rest, [$}|Current], Acc, Depth - 1, InTag, InEntity);
split_spec_args ([$,|Rest], Current, Acc, 0, false, false) ->
    split_spec_args(Rest, [], finalize_spec_arg(Current, Acc), 0, false, false);
split_spec_args ([C|Rest], Current, Acc, Depth, InTag, InEntity) ->
    split_spec_args(Rest, [C|Current], Acc, Depth, InTag, InEntity).

finalize_spec_arg (Current, Acc) ->
    case string:trim(lists:reverse(Current)) of
        [] -> Acc;
        Arg -> Acc ++ [Arg]
    end.

extract_moduledoc (Html) ->
    extract_section_inner(Html, "<section id=\"moduledoc\">").

strip_summary_paragraph (Html, []) ->
    Html;
strip_summary_paragraph (Html, Summary) ->
    Trimmed = string:trim(Html, leading),
    SummaryText = normalize_text(Summary),
    case string:str(Trimmed, "</p>") of
        0 ->
            Trimmed;
        EndPos ->
            {FirstChunk, Rest} = lists:split(EndPos + length("</p>") - 1, Trimmed),
            case normalize_text(strip_tags(FirstChunk)) =:= SummaryText of
                true -> Rest;
                false -> Trimmed
            end
    end.

extract_detail_sections (Html) ->
    extract_detail_sections(Html, []).

extract_detail_sections (Html, Acc) ->
    case string:str(Html, "<section class=\"detail\"") of
        0 ->
            lists:reverse(Acc);
        Pos ->
            Start = lists:nthtail(Pos - 1, Html),
            {Chunk, Rest} = take_balanced_section(Start),
            extract_detail_sections(Rest, [Chunk|Acc])
    end.

take_balanced_section (Html) ->
    take_balanced_section(Html, 0, []).

take_balanced_section (Html, Depth, Acc) ->
    OpenPos = string:str(Html, "<section"),
    ClosePos = string:str(Html, "</section>"),
    case choose_next_tag(OpenPos, ClosePos) of
        open ->
            PrefixLen = OpenPos + length("<section") - 1,
            {Prefix, Rest} = lists:split(PrefixLen, Html),
            take_balanced_section(Rest, Depth + 1, [Acc, Prefix]);
        close when Depth =:= 1 ->
            PrefixLen = ClosePos + length("</section>") - 1,
            {Prefix, Rest} = lists:split(PrefixLen, Html),
            {lists:flatten([Acc, Prefix]), Rest};
        close ->
            PrefixLen = ClosePos + length("</section>") - 1,
            {Prefix, Rest} = lists:split(PrefixLen, Html),
            take_balanced_section(Rest, Depth - 1, [Acc, Prefix])
    end.

choose_next_tag (0, _ClosePos) ->
    close;
choose_next_tag (OpenPos, 0) when OpenPos > 0 ->
    open;
choose_next_tag (OpenPos, ClosePos) when OpenPos < ClosePos ->
    open;
choose_next_tag (_OpenPos, _ClosePos) ->
    close.

extract_section_inner (Html, Marker) ->
    case string:str(Html, Marker) of
        0 ->
            [];
        Pos ->
            Start = lists:nthtail(Pos - 1, Html),
            {Chunk, _Rest} = take_balanced_section(Start),
            case re:run(Chunk, "^<section[^>]*>(.*)</section>$",
                        [dotall, {capture, [1], list}]) of
                {match, [Inner]} -> Inner;
                nomatch -> []
            end
    end.

normalize_text (Text) ->
    Stripped = string:trim(Text),
    Lines = string:tokens(Stripped, "\r\n"),
    string:join([string:trim(Line) || Line <- Lines, Line =/= ""], " ").

strip_tags (Html) ->
    normalize_text(re:replace(Html, "<[^>]+>", "", [global, {return, list}])).

strip_standalone_noise (Html) ->
    strip_specs(strip_scripts(Html)).

strip_scripts (Html) ->
    re:replace(Html, "<script\\b[^>]*>.*?</script>", "", [global, dotall, {return, list}]).

strip_specs (Html) ->
    re:replace(Html, "<div class=\"specs\">.*?</div>", "", [global, dotall, {return, list}]).

write_index (Conf, ModuleDocs) ->
    SortedIndex = sort_index(index_items(ModuleDocs)),
    Html = [ "<h1>Module Index</h1><hr/><br>\n<div>"
           , erldocs_render_legacy_xml:xml_to_html(index_to_xml(SortedIndex))
           , "</div>"
           ],
    Args = [ {base, erldocs_util:kf(base, Conf)}
           , {search_base, "./"}
           , {title, "Module Index"}
           , {content, Html}
           , {ga, erldocs_util:kf(ga, Conf)}
           ],
    {ok, Data} = erldocs_dtl:render(Args),
    Path = erldocs_util:jname(erldocs_util:kf(dest, Conf), "index.html"),
    ok = file:write_file(Path, Data).

write_javascript_index (Conf, ModuleDocs) ->
    SortedIndex = sort_index(index_items(ModuleDocs)),
    IndexStr = iolists_tl(
                 [ [ ",['", js_strip(A)
                   , "','", js_strip(B)
                   , "','", js_strip(C)
                   , "','", js_strip(D), "']"
                   ]
                   || {A,B,C,D} <- SortedIndex ]
                ),
    Data = ["var index = [", IndexStr, "];"],
    Path = erldocs_util:jname(erldocs_util:kf(dest, Conf), "erldocs_index.js"),
    ok = file:write_file(Path, Data).

index_items (ModuleDocs) ->
    Apps = lists:usort([App || #module_doc{app = App} <- ModuleDocs]),
    AppItems = [{"app", App, App, "[application]"} || App <- Apps],
    ModuleItems =
        lists:flatmap(fun (#module_doc{app = App, module = Mod, summary = Summary,
                                       functions = Functions}) ->
                              [{"mod", App, Mod, Summary}
                               | [{"fun", App, Mod ++ ":" ++ Id, FunSummary}
                                  || #function_doc{id = Id, summary = FunSummary} <- Functions]]
                      end, ModuleDocs),
    AppItems ++ ModuleItems.

index_to_xml (SortedIndex) ->
    [case I of
         {"app", App, _, _Sum} ->
             {h4, [{id, "app-" ++ App}], [App]};
         {"mod", App, Mod, Sum} ->
             Url = erldocs_util:jname(App, Mod ++ ".html"),
             {p, [], [ {a, [{href, Url}], [Mod]}
                     , {br, [], []}
                     , Sum
                     ]};
         {"fun", _App, _MFA, _Sum} ->
             <<>>;
         {"type", _App, _MFA, _Sum} ->
             <<>>
     end || I <- SortedIndex].

sort_index (Index) ->
    lists:sort(fun compare_index_items/2, Index).

compare_index_items (Lhs, Rhs) ->
    index_ordering(Lhs) =< index_ordering(Rhs).

index_ordering ({Type, App, Mod, _Sum}) ->
    [ string:to_lower(App)
    , index_item(Type)
    , string:to_lower(Mod)
    ].

index_item ("app") -> 1;
index_item ("mod") -> 2;
index_item ("fun") -> 3;
index_item ("type") -> 4.

js_strip (Str) ->
    lists:flatten([js_char(C) || C <- Str, C /= $\n, C /= $\r]).

js_char ($\\) ->
    "\\\\";
js_char ($') ->
    "\\'";
js_char ($\t) ->
    " ";
js_char (C) ->
    [C].

iolists_tl ([H|T])
  when is_list(H) ->
    [iolists_tl(H)|T];
iolists_tl ([_|T]) ->
    T.
