-- Testing readInt, lightly.
--
module Main(main) where

import Numeric
import Char

main = 
  let 
   rd :: ReadS Integer 
   rd = readSigned (readInt 10 (isDigit) (digitToInt))
  in
  do
   print (rd (show (343023920121::Integer)))
   print (rd (show (3430239::Int)))
   print (rd (show (1212 :: Int)))
   print (rd (show (591125662431 `div` (517::Int))))
   print (rd (show (-111::Int)))
   print (rd (show (232189458241::Integer)))
