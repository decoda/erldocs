%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_collect_modern_tests).

-include_lib("eunit/include/eunit.hrl").
-include("erldocs.hrl").

collect_file_test () ->
    Fixture = make_fixture_file(),
    [ModuleDoc] = erldocs_collect_modern:collect_file("sample_app", Fixture, []),
    ?assertMatch(#module_doc{module = "sample_app", source_kind = modern_edoc,
                             render_mode = fragment}, ModuleDoc),
    ?assert(lists:prefix("<h1>", lists:flatten(ModuleDoc#module_doc.blocks))),
    [FunctionDoc | _] = ModuleDoc#module_doc.functions,
    ?assertEqual("hello/0", FunctionDoc#function_doc.id),
    ?assertEqual("Return a greeting.", FunctionDoc#function_doc.summary).

collect_existing_html_test () ->
    {AppDir, File} = make_html_fixture_app(),
    [ModuleDoc] = erldocs_collect_modern:collect_file("sample_app", AppDir, File, [], true),
    ?assertMatch(#module_doc{module = "sample_app", source_kind = modern_edoc,
                             render_mode = standalone}, ModuleDoc),
    ?assertEqual("Standalone summary.", ModuleDoc#module_doc.summary),
    ?assertEqual(3, length(ModuleDoc#module_doc.functions)),
    [FunctionDoc, FunctionDoc2 | _] = ModuleDoc#module_doc.functions,
    ?assertEqual("hello/0", FunctionDoc#function_doc.id),
    ?assertEqual("hello()", FunctionDoc#function_doc.heading),
    ?assert(lists:prefix("Return a greeting.", FunctionDoc#function_doc.summary)),
    ?assertEqual("hello/1", FunctionDoc2#function_doc.id),
    ?assertEqual("hello(Name)", FunctionDoc2#function_doc.heading),
    ?assert(lists:prefix("Return a personalized greeting.", FunctionDoc2#function_doc.summary)),
    FunctionDoc3 = lists:nth(3, ModuleDoc#module_doc.functions),
    ?assertEqual("take/1", FunctionDoc3#function_doc.id),
    ?assertEqual("take(Value)", FunctionDoc3#function_doc.heading),
    ?assert(lists:prefix("Take a value.", FunctionDoc3#function_doc.summary)),
    ?assertEqual(2, length(ModuleDoc#module_doc.types)),
    [TypeDoc, TypeDoc2 | _] = ModuleDoc#module_doc.types,
    ?assertEqual("t:greeting/0", TypeDoc#type_doc.id),
    ?assertEqual("greeting()", TypeDoc#type_doc.heading),
    ?assertEqual("Greeting type.", proplists:get_value(summary, TypeDoc#type_doc.metadata)),
    ?assertEqual("t:name/0", TypeDoc2#type_doc.id),
    ?assertEqual("name()", TypeDoc2#type_doc.heading),
    ?assertEqual("Name type.", proplists:get_value(summary, TypeDoc2#type_doc.metadata)),
    Metadata = ModuleDoc#module_doc.metadata,
    ?assertMatch([_|_], proplists:get_value(support_files, Metadata)).

collect_erts_preloaded_html_test () ->
    Root = filename:join("/tmp", "erldocs-modern-erts-fixture"),
    HtmlDir = filename:join([Root, "doc", "html"]),
    PreloadedDir = filename:join([Root, "preloaded", "src"]),
    ok = filelib:ensure_dir(filename:join(HtmlDir, "erlang.html")),
    ok = filelib:ensure_dir(filename:join(PreloadedDir, "erlang.erl")),
    Html = "<!DOCTYPE html><html><body>"
           "<h1>erlang</h1>"
           "<p>BIFs.</p>"
           "<section id=\"summary\">"
           "<div class=\"summary-functions summary\">"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#apply/2\" data-no-tooltip=\"\" translate=\"no\">apply(Fun, Args)</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Calls a fun.</p></div>"
           "</div>"
           "</div>"
           "</section>"
           "</body></html>",
    Source = "-module(erlang).\n-export([apply/2]).\napply(_, _) -> ok.\n",
    ok = file:write_file(filename:join(PreloadedDir, "erlang.erl"), Source),
    ok = file:write_file(filename:join(HtmlDir, "erlang.html"), Html),
    [ModuleDoc] = erldocs_collect_modern:collect_app([{building_otp, {true, "dummy"}}], [], "erts", Root),
    ?assertEqual("erlang", ModuleDoc#module_doc.module),
    [FunctionDoc | _] = ModuleDoc#module_doc.functions,
    ?assertEqual("apply/2", FunctionDoc#function_doc.id).

rewrite_standalone_links_test () ->
    Html = "<a href=\"../../../../doc/index.html\">Home</a>"
           "<img src=\"assets/logo.png\"/>"
           "<script src=\"dist/app.js\"></script>"
           "<script src=\"docs_config.js\"></script>"
           "<form action=\"search.html\"></form>"
           "<a href=\"../../../../lib/../erts/doc/html/erlang.html#t:atom/0\">erlang</a>",
    Rewritten = erldocs_collect_modern:rewrite_standalone_links(Html, "sample_app"),
    ?assertEqual(nomatch, re:run(Rewritten, "src=\"assets/logo\\.png\"", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Rewritten, "src=\"dist/app\\.js\"", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Rewritten, "src=\"docs_config\\.js\"", [{capture, none}])),
    ?assertMatch({match, _}, re:run(Rewritten, "\\./_assets/assets/logo\\.png")),
    ?assertMatch({match, _}, re:run(Rewritten, "\\./_assets/dist/app\\.js")),
    ?assertMatch({match, _}, re:run(Rewritten, "\\./_assets/docs_config\\.js")),
    ?assertMatch({match, _}, re:run(Rewritten, "\\.\\./index\\.html#app-sample_app")),
    ?assertMatch({match, _}, re:run(Rewritten, "\\.\\./erts/erlang\\.html#t:atom/0")).

make_fixture_file () ->
    Root = filename:join("/tmp", "erldocs-modern-fixture"),
    ok = filelib:ensure_dir(filename:join(Root, "sample_app.erl")),
    Source = "%% -*- coding: utf-8 -*-\n"
             "-module(sample_app).\n\n"
             "-export([hello/0]).\n\n"
             "%% @doc Return a greeting.\n"
             "-spec hello() -> binary().\n"
             "hello () ->\n"
             "    <<\"hello\">>.\n",
    File = filename:join(Root, "sample_app.erl"),
    ok = file:write_file(File, Source),
    File.

make_html_fixture_app () ->
    Root = filename:join("/tmp", "erldocs-modern-html-fixture"),
    HtmlDir = filename:join([Root, "doc", "html"]),
    SrcDir = filename:join([Root, "src"]),
    ok = filelib:ensure_dir(filename:join(HtmlDir, "sample_app.html")),
    ok = filelib:ensure_dir(filename:join(SrcDir, "sample_app.erl")),
    ok = filelib:ensure_dir(filename:join(HtmlDir, "assets/logo.png")),
    ok = filelib:ensure_dir(filename:join(HtmlDir, "dist/app.js")),
    Html = "<!DOCTYPE html><html><body>"
           "<h1>sample_app</h1>"
           "<p>Standalone summary.</p>"
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
           "</div>"
           "<div class=\"summary-row\">"
           "<div class=\"summary-signature\">"
           "<a href=\"#take/1\" data-no-tooltip=\"\" translate=\"no\">take(Value)</a>"
           "</div>"
           "<div class=\"summary-synopsis\"><p>Take a value.</p></div>"
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
           "<section class=\"detail\" id=\"take/1\">"
           "<div class=\"detail-header\">"
           "<div class=\"heading-with-actions\">"
           "<h1 class=\"signature\" translate=\"no\">take(Value)</h1>"
           "</div>"
           "</div>"
           "<section class=\"docstring\">"
           "<p>Take a value.</p>"
           "</section>"
           "</section>"
           "<img src=\"assets/logo.png\"/>"
           "<script src=\"dist/app.js\"></script>"
           "<script src=\"docs_config.js\"></script>"
           "</body></html>",
    Source = "-module(sample_app).\n-export([hello/0]).\nhello() -> ok.\n",
    File = filename:join(SrcDir, "sample_app.erl"),
    ok = file:write_file(File, Source),
    ok = file:write_file(filename:join(HtmlDir, "sample_app.html"), Html),
    ok = file:write_file(filename:join(HtmlDir, "docs_config.js"), "var docs_config = {};"),
    ok = file:write_file(filename:join(HtmlDir, "assets/logo.png"), <<"png">>),
    ok = file:write_file(filename:join(HtmlDir, "dist/app.js"), "console.log('ok');"),
    {Root, File}.
