
module Main (main) where

import Control.Exception
import Prelude hiding (catch)
import System.Directory

main :: IO ()
main = do let -- On OS X (canonicalizePath "") gives the current
              -- directory, but the prefix is variable so we
              -- just take the last 24 characters (should be
              -- "tests/ghc-regress/lib/IO")
              suffixOnly = reverse . take 24 . reverse
          doit suffixOnly ""
          let -- On Windows, "/no/such/file" -> "C:\\no\\such\\file", so
              mangleDrive (_ : ':' : xs) = "drive:" ++ xs
              mangleDrive xs = xs
          doit mangleDrive "/no/such/file"

doit :: (FilePath -> FilePath) -> FilePath -> IO ()
doit mangle fp = do fp' <- canonicalizePath fp
                    print (fp, mangle fp')
    `catch` \e -> putStrLn ("Exception: " ++ show (e :: IOException))

