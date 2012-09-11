-- Test trying to use a function bound in the list comprehension as the group function

{-# OPTIONS_GHC -XRank2Types -XTransformListComp #-}

module RnFail049 where

import List(inits, tails)

functions :: [forall a. [a] -> [[a]]]
functions = [inits, tails]

output = [() | f <- functions, then group using f]


