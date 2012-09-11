{-# OPTIONS_GHC -w #-}
{-# OPTIONS -fglasgow-exts -cpp #-}
{-# LANGUAGE BangPatterns #-} -- required for versions of Happy before 1.18.6
{-# OPTIONS -w -Wwarn #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

module Parser (parse) where

import Lexer (lex_tok)
import ParserM (Token(..), ParserM, run_parser, get_pos, show_pos,
                happyError)
import Syntax
import qualified Data.Array as Happy_Data_Array
import qualified GHC.Exts as Happy_GHC_Exts

-- parser produced by Happy Version 1.18.6

newtype HappyAbsSyn  = HappyAbsSyn HappyAny
#if __GLASGOW_HASKELL__ >= 607
type HappyAny = Happy_GHC_Exts.Any
#else
type HappyAny = forall a . a
#endif
happyIn4 :: (Info) -> (HappyAbsSyn )
happyIn4 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn4 #-}
happyOut4 :: (HappyAbsSyn ) -> (Info)
happyOut4 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut4 #-}
happyIn5 :: ([Option]) -> (HappyAbsSyn )
happyIn5 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn5 #-}
happyOut5 :: (HappyAbsSyn ) -> ([Option])
happyOut5 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut5 #-}
happyIn6 :: ([Option]) -> (HappyAbsSyn )
happyIn6 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn6 #-}
happyOut6 :: (HappyAbsSyn ) -> ([Option])
happyOut6 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut6 #-}
happyIn7 :: (Option) -> (HappyAbsSyn )
happyIn7 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn7 #-}
happyOut7 :: (HappyAbsSyn ) -> (Option)
happyOut7 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut7 #-}
happyIn8 :: ([Entry]) -> (HappyAbsSyn )
happyIn8 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn8 #-}
happyOut8 :: (HappyAbsSyn ) -> ([Entry])
happyOut8 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut8 #-}
happyIn9 :: (Entry) -> (HappyAbsSyn )
happyIn9 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn9 #-}
happyOut9 :: (HappyAbsSyn ) -> (Entry)
happyOut9 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut9 #-}
happyIn10 :: (Entry) -> (HappyAbsSyn )
happyIn10 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn10 #-}
happyOut10 :: (HappyAbsSyn ) -> (Entry)
happyOut10 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut10 #-}
happyIn11 :: (Entry) -> (HappyAbsSyn )
happyIn11 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn11 #-}
happyOut11 :: (HappyAbsSyn ) -> (Entry)
happyOut11 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut11 #-}
happyIn12 :: (Entry) -> (HappyAbsSyn )
happyIn12 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn12 #-}
happyOut12 :: (HappyAbsSyn ) -> (Entry)
happyOut12 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut12 #-}
happyIn13 :: (Entry) -> (HappyAbsSyn )
happyIn13 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn13 #-}
happyOut13 :: (HappyAbsSyn ) -> (Entry)
happyOut13 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut13 #-}
happyIn14 :: ([Option]) -> (HappyAbsSyn )
happyIn14 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn14 #-}
happyOut14 :: (HappyAbsSyn ) -> ([Option])
happyOut14 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut14 #-}
happyIn15 :: (Category) -> (HappyAbsSyn )
happyIn15 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn15 #-}
happyOut15 :: (HappyAbsSyn ) -> (Category)
happyOut15 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut15 #-}
happyIn16 :: (String) -> (HappyAbsSyn )
happyIn16 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn16 #-}
happyOut16 :: (HappyAbsSyn ) -> (String)
happyOut16 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut16 #-}
happyIn17 :: (String) -> (HappyAbsSyn )
happyIn17 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn17 #-}
happyOut17 :: (HappyAbsSyn ) -> (String)
happyOut17 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut17 #-}
happyIn18 :: (String) -> (HappyAbsSyn )
happyIn18 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn18 #-}
happyOut18 :: (HappyAbsSyn ) -> (String)
happyOut18 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut18 #-}
happyIn19 :: (String) -> (HappyAbsSyn )
happyIn19 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn19 #-}
happyOut19 :: (HappyAbsSyn ) -> (String)
happyOut19 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut19 #-}
happyIn20 :: (Ty) -> (HappyAbsSyn )
happyIn20 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn20 #-}
happyOut20 :: (HappyAbsSyn ) -> (Ty)
happyOut20 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut20 #-}
happyIn21 :: (Ty) -> (HappyAbsSyn )
happyIn21 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn21 #-}
happyOut21 :: (HappyAbsSyn ) -> (Ty)
happyOut21 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut21 #-}
happyIn22 :: (Ty) -> (HappyAbsSyn )
happyIn22 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn22 #-}
happyOut22 :: (HappyAbsSyn ) -> (Ty)
happyOut22 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut22 #-}
happyIn23 :: ([Ty]) -> (HappyAbsSyn )
happyIn23 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn23 #-}
happyOut23 :: (HappyAbsSyn ) -> ([Ty])
happyOut23 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut23 #-}
happyIn24 :: ([Ty]) -> (HappyAbsSyn )
happyIn24 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn24 #-}
happyOut24 :: (HappyAbsSyn ) -> ([Ty])
happyOut24 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut24 #-}
happyIn25 :: (Ty) -> (HappyAbsSyn )
happyIn25 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn25 #-}
happyOut25 :: (HappyAbsSyn ) -> (Ty)
happyOut25 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut25 #-}
happyIn26 :: (String) -> (HappyAbsSyn )
happyIn26 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn26 #-}
happyOut26 :: (HappyAbsSyn ) -> (String)
happyOut26 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut26 #-}
happyInTok :: (Token) -> (HappyAbsSyn )
happyInTok x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyInTok #-}
happyOutTok :: (HappyAbsSyn ) -> (Token)
happyOutTok x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOutTok #-}


happyActOffsets :: HappyAddr
happyActOffsets = HappyA# "\x70\x00\x70\x00\x47\x00\x6f\x00\x68\x00\x00\x00\x67\x00\x76\x00\x66\x00\x47\x00\x00\x00\x00\x00\x00\x00\x00\x00\x64\x00\x5d\x00\x5e\x00\x01\x00\x6e\x00\x72\x00\x00\x00\x04\x00\xfd\xff\x01\x00\x00\x00\x00\x00\x01\x00\x58\x00\x6c\x00\x00\x00\x00\x00\x0e\x00\x00\x00\x00\x00\xfc\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xfe\xff\x6c\x00\x6d\x00\x6b\x00\x6a\x00\x00\x00\x00\x00\x04\x00\x00\x00\x69\x00\x00\x00\x01\x00\x5c\x00\x00\x00\x56\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x5b\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x63\x00\xfc\xff\xfc\xff\x00\x00\x62\x00\x00\x00\x00\x00\x60\x00\x00\x00\x00\x00\x00\x00\x59\x00\x00\x00\x00\x00\x00\x00"#

happyGotoOffsets :: HappyAddr
happyGotoOffsets = HappyA# "\x65\x00\x4f\x00\x46\x00\x61\x00\x00\x00\x00\x00\x5f\x00\x00\x00\x00\x00\x40\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x2d\x00\x53\x00\x00\x00\x00\x00\x41\x00\x26\x00\x10\x00\x00\x00\x00\x00\x23\x00\x00\x00\x51\x00\x00\x00\x00\x00\x0d\x00\x00\x00\x00\x00\x4d\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xfb\xff\x4c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x2c\x00\x00\x00\x00\x00\x00\x00\x1c\x00\x50\x00\x00\x00\x38\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf9\xff\x1d\x00\x19\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x22\x00\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x18\x00\x00\x00\x00\x00\x00\x00\x13\x00\x00\x00\x00\x00\x00\x00"#

happyDefActions :: HappyAddr
happyDefActions = HappyA# "\x00\x00\x00\x00\xf5\xff\xfb\xff\x00\x00\xfd\xff\xfb\xff\x00\x00\x00\x00\xf5\xff\xf4\xff\xf3\xff\xf2\xff\xf1\xff\x00\x00\x00\x00\x00\x00\x00\x00\xe5\xff\xde\xff\xdc\xff\xd5\xff\x00\x00\x00\x00\xda\xff\xd2\xff\x00\x00\x00\x00\xe5\xff\xf6\xff\xfe\xff\x00\x00\xfc\xff\xf8\xff\xe2\xff\xf9\xff\xfa\xff\xf7\xff\xed\xff\xe6\xff\x00\x00\xe5\xff\xd7\xff\x00\x00\x00\x00\xd1\xff\xdd\xff\xd5\xff\xd3\xff\x00\x00\xd4\xff\x00\x00\xeb\xff\xef\xff\xfb\xff\xdf\xff\xd6\xff\xdb\xff\xd9\xff\x00\x00\xeb\xff\x00\x00\xea\xff\xe9\xff\xe8\xff\xe7\xff\x00\x00\xe2\xff\xe2\xff\xe0\xff\x00\x00\xe3\xff\xe4\xff\xe5\xff\xee\xff\xd8\xff\xec\xff\xeb\xff\xe1\xff\xf0\xff"#

happyCheck :: HappyAddr
happyCheck = HappyA# "\xff\xff\x04\x00\x05\x00\x06\x00\x08\x00\x04\x00\x0b\x00\x06\x00\x04\x00\x10\x00\x11\x00\x12\x00\x13\x00\x0e\x00\x0f\x00\x16\x00\x12\x00\x13\x00\x14\x00\x15\x00\x17\x00\x18\x00\x08\x00\x1b\x00\x17\x00\x18\x00\x0d\x00\x17\x00\x18\x00\x0a\x00\x10\x00\x11\x00\x10\x00\x11\x00\x12\x00\x13\x00\x0c\x00\x0d\x00\x16\x00\x0a\x00\x1a\x00\x10\x00\x11\x00\x12\x00\x10\x00\x11\x00\x12\x00\x16\x00\x0e\x00\x0f\x00\x16\x00\x10\x00\x11\x00\x12\x00\x10\x00\x11\x00\x12\x00\x16\x00\x02\x00\x03\x00\x16\x00\x10\x00\x11\x00\x12\x00\x14\x00\x15\x00\x16\x00\x16\x00\x04\x00\x05\x00\x06\x00\x07\x00\x08\x00\x09\x00\x04\x00\x05\x00\x06\x00\x07\x00\x08\x00\x09\x00\x01\x00\x0a\x00\x0b\x00\x0c\x00\x0d\x00\x14\x00\x15\x00\x16\x00\x0c\x00\x0d\x00\x0a\x00\x0e\x00\x0f\x00\x0c\x00\x0d\x00\x0c\x00\x0d\x00\x02\x00\x03\x00\x02\x00\x03\x00\x00\x00\x01\x00\x0e\x00\x08\x00\x0e\x00\x0e\x00\x09\x00\x09\x00\x17\x00\x05\x00\x05\x00\x03\x00\x19\x00\x07\x00\x01\x00\x08\x00\x18\x00\x08\x00\x19\x00\x02\x00\xff\xff\xff\xff\xff\xff\x16\x00\x19\x00\x17\x00\x0f\x00\xff\xff\xff\xff\xff\xff\xff\xff\x1c\x00\xff\xff\x17\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"#

happyTable :: HappyAddr
happyTable = HappyA# "\x00\x00\x17\x00\x2e\x00\x18\x00\x45\x00\x17\x00\x3d\x00\x18\x00\x32\x00\x2a\x00\x13\x00\x14\x00\x4b\x00\x46\x00\x43\x00\x15\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x19\x00\x1a\x00\x23\x00\x46\x00\x19\x00\x1a\x00\x21\x00\x33\x00\x1a\x00\x4f\x00\x24\x00\x25\x00\x2a\x00\x13\x00\x14\x00\x2b\x00\x4d\x00\x27\x00\x15\x00\x4a\x00\x26\x00\x49\x00\x13\x00\x14\x00\x37\x00\x13\x00\x14\x00\x15\x00\x47\x00\x43\x00\x15\x00\x29\x00\x13\x00\x14\x00\x2c\x00\x13\x00\x14\x00\x15\x00\x4c\x00\x06\x00\x15\x00\x12\x00\x13\x00\x14\x00\x38\x00\x2f\x00\x30\x00\x15\x00\x1d\x00\x09\x00\x0a\x00\x0b\x00\x0c\x00\x0d\x00\x08\x00\x09\x00\x0a\x00\x0b\x00\x0c\x00\x0d\x00\x02\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x2e\x00\x2f\x00\x30\x00\x3c\x00\x27\x00\x35\x00\x42\x00\x43\x00\x26\x00\x27\x00\x34\x00\x27\x00\x20\x00\x06\x00\x05\x00\x06\x00\x04\x00\x02\x00\x37\x00\x23\x00\x37\x00\x37\x00\x4f\x00\x49\x00\x08\x00\x2e\x00\x3a\x00\x3c\x00\x29\x00\x3b\x00\x34\x00\x23\x00\x1c\x00\x23\x00\x1b\x00\x20\x00\x00\x00\x00\x00\x00\x00\x1f\x00\x1d\x00\x08\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\x00\x00\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"#

happyReduceArr = Happy_Data_Array.array (1, 46) [
	(1 , happyReduce_1),
	(2 , happyReduce_2),
	(3 , happyReduce_3),
	(4 , happyReduce_4),
	(5 , happyReduce_5),
	(6 , happyReduce_6),
	(7 , happyReduce_7),
	(8 , happyReduce_8),
	(9 , happyReduce_9),
	(10 , happyReduce_10),
	(11 , happyReduce_11),
	(12 , happyReduce_12),
	(13 , happyReduce_13),
	(14 , happyReduce_14),
	(15 , happyReduce_15),
	(16 , happyReduce_16),
	(17 , happyReduce_17),
	(18 , happyReduce_18),
	(19 , happyReduce_19),
	(20 , happyReduce_20),
	(21 , happyReduce_21),
	(22 , happyReduce_22),
	(23 , happyReduce_23),
	(24 , happyReduce_24),
	(25 , happyReduce_25),
	(26 , happyReduce_26),
	(27 , happyReduce_27),
	(28 , happyReduce_28),
	(29 , happyReduce_29),
	(30 , happyReduce_30),
	(31 , happyReduce_31),
	(32 , happyReduce_32),
	(33 , happyReduce_33),
	(34 , happyReduce_34),
	(35 , happyReduce_35),
	(36 , happyReduce_36),
	(37 , happyReduce_37),
	(38 , happyReduce_38),
	(39 , happyReduce_39),
	(40 , happyReduce_40),
	(41 , happyReduce_41),
	(42 , happyReduce_42),
	(43 , happyReduce_43),
	(44 , happyReduce_44),
	(45 , happyReduce_45),
	(46 , happyReduce_46)
	]

happy_n_terms = 29 :: Int
happy_n_nonterms = 23 :: Int

happyReduce_1 = happySpecReduce_3  0# happyReduction_1
happyReduction_1 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut5 happy_x_1 of { happy_var_1 -> 
	case happyOut8 happy_x_2 of { happy_var_2 -> 
	happyIn4
		 (Info happy_var_1 happy_var_2
	)}}

happyReduce_2 = happySpecReduce_2  1# happyReduction_2
happyReduction_2 happy_x_2
	happy_x_1
	 =  case happyOut6 happy_x_2 of { happy_var_2 -> 
	happyIn5
		 (happy_var_2
	)}

happyReduce_3 = happySpecReduce_2  2# happyReduction_3
happyReduction_3 happy_x_2
	happy_x_1
	 =  case happyOut7 happy_x_1 of { happy_var_1 -> 
	case happyOut6 happy_x_2 of { happy_var_2 -> 
	happyIn6
		 (happy_var_1 : happy_var_2
	)}}

happyReduce_4 = happySpecReduce_0  2# happyReduction_4
happyReduction_4  =  happyIn6
		 ([]
	)

happyReduce_5 = happySpecReduce_3  3# happyReduction_5
happyReduction_5 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (TLowerName happy_var_1) -> 
	happyIn7
		 (OptionFalse  happy_var_1
	)}

happyReduce_6 = happySpecReduce_3  3# happyReduction_6
happyReduction_6 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (TLowerName happy_var_1) -> 
	happyIn7
		 (OptionTrue   happy_var_1
	)}

happyReduce_7 = happySpecReduce_3  3# happyReduction_7
happyReduction_7 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (TLowerName happy_var_1) -> 
	case happyOut17 happy_x_3 of { happy_var_3 -> 
	happyIn7
		 (OptionString happy_var_1 happy_var_3
	)}}

happyReduce_8 = happySpecReduce_3  3# happyReduction_8
happyReduction_8 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (TLowerName happy_var_1) -> 
	case happyOutTok happy_x_3 of { (TInteger happy_var_3) -> 
	happyIn7
		 (OptionInteger happy_var_1 happy_var_3
	)}}

happyReduce_9 = happySpecReduce_2  4# happyReduction_9
happyReduction_9 happy_x_2
	happy_x_1
	 =  case happyOut9 happy_x_1 of { happy_var_1 -> 
	case happyOut8 happy_x_2 of { happy_var_2 -> 
	happyIn8
		 (happy_var_1 : happy_var_2
	)}}

happyReduce_10 = happySpecReduce_0  4# happyReduction_10
happyReduction_10  =  happyIn8
		 ([]
	)

happyReduce_11 = happySpecReduce_1  5# happyReduction_11
happyReduction_11 happy_x_1
	 =  case happyOut10 happy_x_1 of { happy_var_1 -> 
	happyIn9
		 (happy_var_1
	)}

happyReduce_12 = happySpecReduce_1  5# happyReduction_12
happyReduction_12 happy_x_1
	 =  case happyOut11 happy_x_1 of { happy_var_1 -> 
	happyIn9
		 (happy_var_1
	)}

happyReduce_13 = happySpecReduce_1  5# happyReduction_13
happyReduction_13 happy_x_1
	 =  case happyOut12 happy_x_1 of { happy_var_1 -> 
	happyIn9
		 (happy_var_1
	)}

happyReduce_14 = happySpecReduce_1  5# happyReduction_14
happyReduction_14 happy_x_1
	 =  case happyOut13 happy_x_1 of { happy_var_1 -> 
	happyIn9
		 (happy_var_1
	)}

happyReduce_15 = happyReduce 7# 6# happyReduction_15
happyReduction_15 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_2 of { (TUpperName happy_var_2) -> 
	case happyOutTok happy_x_3 of { (TString happy_var_3) -> 
	case happyOut15 happy_x_4 of { happy_var_4 -> 
	case happyOut20 happy_x_5 of { happy_var_5 -> 
	case happyOut16 happy_x_6 of { happy_var_6 -> 
	case happyOut14 happy_x_7 of { happy_var_7 -> 
	happyIn10
		 (PrimOpSpec {
                    cons = happy_var_2,
                    name = happy_var_3,
                    cat = happy_var_4,
                    ty = happy_var_5,
                    desc = happy_var_6,
                    opts = happy_var_7
                }
	) `HappyStk` happyRest}}}}}}

happyReduce_16 = happyReduce 4# 7# happyReduction_16
happyReduction_16 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut20 happy_x_2 of { happy_var_2 -> 
	case happyOut16 happy_x_3 of { happy_var_3 -> 
	case happyOut14 happy_x_4 of { happy_var_4 -> 
	happyIn11
		 (PrimTypeSpec { ty = happy_var_2, desc = happy_var_3, opts = happy_var_4 }
	) `HappyStk` happyRest}}}

happyReduce_17 = happyReduce 5# 8# happyReduction_17
happyReduction_17 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_2 of { (TString happy_var_2) -> 
	case happyOut20 happy_x_3 of { happy_var_3 -> 
	case happyOut16 happy_x_4 of { happy_var_4 -> 
	case happyOut14 happy_x_5 of { happy_var_5 -> 
	happyIn12
		 (PseudoOpSpec { name = happy_var_2, ty = happy_var_3, desc = happy_var_4, opts = happy_var_5 }
	) `HappyStk` happyRest}}}}

happyReduce_18 = happySpecReduce_3  9# happyReduction_18
happyReduction_18 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_2 of { (TString happy_var_2) -> 
	case happyOut16 happy_x_3 of { happy_var_3 -> 
	happyIn13
		 (Section { title = happy_var_2, desc = happy_var_3 }
	)}}

happyReduce_19 = happySpecReduce_2  10# happyReduction_19
happyReduction_19 happy_x_2
	happy_x_1
	 =  case happyOut6 happy_x_2 of { happy_var_2 -> 
	happyIn14
		 (happy_var_2
	)}

happyReduce_20 = happySpecReduce_0  10# happyReduction_20
happyReduction_20  =  happyIn14
		 ([]
	)

happyReduce_21 = happySpecReduce_1  11# happyReduction_21
happyReduction_21 happy_x_1
	 =  happyIn15
		 (Dyadic
	)

happyReduce_22 = happySpecReduce_1  11# happyReduction_22
happyReduction_22 happy_x_1
	 =  happyIn15
		 (Monadic
	)

happyReduce_23 = happySpecReduce_1  11# happyReduction_23
happyReduction_23 happy_x_1
	 =  happyIn15
		 (Compare
	)

happyReduce_24 = happySpecReduce_1  11# happyReduction_24
happyReduction_24 happy_x_1
	 =  happyIn15
		 (GenPrimOp
	)

happyReduce_25 = happySpecReduce_1  12# happyReduction_25
happyReduction_25 happy_x_1
	 =  case happyOut17 happy_x_1 of { happy_var_1 -> 
	happyIn16
		 (happy_var_1
	)}

happyReduce_26 = happySpecReduce_0  12# happyReduction_26
happyReduction_26  =  happyIn16
		 (""
	)

happyReduce_27 = happySpecReduce_3  13# happyReduction_27
happyReduction_27 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut18 happy_x_2 of { happy_var_2 -> 
	happyIn17
		 (happy_var_2
	)}

happyReduce_28 = happySpecReduce_2  14# happyReduction_28
happyReduction_28 happy_x_2
	happy_x_1
	 =  case happyOut19 happy_x_1 of { happy_var_1 -> 
	case happyOut18 happy_x_2 of { happy_var_2 -> 
	happyIn18
		 (happy_var_1 ++ happy_var_2
	)}}

happyReduce_29 = happySpecReduce_0  14# happyReduction_29
happyReduction_29  =  happyIn18
		 (""
	)

happyReduce_30 = happySpecReduce_3  15# happyReduction_30
happyReduction_30 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut18 happy_x_2 of { happy_var_2 -> 
	happyIn19
		 ("{" ++ happy_var_2 ++ "}"
	)}

happyReduce_31 = happySpecReduce_1  15# happyReduction_31
happyReduction_31 happy_x_1
	 =  case happyOutTok happy_x_1 of { (TNoBraces happy_var_1) -> 
	happyIn19
		 (happy_var_1
	)}

happyReduce_32 = happySpecReduce_3  16# happyReduction_32
happyReduction_32 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut21 happy_x_1 of { happy_var_1 -> 
	case happyOut20 happy_x_3 of { happy_var_3 -> 
	happyIn20
		 (TyF happy_var_1 happy_var_3
	)}}

happyReduce_33 = happySpecReduce_1  16# happyReduction_33
happyReduction_33 happy_x_1
	 =  case happyOut21 happy_x_1 of { happy_var_1 -> 
	happyIn20
		 (happy_var_1
	)}

happyReduce_34 = happySpecReduce_2  17# happyReduction_34
happyReduction_34 happy_x_2
	happy_x_1
	 =  case happyOut26 happy_x_1 of { happy_var_1 -> 
	case happyOut24 happy_x_2 of { happy_var_2 -> 
	happyIn21
		 (TyApp happy_var_1 happy_var_2
	)}}

happyReduce_35 = happySpecReduce_1  17# happyReduction_35
happyReduction_35 happy_x_1
	 =  case happyOut22 happy_x_1 of { happy_var_1 -> 
	happyIn21
		 (happy_var_1
	)}

happyReduce_36 = happySpecReduce_3  17# happyReduction_36
happyReduction_36 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut20 happy_x_2 of { happy_var_2 -> 
	happyIn21
		 (happy_var_2
	)}

happyReduce_37 = happySpecReduce_1  17# happyReduction_37
happyReduction_37 happy_x_1
	 =  case happyOutTok happy_x_1 of { (TLowerName happy_var_1) -> 
	happyIn21
		 (TyVar happy_var_1
	)}

happyReduce_38 = happySpecReduce_3  18# happyReduction_38
happyReduction_38 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut23 happy_x_2 of { happy_var_2 -> 
	happyIn22
		 (TyUTup happy_var_2
	)}

happyReduce_39 = happySpecReduce_3  19# happyReduction_39
happyReduction_39 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut20 happy_x_1 of { happy_var_1 -> 
	case happyOut23 happy_x_3 of { happy_var_3 -> 
	happyIn23
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_40 = happySpecReduce_1  19# happyReduction_40
happyReduction_40 happy_x_1
	 =  case happyOut20 happy_x_1 of { happy_var_1 -> 
	happyIn23
		 ([happy_var_1]
	)}

happyReduce_41 = happySpecReduce_2  20# happyReduction_41
happyReduction_41 happy_x_2
	happy_x_1
	 =  case happyOut25 happy_x_1 of { happy_var_1 -> 
	case happyOut24 happy_x_2 of { happy_var_2 -> 
	happyIn24
		 (happy_var_1 : happy_var_2
	)}}

happyReduce_42 = happySpecReduce_0  20# happyReduction_42
happyReduction_42  =  happyIn24
		 ([]
	)

happyReduce_43 = happySpecReduce_1  21# happyReduction_43
happyReduction_43 happy_x_1
	 =  case happyOutTok happy_x_1 of { (TLowerName happy_var_1) -> 
	happyIn25
		 (TyVar happy_var_1
	)}

happyReduce_44 = happySpecReduce_1  21# happyReduction_44
happyReduction_44 happy_x_1
	 =  case happyOut26 happy_x_1 of { happy_var_1 -> 
	happyIn25
		 (TyApp happy_var_1 []
	)}

happyReduce_45 = happySpecReduce_1  22# happyReduction_45
happyReduction_45 happy_x_1
	 =  case happyOutTok happy_x_1 of { (TUpperName happy_var_1) -> 
	happyIn26
		 (happy_var_1
	)}

happyReduce_46 = happySpecReduce_2  22# happyReduction_46
happyReduction_46 happy_x_2
	happy_x_1
	 =  happyIn26
		 ("()"
	)

happyNewToken action sts stk
	= lex_tok(\tk -> 
	let cont i = happyDoAction i tk action sts stk in
	case tk of {
	TEOF -> happyDoAction 28# tk action sts stk;
	TArrow -> cont 1#;
	TEquals -> cont 2#;
	TComma -> cont 3#;
	TOpenParen -> cont 4#;
	TCloseParen -> cont 5#;
	TOpenParenHash -> cont 6#;
	THashCloseParen -> cont 7#;
	TOpenBrace -> cont 8#;
	TCloseBrace -> cont 9#;
	TSection -> cont 10#;
	TPrimop -> cont 11#;
	TPseudoop -> cont 12#;
	TPrimtype -> cont 13#;
	TWith -> cont 14#;
	TDefaults -> cont 15#;
	TTrue -> cont 16#;
	TFalse -> cont 17#;
	TDyadic -> cont 18#;
	TMonadic -> cont 19#;
	TCompare -> cont 20#;
	TGenPrimOp -> cont 21#;
	TThatsAllFolks -> cont 22#;
	TLowerName happy_dollar_dollar -> cont 23#;
	TUpperName happy_dollar_dollar -> cont 24#;
	TString happy_dollar_dollar -> cont 25#;
	TInteger happy_dollar_dollar -> cont 26#;
	TNoBraces happy_dollar_dollar -> cont 27#;
	_ -> happyError' tk
	})

happyError_ tk = happyError' tk

happyThen :: () => ParserM a -> (a -> ParserM b) -> ParserM b
happyThen = (>>=)
happyReturn :: () => a -> ParserM a
happyReturn = (return)
happyThen1 = happyThen
happyReturn1 :: () => a -> ParserM a
happyReturn1 = happyReturn
happyError' :: () => (Token) -> ParserM a
happyError' tk = (\token -> happyError) tk

parsex = happySomeParser where
  happySomeParser = happyThen (happyParse 0#) (\x -> happyReturn (happyOut4 x))

happySeq = happyDoSeq


parse :: String -> Either String Info
parse = run_parser parsex
{-# LINE 1 "templates/GenericTemplate.hs" #-}
{-# LINE 1 "templates/GenericTemplate.hs" #-}
{-# LINE 1 "<built-in>" #-}
{-# LINE 1 "<command-line>" #-}
{-# LINE 1 "templates/GenericTemplate.hs" #-}
-- Id: GenericTemplate.hs,v 1.26 2005/01/14 14:47:22 simonmar Exp 

{-# LINE 30 "templates/GenericTemplate.hs" #-}


data Happy_IntList = HappyCons Happy_GHC_Exts.Int# Happy_IntList





{-# LINE 51 "templates/GenericTemplate.hs" #-}

{-# LINE 61 "templates/GenericTemplate.hs" #-}

{-# LINE 70 "templates/GenericTemplate.hs" #-}

infixr 9 `HappyStk`
data HappyStk a = HappyStk a (HappyStk a)

-----------------------------------------------------------------------------
-- starting the parse

happyParse start_state = happyNewToken start_state notHappyAtAll notHappyAtAll

-----------------------------------------------------------------------------
-- Accepting the parse

-- If the current token is 0#, it means we've just accepted a partial
-- parse (a %partial parser).  We must ignore the saved token on the top of
-- the stack in this case.
happyAccept 0# tk st sts (_ `HappyStk` ans `HappyStk` _) =
	happyReturn1 ans
happyAccept j tk st sts (HappyStk ans _) = 
	(happyTcHack j (happyTcHack st)) (happyReturn1 ans)

-----------------------------------------------------------------------------
-- Arrays only: do the next action



happyDoAction i tk st
	= {- nothing -}


	  case action of
		0#		  -> {- nothing -}
				     happyFail i tk st
		-1# 	  -> {- nothing -}
				     happyAccept i tk st
		n | (n Happy_GHC_Exts.<# (0# :: Happy_GHC_Exts.Int#)) -> {- nothing -}

				     (happyReduceArr Happy_Data_Array.! rule) i tk st
				     where rule = (Happy_GHC_Exts.I# ((Happy_GHC_Exts.negateInt# ((n Happy_GHC_Exts.+# (1# :: Happy_GHC_Exts.Int#))))))
		n		  -> {- nothing -}


				     happyShift new_state i tk st
				     where (new_state) = (n Happy_GHC_Exts.-# (1# :: Happy_GHC_Exts.Int#))
   where (off)    = indexShortOffAddr happyActOffsets st
         (off_i)  = (off Happy_GHC_Exts.+# i)
	 check  = if (off_i Happy_GHC_Exts.>=# (0# :: Happy_GHC_Exts.Int#))
			then (indexShortOffAddr happyCheck off_i Happy_GHC_Exts.==#  i)
			else False
         (action)
          | check     = indexShortOffAddr happyTable off_i
          | otherwise = indexShortOffAddr happyDefActions st

{-# LINE 130 "templates/GenericTemplate.hs" #-}


indexShortOffAddr (HappyA# arr) off =
	Happy_GHC_Exts.narrow16Int# i
  where
        i = Happy_GHC_Exts.word2Int# (Happy_GHC_Exts.or# (Happy_GHC_Exts.uncheckedShiftL# high 8#) low)
        high = Happy_GHC_Exts.int2Word# (Happy_GHC_Exts.ord# (Happy_GHC_Exts.indexCharOffAddr# arr (off' Happy_GHC_Exts.+# 1#)))
        low  = Happy_GHC_Exts.int2Word# (Happy_GHC_Exts.ord# (Happy_GHC_Exts.indexCharOffAddr# arr off'))
        off' = off Happy_GHC_Exts.*# 2#





data HappyAddr = HappyA# Happy_GHC_Exts.Addr#




-----------------------------------------------------------------------------
-- HappyState data type (not arrays)

{-# LINE 163 "templates/GenericTemplate.hs" #-}

-----------------------------------------------------------------------------
-- Shifting a token

happyShift new_state 0# tk st sts stk@(x `HappyStk` _) =
     let (i) = (case Happy_GHC_Exts.unsafeCoerce# x of { (Happy_GHC_Exts.I# (i)) -> i }) in
--     trace "shifting the error token" $
     happyDoAction i tk new_state (HappyCons (st) (sts)) (stk)

happyShift new_state i tk st sts stk =
     happyNewToken new_state (HappyCons (st) (sts)) ((happyInTok (tk))`HappyStk`stk)

-- happyReduce is specialised for the common cases.

happySpecReduce_0 i fn 0# tk st sts stk
     = happyFail 0# tk st sts stk
happySpecReduce_0 nt fn j tk st@((action)) sts stk
     = happyGoto nt j tk st (HappyCons (st) (sts)) (fn `HappyStk` stk)

happySpecReduce_1 i fn 0# tk st sts stk
     = happyFail 0# tk st sts stk
happySpecReduce_1 nt fn j tk _ sts@((HappyCons (st@(action)) (_))) (v1`HappyStk`stk')
     = let r = fn v1 in
       happySeq r (happyGoto nt j tk st sts (r `HappyStk` stk'))

happySpecReduce_2 i fn 0# tk st sts stk
     = happyFail 0# tk st sts stk
happySpecReduce_2 nt fn j tk _ (HappyCons (_) (sts@((HappyCons (st@(action)) (_))))) (v1`HappyStk`v2`HappyStk`stk')
     = let r = fn v1 v2 in
       happySeq r (happyGoto nt j tk st sts (r `HappyStk` stk'))

happySpecReduce_3 i fn 0# tk st sts stk
     = happyFail 0# tk st sts stk
happySpecReduce_3 nt fn j tk _ (HappyCons (_) ((HappyCons (_) (sts@((HappyCons (st@(action)) (_))))))) (v1`HappyStk`v2`HappyStk`v3`HappyStk`stk')
     = let r = fn v1 v2 v3 in
       happySeq r (happyGoto nt j tk st sts (r `HappyStk` stk'))

happyReduce k i fn 0# tk st sts stk
     = happyFail 0# tk st sts stk
happyReduce k nt fn j tk st sts stk
     = case happyDrop (k Happy_GHC_Exts.-# (1# :: Happy_GHC_Exts.Int#)) sts of
	 sts1@((HappyCons (st1@(action)) (_))) ->
        	let r = fn stk in  -- it doesn't hurt to always seq here...
       		happyDoSeq r (happyGoto nt j tk st1 sts1 r)

happyMonadReduce k nt fn 0# tk st sts stk
     = happyFail 0# tk st sts stk
happyMonadReduce k nt fn j tk st sts stk =
        happyThen1 (fn stk tk) (\r -> happyGoto nt j tk st1 sts1 (r `HappyStk` drop_stk))
       where (sts1@((HappyCons (st1@(action)) (_)))) = happyDrop k (HappyCons (st) (sts))
             drop_stk = happyDropStk k stk

happyMonad2Reduce k nt fn 0# tk st sts stk
     = happyFail 0# tk st sts stk
happyMonad2Reduce k nt fn j tk st sts stk =
       happyThen1 (fn stk tk) (\r -> happyNewToken new_state sts1 (r `HappyStk` drop_stk))
       where (sts1@((HappyCons (st1@(action)) (_)))) = happyDrop k (HappyCons (st) (sts))
             drop_stk = happyDropStk k stk

             (off) = indexShortOffAddr happyGotoOffsets st1
             (off_i) = (off Happy_GHC_Exts.+# nt)
             (new_state) = indexShortOffAddr happyTable off_i




happyDrop 0# l = l
happyDrop n (HappyCons (_) (t)) = happyDrop (n Happy_GHC_Exts.-# (1# :: Happy_GHC_Exts.Int#)) t

happyDropStk 0# l = l
happyDropStk n (x `HappyStk` xs) = happyDropStk (n Happy_GHC_Exts.-# (1#::Happy_GHC_Exts.Int#)) xs

-----------------------------------------------------------------------------
-- Moving to a new state after a reduction


happyGoto nt j tk st = 
   {- nothing -}
   happyDoAction j tk new_state
   where (off) = indexShortOffAddr happyGotoOffsets st
         (off_i) = (off Happy_GHC_Exts.+# nt)
         (new_state) = indexShortOffAddr happyTable off_i




-----------------------------------------------------------------------------
-- Error recovery (0# is the error token)

-- parse error if we are in recovery and we fail again
happyFail  0# tk old_st _ stk =
--	trace "failing" $ 
    	happyError_ tk

{-  We don't need state discarding for our restricted implementation of
    "error".  In fact, it can cause some bogus parses, so I've disabled it
    for now --SDM

-- discard a state
happyFail  0# tk old_st (HappyCons ((action)) (sts)) 
						(saved_tok `HappyStk` _ `HappyStk` stk) =
--	trace ("discarding state, depth " ++ show (length stk))  $
	happyDoAction 0# tk action sts ((saved_tok`HappyStk`stk))
-}

-- Enter error recovery: generate an error token,
--                       save the old token and carry on.
happyFail  i tk (action) sts stk =
--      trace "entering error recovery" $
	happyDoAction 0# tk action sts ( (Happy_GHC_Exts.unsafeCoerce# (Happy_GHC_Exts.I# (i))) `HappyStk` stk)

-- Internal happy errors:

notHappyAtAll :: a
notHappyAtAll = error "Internal Happy error\n"

-----------------------------------------------------------------------------
-- Hack to get the typechecker to accept our action functions


happyTcHack :: Happy_GHC_Exts.Int# -> a -> a
happyTcHack x y = y
{-# INLINE happyTcHack #-}


-----------------------------------------------------------------------------
-- Seq-ing.  If the --strict flag is given, then Happy emits 
--	happySeq = happyDoSeq
-- otherwise it emits
-- 	happySeq = happyDontSeq

happyDoSeq, happyDontSeq :: a -> b -> b
happyDoSeq   a b = a `seq` b
happyDontSeq a b = b

-----------------------------------------------------------------------------
-- Don't inline any functions from the template.  GHC has a nasty habit
-- of deciding to inline happyGoto everywhere, which increases the size of
-- the generated parser quite a bit.


{-# NOINLINE happyDoAction #-}
{-# NOINLINE happyTable #-}
{-# NOINLINE happyCheck #-}
{-# NOINLINE happyActOffsets #-}
{-# NOINLINE happyGotoOffsets #-}
{-# NOINLINE happyDefActions #-}

{-# NOINLINE happyShift #-}
{-# NOINLINE happySpecReduce_0 #-}
{-# NOINLINE happySpecReduce_1 #-}
{-# NOINLINE happySpecReduce_2 #-}
{-# NOINLINE happySpecReduce_3 #-}
{-# NOINLINE happyReduce #-}
{-# NOINLINE happyMonadReduce #-}
{-# NOINLINE happyGoto #-}
{-# NOINLINE happyFail #-}

-- end of Happy Template.
