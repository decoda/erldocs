%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_collect_legacy_tests).

-include_lib("eunit/include/eunit.hrl").
-include("erldocs.hrl").

module_summary_test () ->
    Xml = [{modulesummary, [], ["Sample module summary"]}],
    ?assertEqual("Sample module summary",
                 erldocs_collect_legacy:module_summary(erlref, Xml)).

function_summary_test () ->
    FuncXml = [{fsummary, [], ["Line 1", "\n", "Line 2"]}],
    ?assertEqual("Line 1 Line 2",
                 erldocs_collect_legacy:function_summary(FuncXml)).

legacy_signatures_are_mapped_test () ->
    Xml = [{funcs, [], [{func, [], [{name, [{name,"main"}, {arity,"1"}], []}
                                   ,{fsummary, [], ["Runs main"]}
                                   ]}]}],
    Specs = [{spec, [], [{name, [], ["main"]}
                        ,{arity, [], ["1"]}
                        ,{contract, [], [{clause, [], [{head, [], ["main/1"]}
                                                      ,{guard, [], [{subtype, [], [{typename, [], []}
                                                                                  ,{string, [], ["term() -> boolean()"]}
                                                                                  ]}]}
                                                      ]}]}
                        ]}],
    [FunctionDoc] = erldocs_collect_legacy:function_docs("app", "mod", Xml, Specs),
    ?assertMatch(#function_doc{id = "main/1", signature = ["term() -&gt; boolean()"]},
                 FunctionDoc).

legacy_type_docs_are_mapped_test () ->
    Specs = [{type, [], [{name, [], ["my_type"]}
                        ,{n_vars, [], ["0"]}
                        ,{typedecl, [], [{typehead, [], [{marker, [{id, "type-my_type"}], ["my_type/0"]}
                                                        ," :: integer()"
                                                        ]}]}
                        ]}],
    [TypeDoc] = erldocs_collect_legacy:type_docs(Specs),
    ?assertMatch(#type_doc{id = "type-my_type", signature = ["my_type/0 :: integer()"]},
                 TypeDoc).
