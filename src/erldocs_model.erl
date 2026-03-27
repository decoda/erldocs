%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-
-module(erldocs_model).

-export([ module_doc/8
        , module_doc/9
        , function_doc/8
        , type_doc/8
        ]).

-include("erldocs.hrl").

module_doc (App, Module, SourceKind, Summary, Blocks, Functions, Types, Metadata) ->
    module_doc(App, Module, SourceKind, fragment, Summary, Blocks, Functions, Types, Metadata).

module_doc (App, Module, SourceKind, RenderMode, Summary, Blocks, Functions, Types, Metadata) ->
    #module_doc{app = App
               ,module = Module
               ,source_kind = SourceKind
               ,render_mode = RenderMode
               ,summary = Summary
               ,blocks = Blocks
               ,functions = Functions
               ,types = Types
               ,metadata = Metadata
               }.

function_doc (Name, Arity, Id, Summary, Heading, Blocks, Signature, Metadata) ->
    #function_doc{name = Name
                 ,arity = Arity
                 ,id = Id
                 ,summary = Summary
                 ,heading = Heading
                 ,blocks = Blocks
                 ,signature = Signature
                 ,metadata = Metadata
                 }.

type_doc (Name, Arity, Id, Heading, Blocks, Signature, Opaque, Metadata) ->
    #type_doc{name = Name
             ,arity = Arity
             ,id = Id
             ,heading = Heading
             ,blocks = Blocks
             ,signature = Signature
             ,opaque = Opaque
             ,metadata = Metadata
             }.
