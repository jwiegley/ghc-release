-- Test for http://hackage.haskell.org/trac/ghc/ticket/2533
import System.Environment
import List
main = do 
 (n:_) <- getArgs
 print (genericTake (read n) "none taken")
 print (genericDrop (read n) "none dropped")
 print (genericSplitAt (read n) "none split")
