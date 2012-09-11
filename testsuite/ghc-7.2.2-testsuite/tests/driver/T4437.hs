
module Main (main) where

import Data.List
import DynFlags
import Language.Haskell.Extension

main :: IO ()
main = do let ghcExtensions = [ ext | (ext, _, _, _) <- xFlags ]
              cabalExtensions = map show [ toEnum 0 :: KnownExtension .. ]
              ghcOnlyExtensions = ghcExtensions \\ cabalExtensions
              -- These are extensions which are deliberately not yet
              -- registered with Cabal
              expectedGhcOnlyExtensions
                  = ["ParallelArrays",
                     "RelaxedLayout",
                     "DeriveGeneric",
                     "DefaultSignatures",
                     "InterruptibleFFI",
                     "AlternativeLayoutRule",
                     "AlternativeLayoutRuleTransitional",
                     "MonadComprehensions"]
              unexpectedGhcOnlyExtension = ghcOnlyExtensions
                                        \\ expectedGhcOnlyExtensions
          mapM_ putStrLn unexpectedGhcOnlyExtension

