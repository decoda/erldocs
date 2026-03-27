%% Copyright © 2015 Pierre Fenoll ‹pierrefenoll@gmail.com›
%% See LICENSE for licensing information.
%% -*- coding: utf-8 -*-

%% http://erlang.org/pipermail/erlang-questions/2005-October/017419.html
-define(ERLDOCS_XMERL_ETS_TABLE, erldocs_xmerl_ets_table).

%% The directory in which erldocs puts its specs_*.xml
-define(ERLDOCS_SPECS_TMP, ".xml").

-record(module_doc, { app
                    , module
                    , source_kind = legacy_xml
                    , render_mode = fragment
                    , summary = ""
                    , blocks = []
                    , functions = []
                    , types = []
                    , metadata = []
                    }).

-record(function_doc, { name
                      , arity = 0
                      , id = ""
                      , summary = ""
                      , heading = ""
                      , blocks = []
                      , signature = []
                      , metadata = []
                      }).

-record(type_doc, { name
                  , arity = 0
                  , id = ""
                  , heading = ""
                  , blocks = []
                  , signature = []
                  , opaque = false
                  , metadata = []
                  }).

%% End of File.
