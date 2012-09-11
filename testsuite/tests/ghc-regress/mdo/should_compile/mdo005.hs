{-# OPTIONS -fglasgow-exts #-}

-- test scoping

module Main (main) where

import Control.Monad.Fix 
import Maybe ( fromJust )

t = mdo x <- fromJust (mdo x <- Just (1:x)
			   return (take 4 x))
	return x

main :: IO ()
main = print t 