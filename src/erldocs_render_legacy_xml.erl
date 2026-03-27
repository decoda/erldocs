%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_render_legacy_xml).

-export([ render_content/2
        , xml_to_html/1
        ]).

render_content (Xml, Types) ->
    Acc = [{ids,[]}, {list,ul}, {functions,[]}, {types,Types}],
    {[_Id, _List, {functions,_Funs}, {types,_Types}], NXml}
        = render(fun tr_erlref/2, Xml, Acc),
    xml_to_html(NXml).

render (Fun, List, Acc) when is_list(List) ->
    case io_lib:char_list(List) of
        true  ->
            {Acc, List};
        false ->
            F = fun (X, {Ac, L}) ->
                        {NAcc, NEl} = render(Fun, X, Ac),
                        {NAcc, [NEl | L]}
                end,
            {Ac, L} = lists:foldl(F, {Acc, []}, List),
            {Ac, lists:reverse(L)}
    end;

render (Fun, Element, Acc) ->
    F = fun (ignore, NAcc) ->
                {NAcc, ""};
            ({NEl, NAttr, NChild}, NAcc) ->
                {NNAcc, NNChild} = render(Fun, NChild, NAcc),
                {NNAcc, {NEl, NAttr, NNChild}};
            (Else, NAcc) ->
                {NAcc, Else}
        end,
    case Fun(Element, Acc) of
        {El, NAcc} -> F(El, NAcc);
        El         -> F(El, Acc)
    end.

'add .html' ("#" ++ Rest) ->
    "#" ++ separate_f_from_a(Rest);
'add .html' (Link) ->
    case string:tokens(Link, "#") of
        [Tmp]    -> Tmp ++ ".html";
        [N1, N2] -> lists:flatten([N1, ".html#", separate_f_from_a(N2)])
    end.

tr__marker (FdashA) ->
    Mark = separate_f_from_a(FdashA),
    case FdashA =:= Mark of
        true  -> {span, [{id,Mark}], [" "]};
        false -> ignore
    end.

separate_f_from_a (FdashA) ->
    case re:run(FdashA, "^(.+)[/-]([0-9])+$", [{capture,all_but_first,list}]) of
        {match, [F,A]} -> F ++ "/" ++ A;
        nomatch -> FdashA
    end.

tr_erlref (Element) ->
    tr_erlref(Element, ignore_acc).
tr_erlref ({header,[],_Child}, _Acc) ->
    ignore;
tr_erlref ({marker, [{id,Marker}], []}, _Acc) ->
    tr__marker(Marker);
tr_erlref ({term,[{id, Term}], _Child}, _Acc) ->
    Term;
tr_erlref ({lib,[],Lib}, _Acc) ->
    {h1, [], [lists:flatten(Lib)]};
tr_erlref ({module,[],Module}, _Acc) ->
    {h1, [], [lists:flatten(Module)]};
tr_erlref ({modulesummary, [], Child}, _Acc) ->
    {h2, [{class,"modsummary"}], Child};
tr_erlref ({c, [], Child}, _Acc) ->
    {code, [], Child};
tr_erlref ({title, [], Child}, _Acc) ->
    {h4, [], [Child]};
tr_erlref ({v, [], []}, _Acc) ->
    {li, [], [" "]};
tr_erlref ({v, [], Child}, _Acc) ->
    {li, [], [{code, [], Child}]};
tr_erlref ({seealso, [{marker, Marker}], Child}, _Acc) ->
    case string:tokens(Marker, ":") of
        []        -> Url = 'add .html'(lists:flatten(Child));
        [Tmp]     -> Url = 'add .html'(Tmp);
        [Ap | Md] -> Url = "../" ++ Ap ++ "/" ++ 'add .html'(lists:flatten(Md))
    end,
    {a, [{href,Url},{class,"seealso"}], Child};

tr_erlref ({desc, [], Child}, _Acc) ->
    {'div', [{class, "description"}], Child};
tr_erlref ({description, [], Child}, _Acc) ->
    {'div', [{class,"description"}], Child};

tr_erlref ({funcs, [], Child}, _Acc) ->
    tr__category("Functions", "functions", Child);
tr_erlref ({func, [], Child}, _Acc) ->
    {'div', [{class,"function"}], Child};

tr_erlref ({datatypes, [], Child}, _Acc) ->
    tr__category("Types", "types", Child);
tr_erlref ({datatype, [], Child}, _Acc) ->
    {'div', [{class,"type"}], Child};
tr_erlref ({name, [], [{marker,[{id,ID="type-"++_}],Child}|_]}, _Acc) ->
    tr__type_name(ID, Child);
tr_erlref ({name, [{name,TName}], []}, Acc) ->
    tr__type_name(TName, "0", Acc);
tr_erlref ({name, [{name,TName},{n_vars,NVars}], []}, Acc) ->
    tr__type_name(TName, NVars, Acc);
tr_erlref ({name, [{name,TName},{n_vars,_,[NVars]}], []}, Acc) ->
    tr__type_name(TName, NVars, Acc);

tr_erlref ({section, [], [{title,[],["DATA TYPES"]}|Child]}, Acc) ->
    {taglist, _, Tags} = lists:keyfind(taglist, 1, Child),
    DTypes = [ begin
                   CompressedName = TName ++ "/0",
                   case tr__type_name(TName, "0", Acc) of
                       {h3, [{id,"type-"++TName}], [CompressedName]} ->
                           ignore;
                       Found ->
                           [ "\n    "
                           , {'div', [{class,"type"}], [Found]}
                           ]
                   end
               end || {item,_,[{marker,[{id,"type-"++TName}|_],_}|_]} <- Tags ],
    DTs = [DType || DType <- DTypes, DType /= ignore],
    tr__category("Types", "types", DTs);
tr_erlref ({section, [], Child}, _Acc) ->
    {'div', [{class,"section"}], Child};

tr_erlref ({tag, [], Child}, _Acc) ->
    {dt, [], Child};
tr_erlref ({taglist, [], Child}, [Ids, _List, Funs]) ->
    { {dl, [], Child}, [Ids, {list, dl}, Funs] };
tr_erlref ({input, [], Child}, _Acc) ->
    {code, [], Child};
tr_erlref ({item, [], Child}, [_Ids, {list, dl}, _Funs]) ->
    {dd, [], Child};
tr_erlref ({item, [], Child}, [_Ids, {list, ul}, _Funs]) ->
    {li, [], Child};
tr_erlref ({list, _Type, Child}, [Ids, _List, Funs]) ->
    { {ul, [], Child}, [Ids, {list, ul}, Funs] };
tr_erlref ({code, [{type, "none"}], Child}, _Acc) ->
    {pre, [{class, "sh_erlang"}], Child};
tr_erlref ({pre, [], Child}, _Acc) ->
    {pre, [{class, "sh_erlang"}], Child};
tr_erlref ({note, [], Child}, _Acc) ->
    {'div', [{class, "note"}], [{h2, [], ["Note!"]} | Child]};
tr_erlref ({warning, [], Child}, _Acc) ->
    {'div', [{class, "warning"}], [{h2, [], ["Warning!"]} | Child]};
tr_erlref ({name, [], [{ret,[],[Ret]}, {nametext,[],[Desc]}]}, _Acc) ->
    {pre, [], [Ret ++ " " ++ Desc]};

tr_erlref ({type, [{variable,_VarName}|_], []}, _Acc) ->
    ignore;
tr_erlref ({type, [], Child}, _Acc) ->
    {ul, [{class, "type"}], Child};
tr_erlref (E={type, [{name,TName}], []}, Acc) ->
    {_, Types} = lists:keyfind(types, 1, Acc),
    case erldocs_collect_legacy:find_type(TName, "0", Types) of
        ignore -> E;
        {_ID, Child} -> {ul
                        , [{class, "type"}]
                        , {li, [], {code, [], [Child]}}
                        }
    end;

tr_erlref ({name, [{name,Name}, {arity,N}, {clause_i,ClauseI}], []}, Acc)
  when ClauseI =:= "1" ->
    tr_erlref({name, [{name,Name}, {arity,N}], []}, Acc);
tr_erlref ({name, [{name,____}, {arity,_}, {clause_i,ClauseI}], []}, ___)
  when ClauseI  >  "1" ->
    ignore;
tr_erlref ({name, [{name,Name}, {arity,N}, {since,_}], []}, Acc) ->
    tr_erlref({name, [{name,Name}, {arity,N}], []}, Acc);
tr_erlref ({name, [{name,Name}, {arity,N}], []}, Acc) ->
    [{ids,Ids}, List, {functions,Funs}, {types,Types}] = Acc,
    NName = inc_name(Name, Ids, 0),
    ID = Name ++ "/" ++ N,
    Found = erldocs_collect_legacy:find_spec(Name, N, Types),
    {SpecsFound, Names} = lists:unzip(Found),
    Specs = [ {li, [], [{code, [], [Spec]}]}
              || Spec <- erldocs_collect_legacy:merge_specs(SpecsFound), Spec /= [] ],
    NSpecs = case Specs of
                 [] -> [];
                 _  -> ["\n      ", {ul, [{class,"type_desc"}], Specs}]
             end,
    Tags = case Names of
               []             ->
                   [{h3, [{id,ID}], [ID]}];
               [PName|PNames] ->
                   [{h3, [{id,ID}], [PName]}]
                       ++ [ {h3, [], [PNameK]} || PNameK <- PNames ]
           end,
    { Tags ++ NSpecs
    , [{ids,[NName|Ids]}, List, {functions,[NName|Funs]}, {types,Types}] };
tr_erlref ({name, [], Child}, Acc) ->
    [{ids,Ids}, List, {functions,Funs}, {types,Types}] = Acc,
    case erldocs_collect_legacy:make_name(Child) of
        ignore -> ignore;
        Name   ->
            NName = inc_name(Name, Ids, 0),
            { {h3, [{id, NName}], [Child]}
            , [{ids,[NName|Ids]}, List, {functions,[NName|Funs]}, {types,Types}] }
    end;

tr_erlref ({type_desc, [{variable, Name}], [Desc]}, _Acc) ->
    {'div', [{class, "type_desc"}], [{code, [], [Name, " = ",Desc]}]};
tr_erlref ({fsummary, [], _Child}, _Acc) ->
    ignore;
tr_erlref (Else, _Acc) ->
    Else.

tr__type_name (ID, Child) ->
    NChild = [case E of
                  Br when element(1,E) =:= br ->
                      [Br | lists:duplicate(8, {nbsp,[],[]})];
                  _ -> E
              end || E <- Child],
    {h3, [{id,ID}], [NChild]}.
tr__type_name (TName, NVars, Acc) ->
    {_, Types} = lists:keyfind(types, 1, Acc),
    case erldocs_collect_legacy:find_type(TName, NVars, Types) of
        {ID, Child} ->
            tr__type_name(ID, Child);
        ignore ->
            tr__type_name("type-" ++ TName, TName ++ "/" ++ NVars)
    end.

tr__category (_, _, []) -> [];
tr__category (Name, ID, Child) ->
    { 'div'
    , [{id,ID}, {class,"category"}]
    , [ {h4, [], [{a, [{href,"#" ++ ID}], [Name]}]}
      , {hr, [], []}
      | Child
      ]
    }.

nname (Name, 0)   -> Name;
nname (Name, Acc) -> Name ++ "-" ++ integer_to_list(Acc).

inc_name (Name, List, Acc) ->
    case lists:member(nname(Name, Acc), List) of
        true  -> inc_name(Name, List, Acc + 1);
        false -> nname(Name, Acc)
    end.

xml_to_html ({nbsp, [], Child}) ->
    ["&nbsp;", xml_to_html(Child)];
xml_to_html (Nbsp)
  when is_tuple(Nbsp), element(1, Nbsp) =:= nbsp ->
    "&nbsp;";
xml_to_html ({br, [], []}) ->
    "<br>\n";
xml_to_html ({Tag, Attr}) ->
    io_lib:format("<~ts ~ts>",
                  [atom_to_list(Tag), atos(Attr)]);
xml_to_html ({Tag, [], []}) ->
    io_lib:format("<~ts/>",
                  [atom_to_list(Tag)]);
xml_to_html ({Tag, Attr, []}) ->
    io_lib:format("<~ts ~ts/>",
                  [atom_to_list(Tag), atos(Attr)]);
xml_to_html ({Tag, [], Child}) ->
    io_lib:format("<~ts>~ts</~ts>",
                  [atom_to_list(Tag), xml_to_html(Child), atom_to_list(Tag)]);
xml_to_html ({Tag, Attr, Child}) ->
    io_lib:format("<~ts ~ts>~ts</~ts>",
                  [atom_to_list(Tag), atos(Attr), xml_to_html(Child), atom_to_list(Tag)]);
xml_to_html ([H | T]) ->
    [xml_to_html(H) | xml_to_html(T)];
xml_to_html (Else) ->
    htmlchar(Else).

atos ([])                      -> "";
atos (List) when is_list(List) -> iolists_join($\s, [atos(X) || X <- List]);
atos ({Name, Val})             -> [atom_to_list(Name), "=\"", Val, "\""].

htmlchar ($<) -> "&lt;";
htmlchar ($>) -> "&gt;";
htmlchar (Else) -> Else.

iolists_join (_, []) -> [];
iolists_join (_, [H]) -> [H];
iolists_join (Sep, [H|T]) ->
    [H] ++ [[Sep,E] || E <- T].
