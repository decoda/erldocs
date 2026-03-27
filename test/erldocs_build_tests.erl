%% Copyright © 2015 Pierre Fenoll ‹pierrefenoll@gmail.com›
%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_build_tests).

-include_lib("eunit/include/eunit.hrl").
-include("erldocs.hrl").

includes_test () ->
    {ok, RepoRoot} = file:get_cwd(),
    IncludePaths = erldocs_build:includes(RepoRoot),
    ?assert(lists:member(filename:join(RepoRoot, "include"), IncludePaths)),
    ?assertEqual([], [Path || Path <- IncludePaths,
                              lists:member("test", filename:split(Path))]).

build_generates_site_test () ->
    FixtureApp = make_fixture_app(),
    Dest = filename:join("/tmp", "erldocs-build-test"),
    Conf = [ {apps, [FixtureApp]}
           , {dest, Dest}
           , {base, "./"}
           , {ga, "test"}
           ],
    ?assertEqual(true, erldocs_build:dispatch(Conf)),
    ?assert(filelib:is_file(filename:join(Dest, "index.html"))),
    ?assert(filelib:is_file(filename:join(Dest, "erldocs_index.js"))),
    ?assert(filelib:is_file(filename:join([Dest, "sample_app", "sample_app.html"]))).

build_generates_standalone_site_test () ->
    FixtureApp = make_html_fixture_app(),
    Dest = filename:join("/tmp", "erldocs-build-standalone-test"),
    Conf = [ {apps, [FixtureApp]}
           , {dest, Dest}
           , {base, "./"}
           , {ga, "test"}
           , {building_otp, {true, "dummy"}}
           ],
    ?assertEqual(true, erldocs_build:build(Conf)),
    Output = filename:join([Dest, "sample_app", "sample_app.html"]),
    ?assert(filelib:is_file(Output)),
    IndexPath = filename:join(Dest, "erldocs_index.js"),
    ?assert(filelib:is_file(IndexPath)),
    {ok, Html} = file:read_file(Output),
    {ok, IndexJs} = file:read_file(IndexPath),
    Text = binary_to_list(Html),
    IndexText = binary_to_list(IndexJs),
    ?assertMatch({match, _}, re:run(Text, "<div id=\"sidebar\" class=\"inactive\">")),
    ?assertEqual(nomatch, re:run(Text, "<nav id=\"sidebar\" class=\"sidebar\">", [{capture, none}])),
    ?assertMatch({match, _}, re:run(Text, "Standalone summary\\.")),
    ?assertEqual({match, [["Standalone summary."]]},
                 re:run(Text, "Standalone summary\\.", [global, {capture, all, list}])),
    ?assertMatch({match, _}, re:run(Text, "<div id=\"functions\" class=\"category\">")),
    ?assertMatch({match, _}, re:run(Text, "<div class=\"function\">")),
    ?assertMatch({match, _}, re:run(Text, "<h3 id=\"hello/0\">sample_app:hello\\(\\) -> ok</h3>")),
    ?assertMatch({match, _}, re:run(Text, "<ul class=\"type_desc\"><li><code>Name = binary\\(\\)</code></li></ul>")),
    ?assertMatch({match, _},
                 re:run(Text,
                        "<h3 id=\"merge/3\">sample_app:merge\\(N, List1, List2\\) -> List3</h3>")),
    ?assertMatch({match, _},
                 re:run(Text,
                        "<ul class=\"type_desc\"><li><code>N = integer\\(\\) >= 1</code></li><li><code>List1 = \\[T1\\]</code></li><li><code>List2 = \\[T2\\]</code></li><li><code>List3 = \\[T1 \\| T2\\]</code></li><li><code>T1 = T2 = term\\(\\)</code></li></ul>")),
    ?assertMatch({match, _},
                 re:run(Text,
                        "<h3 id=\"filter/2\">sample_app:filter\\(Pred, List1\\) -> List2</h3>")),
    ?assertMatch({match, _},
                 re:run(Text,
                        "<ul class=\"type_desc\"><li><code>Pred = fun\\(\\(Elem :: T\\) -> boolean\\(\\)\\)</code></li><li><code>List1 = List2 = \\[T\\]</code></li><li><code>T = term\\(\\)</code></li></ul>")),
    ?assertMatch({match, _},
                 re:run(Text,
                        "<h3 id=\"split/2\">sample_app:split\\(N, List1\\) -> \\{List2, List3\\}</h3>")),
    ?assertMatch({match, _},
                 re:run(Text,
                        "<ul class=\"type_desc\"><li><code>N = integer\\(\\) >= 0</code></li><li><code>List1 = List2 = List3 = \\[T\\]</code></li><li><code>T = term\\(\\)</code></li></ul>")),
    ?assertMatch({match, _},
                 re:run(Text,
                        "<h3 id=\"stats/1\">sample_app:stats\\(Item\\)</h3>")),
    ?assertEqual(nomatch,
                 re:run(Text,
                        "<h3 id=\"stats/1\">.*stats\\(one\\).*stats\\(two\\).*",
                        [dotall, {capture, none}])),
    ?assertEqual(nomatch,
                 re:run(Text,
                        "<h3 id=\"stats/1\">sample_app:stats\\(Item\\)</h3>\\s*<ul class=\"type_desc\">",
                        [dotall, {capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "merge\\(N, List1, List2\\) -> List3\\s+when", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "<span class=\"attribute\">-spec</span>", [{capture, none}])),
    ?assertMatch({match, _}, re:run(IndexText, "sample_app:hello/0")),
    ?assertMatch({match, _}, re:run(IndexText, "sample_app:hello/1")),
    ?assertEqual(nomatch, re:run(IndexText, "sample_app:t:greeting/0", [{capture, none}])),
    ?assertEqual(nomatch, re:run(IndexText, "sample_app:t:name/0", [{capture, none}])),
    ?assert(filelib:is_file(filename:join([Dest, "sample_app", "_assets", "assets", "logo.png"]))),
    ?assert(filelib:is_file(filename:join([Dest, "sample_app", "_assets", "dist", "app.js"]))).

javascript_index_escapes_special_chars_test () ->
    Dest = filename:join("/tmp", "erldocs-index-escape-test"),
    ok = filelib:ensure_dir(filename:join(Dest, "dummy")),
    ModuleDoc = #module_doc{
                   app = "sample_app",
                   module = "sample_mod",
                   summary = "Summary with \\\\xFF and apostrophe ' inside",
                   functions = [#function_doc{
                                   id = "hello/0",
                                   summary = "Function summary with \\\\path and apostrophe ' inside"
                                  }],
                   types = []
                 },
    Conf = [{dest, Dest}],
    ok = erldocs_render:write_javascript_index(Conf, [ModuleDoc]),
    IndexFile = filename:join(Dest, "erldocs_index.js"),
    ?assertEqual("0", string:trim(os:cmd("node -c " ++ IndexFile ++ " >/dev/null 2>&1; echo $?"))).

make_fixture_app () ->
    Root = filename:join("/tmp", "erldocs-sample-app"),
    SrcDir = filename:join([Root, "src"]),
    ok = filelib:ensure_dir(filename:join(SrcDir, "sample_app.erl")),
    Source = "%% -*- coding: utf-8 -*-\n"
             "-module(sample_app).\n\n"
             "-export([hello/0]).\n\n"
             "%% @doc Return a greeting.\n"
             "-spec hello() -> binary().\n"
             "hello () ->\n"
             "    <<\"hello\">>.\n",
    ok = file:write_file(filename:join(SrcDir, "sample_app.erl"), Source),
    AppSrc = "{application, sample_app,\n"
             " [{description, \"Sample app\"}\n"
             " ,{vsn, \"0.1.0\"}\n"
             " ,{modules, [sample_app]}\n"
             " ,{registered, []}\n"
             " ,{applications, [kernel, stdlib]}\n"
             " ]}.\n",
    ok = file:write_file(filename:join(SrcDir, "sample_app.app.src"), AppSrc),
    Root.

make_html_fixture_app () ->
    Root = filename:join("/tmp", "erldocs-standalone-app"),
    SrcDir = filename:join([Root, "src"]),
    HtmlDir = filename:join([Root, "doc", "html"]),
    ok = filelib:ensure_dir(filename:join(SrcDir, "sample_app.erl")),
    ok = filelib:ensure_dir(filename:join(HtmlDir, "sample_app.html")),
    ok = filelib:ensure_dir(filename:join(HtmlDir, "assets/logo.png")),
    ok = filelib:ensure_dir(filename:join(HtmlDir, "dist/app.js")),
    Source = "-module(sample_app).\n-export([hello/0]).\nhello() -> ok.\n",
    Html = "<!DOCTYPE html><html><body>"
           "<nav id=\"sidebar\" class=\"sidebar\"></nav>"
           "<main id=\"content\"><p>Standalone summary.</p>"
           "<section id=\"summary\">"
           "<div class=\"summary-functions summary\">"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#hello/0\" data-no-tooltip=\"\" translate=\"no\">hello()</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Return a greeting.</p></div>"
           "</div>"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#hello/1\" data-no-tooltip=\"\" translate=\"no\">hello(Name)</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Return a personalized greeting.</p></div>"
           "</div>"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#merge/3\" data-no-tooltip=\"\" translate=\"no\">merge(N, List1, List2)</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Merge lists.</p></div>"
           "</div>"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#filter/2\" data-no-tooltip=\"\" translate=\"no\">filter(Pred, List1)</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Filter a list.</p></div>"
           "</div>"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#split/2\" data-no-tooltip=\"\" translate=\"no\">split(N, List1)</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Split a list.</p></div>"
           "</div>"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#stats/1\" data-no-tooltip=\"\" translate=\"no\">stats(Item)</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Multi-clause stats.</p></div>"
           "</div>"
           "</div>"
           "<div class=\"summary-types summary\">"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#t:greeting/0\" data-no-tooltip=\"\" translate=\"no\">greeting()</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Greeting type.</p></div>"
           "</div>"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#t:name/0\" data-no-tooltip=\"\" translate=\"no\">name()</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Name type.</p></div>"
           "</div>"
           "</div>"
           "</section>"
           "<section class=\"detail\" id=\"hello/0\">"
           "<div class=\"detail-header\">"
           "<div class=\"heading-with-actions\">"
           "<h1 class=\"signature\" translate=\"no\">hello()</h1>"
           "<span class=\"note\">(allowed in guards tests)</span>"
           "</div>"
           "</div>"
           "<section class=\"docstring\">"
           "<div class=\"specs\">"
           "<pre translate=\"no\"><span class=\"attribute\">-spec</span> hello() -> ok.</pre>"
           "</div>"
           "<p>Return a greeting.</p>"
           "</section>"
           "</section>"
           "<section class=\"detail\" id=\"hello/1\">"
           "<div class=\"detail-header\">"
           "<div class=\"heading-with-actions\">"
           "<h1 class=\"signature\" translate=\"no\">hello(Name)</h1>"
           "</div>"
           "</div>"
           "<section class=\"docstring\">"
           "<div class=\"specs\">"
           "<pre translate=\"no\"><span class=\"attribute\">-spec</span> hello(Name) -> ok when Name :: binary().</pre>"
           "</div>"
           "<p>Return a personalized greeting.</p>"
           "</section>"
           "</section>"
           "<section class=\"detail\" id=\"merge/3\">"
           "<div class=\"detail-header\">"
           "<div class=\"heading-with-actions\">"
           "<h1 class=\"signature\" translate=\"no\">merge(N, List1, List2)</h1>"
           "</div>"
           "</div>"
           "<section class=\"docstring\">"
           "<div class=\"specs\">"
           "<pre translate=\"no\"><span class=\"attribute\">-spec</span> merge(N, List1, List2) -> List3\n"
           "               when\n"
           "                   N :: pos_integer(),\n"
           "                   List1 :: [T1],\n"
           "                   List2 :: [T2],\n"
           "                   List3 :: [T1 | T2],\n"
           "                   T1 :: term(),\n"
           "                   T2 :: term().</pre>"
           "</div>"
           "<p>Merge lists.</p>"
           "</section>"
           "</section>"
           "<section class=\"detail\" id=\"filter/2\">"
           "<div class=\"detail-header\">"
           "<div class=\"heading-with-actions\">"
           "<h1 class=\"signature\" translate=\"no\">filter(Pred, List1)</h1>"
           "</div>"
           "</div>"
           "<section class=\"docstring\">"
           "<div class=\"specs\">"
           "<pre translate=\"no\"><span class=\"attribute\">-spec</span> filter(Pred, List1) -> List2\n"
           "               when\n"
           "                   Pred :: fun((Elem :: T) -> boolean()),\n"
           "                   List1 :: [T],\n"
           "                   List2 :: [T],\n"
           "                   T :: term().</pre>"
           "</div>"
           "<p>Filter a list.</p>"
           "</section>"
           "</section>"
           "<section class=\"detail\" id=\"split/2\">"
           "<div class=\"detail-header\">"
           "<div class=\"heading-with-actions\">"
           "<h1 class=\"signature\" translate=\"no\">split(N, List1)</h1>"
           "</div>"
           "</div>"
           "<section class=\"docstring\">"
           "<div class=\"specs\">"
           "<pre translate=\"no\"><span class=\"attribute\">-spec</span> split(N, List1) -> {List2, List3}\n"
           "               when\n"
           "                   N :: non_neg_integer(),\n"
           "                   List1 :: [T],\n"
           "                   List2 :: [T],\n"
           "                   List3 :: [T],\n"
           "                   T :: term().</pre>"
           "</div>"
           "<p>Split a list.</p>"
           "</section>"
           "</section>"
           "<section class=\"detail\" id=\"stats/1\">"
           "<div class=\"detail-header\">"
           "<div class=\"heading-with-actions\">"
           "<h1 class=\"signature\" translate=\"no\">stats(Item)</h1>"
           "</div>"
           "</div>"
           "<section class=\"docstring\">"
           "<div class=\"specs\">"
           "<pre translate=\"no\"><span class=\"attribute\">-spec</span> stats(one) -> One when One :: integer();\n"
           "                (two) -> Two when Two :: integer().</pre>"
           "</div>"
           "<p>Multi-clause stats.</p>"
           "</section>"
           "</section>"
           "<img src=\"assets/logo.png\"/>"
           "<script src=\"dist/app.js\"></script>"
           "<script src=\"docs_config.js\"></script>"
           "</main></body></html>",
    AppSrc = "{application, sample_app,\n"
             " [{description, \"Sample app\"}\n"
             " ,{vsn, \"0.1.0\"}\n"
             " ,{modules, [sample_app]}\n"
             " ,{registered, []}\n"
             " ,{applications, [kernel, stdlib]}\n"
             " ]}.\n",
    ok = file:write_file(filename:join(SrcDir, "sample_app.erl"), Source),
    ok = file:write_file(filename:join(SrcDir, "sample_app.app.src"), AppSrc),
    ok = file:write_file(filename:join(HtmlDir, "sample_app.html"), Html),
    ok = file:write_file(filename:join(HtmlDir, "docs_config.js"), "var docs_config = {};"),
    ok = file:write_file(filename:join(HtmlDir, "assets/logo.png"), <<"png">>),
    ok = file:write_file(filename:join(HtmlDir, "dist/app.js"), "console.log('ok');"),
    Root.
