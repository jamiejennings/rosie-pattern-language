-- -*- Mode: Lua; -*-                                                                             
--
-- expand.lua   macro-expansion
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- Parse trees are converted to the ast representation, in which:
--     - Sequences and choices are n-ary, not binary
--     - Assignments, aliases, and grammars are encoded as 'bind' ast nodes
--     - 

-- Syntax expansions:
--
-- * Remove cooked groups by interleaving references to the boundary identifier, ~.
-- * 

local ast = require "ast"

local expand = {}








return expand
