{-# OPTIONS_GHC -fno-warn-overlapping-patterns #-}
{-# OPTIONS -fglasgow-exts -cpp #-}
{-# OPTIONS -Wwarn -w -XNoMonomorphismRestriction #-}
-- The NoMonomorphismRestriction deals with a Happy infelicity
--    With OutsideIn's more conservativ monomorphism restriction
--    we aren't generalising
--        notHappyAtAll = error "urk"
--    which is terrible.  Switching off the restriction allows
--    the generalisation.  Better would be to make Happy generate
--    an appropriate signature.
--
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

module CmmParse ( parseCmmFile ) where

import CgMonad		hiding (getDynFlags)
import CgExtCode
import CgHeapery
import CgUtils
import CgProf
import CgTicky
import CgInfoTbls
import CgForeignCall
import CgTailCall
import CgStackery
import ClosureInfo
import CgCallConv
import CgClosure
import CostCentre

import BlockId
import Cmm
import PprCmm
import CmmUtils
import CmmLex
import CLabel
import SMRep
import Lexer

import ForeignCall
import Module
import Literal
import Unique
import UniqFM
import SrcLoc
import DynFlags
import StaticFlags
import ErrUtils
import StringBuffer
import FastString
import Panic
import Constants
import Outputable
import BasicTypes
import Bag              ( emptyBag, unitBag )
import Var

import Control.Monad
import Data.Array
import Data.Char	( ord )
import System.Exit

#include "HsVersions.h"
#if __GLASGOW_HASKELL__ >= 503
import qualified Data.Array as Happy_Data_Array
#else
import qualified Array as Happy_Data_Array
#endif
#if __GLASGOW_HASKELL__ >= 503
import qualified GHC.Exts as Happy_GHC_Exts
#else
import qualified GlaExts as Happy_GHC_Exts
#endif

-- parser produced by Happy Version 1.18.4

newtype HappyAbsSyn  = HappyAbsSyn HappyAny
#if __GLASGOW_HASKELL__ >= 607
type HappyAny = Happy_GHC_Exts.Any
#else
type HappyAny = forall a . a
#endif
happyIn4 :: (ExtCode) -> (HappyAbsSyn )
happyIn4 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn4 #-}
happyOut4 :: (HappyAbsSyn ) -> (ExtCode)
happyOut4 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut4 #-}
happyIn5 :: (ExtCode) -> (HappyAbsSyn )
happyIn5 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn5 #-}
happyOut5 :: (HappyAbsSyn ) -> (ExtCode)
happyOut5 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut5 #-}
happyIn6 :: (ExtCode) -> (HappyAbsSyn )
happyIn6 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn6 #-}
happyOut6 :: (HappyAbsSyn ) -> (ExtCode)
happyOut6 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut6 #-}
happyIn7 :: ([ExtFCode [CmmStatic]]) -> (HappyAbsSyn )
happyIn7 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn7 #-}
happyOut7 :: (HappyAbsSyn ) -> ([ExtFCode [CmmStatic]])
happyOut7 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut7 #-}
happyIn8 :: (ExtFCode [CmmStatic]) -> (HappyAbsSyn )
happyIn8 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn8 #-}
happyOut8 :: (HappyAbsSyn ) -> (ExtFCode [CmmStatic])
happyOut8 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut8 #-}
happyIn9 :: ([ExtFCode CmmExpr]) -> (HappyAbsSyn )
happyIn9 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn9 #-}
happyOut9 :: (HappyAbsSyn ) -> ([ExtFCode CmmExpr])
happyOut9 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut9 #-}
happyIn10 :: (ExtCode) -> (HappyAbsSyn )
happyIn10 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn10 #-}
happyOut10 :: (HappyAbsSyn ) -> (ExtCode)
happyOut10 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut10 #-}
happyIn11 :: (ExtFCode (CLabel, CmmInfoTable, [Maybe LocalReg])) -> (HappyAbsSyn )
happyIn11 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn11 #-}
happyOut11 :: (HappyAbsSyn ) -> (ExtFCode (CLabel, CmmInfoTable, [Maybe LocalReg]))
happyOut11 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut11 #-}
happyIn12 :: (ExtCode) -> (HappyAbsSyn )
happyIn12 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn12 #-}
happyOut12 :: (HappyAbsSyn ) -> (ExtCode)
happyOut12 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut12 #-}
happyIn13 :: (ExtCode) -> (HappyAbsSyn )
happyIn13 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn13 #-}
happyOut13 :: (HappyAbsSyn ) -> (ExtCode)
happyOut13 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut13 #-}
happyIn14 :: ([(FastString, CLabel)]) -> (HappyAbsSyn )
happyIn14 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn14 #-}
happyOut14 :: (HappyAbsSyn ) -> ([(FastString, CLabel)])
happyOut14 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut14 #-}
happyIn15 :: ((FastString,  CLabel)) -> (HappyAbsSyn )
happyIn15 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn15 #-}
happyOut15 :: (HappyAbsSyn ) -> ((FastString,  CLabel))
happyOut15 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut15 #-}
happyIn16 :: ([FastString]) -> (HappyAbsSyn )
happyIn16 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn16 #-}
happyOut16 :: (HappyAbsSyn ) -> ([FastString])
happyOut16 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut16 #-}
happyIn17 :: (ExtCode) -> (HappyAbsSyn )
happyIn17 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn17 #-}
happyOut17 :: (HappyAbsSyn ) -> (ExtCode)
happyOut17 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut17 #-}
happyIn18 :: (CmmReturnInfo) -> (HappyAbsSyn )
happyIn18 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn18 #-}
happyOut18 :: (HappyAbsSyn ) -> (CmmReturnInfo)
happyOut18 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut18 #-}
happyIn19 :: (ExtFCode BoolExpr) -> (HappyAbsSyn )
happyIn19 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn19 #-}
happyOut19 :: (HappyAbsSyn ) -> (ExtFCode BoolExpr)
happyOut19 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut19 #-}
happyIn20 :: (ExtFCode BoolExpr) -> (HappyAbsSyn )
happyIn20 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn20 #-}
happyOut20 :: (HappyAbsSyn ) -> (ExtFCode BoolExpr)
happyOut20 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut20 #-}
happyIn21 :: (CmmSafety) -> (HappyAbsSyn )
happyIn21 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn21 #-}
happyOut21 :: (HappyAbsSyn ) -> (CmmSafety)
happyOut21 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut21 #-}
happyIn22 :: (Maybe [GlobalReg]) -> (HappyAbsSyn )
happyIn22 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn22 #-}
happyOut22 :: (HappyAbsSyn ) -> (Maybe [GlobalReg])
happyOut22 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut22 #-}
happyIn23 :: ([GlobalReg]) -> (HappyAbsSyn )
happyIn23 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn23 #-}
happyOut23 :: (HappyAbsSyn ) -> ([GlobalReg])
happyOut23 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut23 #-}
happyIn24 :: (Maybe (Int,Int)) -> (HappyAbsSyn )
happyIn24 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn24 #-}
happyOut24 :: (HappyAbsSyn ) -> (Maybe (Int,Int))
happyOut24 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut24 #-}
happyIn25 :: ([([Int],ExtCode)]) -> (HappyAbsSyn )
happyIn25 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn25 #-}
happyOut25 :: (HappyAbsSyn ) -> ([([Int],ExtCode)])
happyOut25 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut25 #-}
happyIn26 :: (([Int],ExtCode)) -> (HappyAbsSyn )
happyIn26 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn26 #-}
happyOut26 :: (HappyAbsSyn ) -> (([Int],ExtCode))
happyOut26 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut26 #-}
happyIn27 :: ([Int]) -> (HappyAbsSyn )
happyIn27 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn27 #-}
happyOut27 :: (HappyAbsSyn ) -> ([Int])
happyOut27 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut27 #-}
happyIn28 :: (Maybe ExtCode) -> (HappyAbsSyn )
happyIn28 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn28 #-}
happyOut28 :: (HappyAbsSyn ) -> (Maybe ExtCode)
happyOut28 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut28 #-}
happyIn29 :: (ExtCode) -> (HappyAbsSyn )
happyIn29 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn29 #-}
happyOut29 :: (HappyAbsSyn ) -> (ExtCode)
happyOut29 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut29 #-}
happyIn30 :: (ExtFCode CmmExpr) -> (HappyAbsSyn )
happyIn30 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn30 #-}
happyOut30 :: (HappyAbsSyn ) -> (ExtFCode CmmExpr)
happyOut30 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut30 #-}
happyIn31 :: (ExtFCode CmmExpr) -> (HappyAbsSyn )
happyIn31 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn31 #-}
happyOut31 :: (HappyAbsSyn ) -> (ExtFCode CmmExpr)
happyOut31 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut31 #-}
happyIn32 :: (CmmType) -> (HappyAbsSyn )
happyIn32 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn32 #-}
happyOut32 :: (HappyAbsSyn ) -> (CmmType)
happyOut32 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut32 #-}
happyIn33 :: ([ExtFCode HintedCmmActual]) -> (HappyAbsSyn )
happyIn33 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn33 #-}
happyOut33 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmActual])
happyOut33 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut33 #-}
happyIn34 :: ([ExtFCode HintedCmmActual]) -> (HappyAbsSyn )
happyIn34 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn34 #-}
happyOut34 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmActual])
happyOut34 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut34 #-}
happyIn35 :: ([ExtFCode HintedCmmActual]) -> (HappyAbsSyn )
happyIn35 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn35 #-}
happyOut35 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmActual])
happyOut35 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut35 #-}
happyIn36 :: (ExtFCode HintedCmmActual) -> (HappyAbsSyn )
happyIn36 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn36 #-}
happyOut36 :: (HappyAbsSyn ) -> (ExtFCode HintedCmmActual)
happyOut36 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut36 #-}
happyIn37 :: ([ExtFCode CmmExpr]) -> (HappyAbsSyn )
happyIn37 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn37 #-}
happyOut37 :: (HappyAbsSyn ) -> ([ExtFCode CmmExpr])
happyOut37 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut37 #-}
happyIn38 :: ([ExtFCode CmmExpr]) -> (HappyAbsSyn )
happyIn38 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn38 #-}
happyOut38 :: (HappyAbsSyn ) -> ([ExtFCode CmmExpr])
happyOut38 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut38 #-}
happyIn39 :: (ExtFCode CmmExpr) -> (HappyAbsSyn )
happyIn39 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn39 #-}
happyOut39 :: (HappyAbsSyn ) -> (ExtFCode CmmExpr)
happyOut39 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut39 #-}
happyIn40 :: ([ExtFCode HintedCmmFormal]) -> (HappyAbsSyn )
happyIn40 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn40 #-}
happyOut40 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmFormal])
happyOut40 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut40 #-}
happyIn41 :: ([ExtFCode HintedCmmFormal]) -> (HappyAbsSyn )
happyIn41 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn41 #-}
happyOut41 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmFormal])
happyOut41 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut41 #-}
happyIn42 :: (ExtFCode HintedCmmFormal) -> (HappyAbsSyn )
happyIn42 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn42 #-}
happyOut42 :: (HappyAbsSyn ) -> (ExtFCode HintedCmmFormal)
happyOut42 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut42 #-}
happyIn43 :: (ExtFCode LocalReg) -> (HappyAbsSyn )
happyIn43 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn43 #-}
happyOut43 :: (HappyAbsSyn ) -> (ExtFCode LocalReg)
happyOut43 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut43 #-}
happyIn44 :: (ExtFCode CmmReg) -> (HappyAbsSyn )
happyIn44 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn44 #-}
happyOut44 :: (HappyAbsSyn ) -> (ExtFCode CmmReg)
happyOut44 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut44 #-}
happyIn45 :: ([ExtFCode LocalReg]) -> (HappyAbsSyn )
happyIn45 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn45 #-}
happyOut45 :: (HappyAbsSyn ) -> ([ExtFCode LocalReg])
happyOut45 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut45 #-}
happyIn46 :: ([ExtFCode LocalReg]) -> (HappyAbsSyn )
happyIn46 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn46 #-}
happyOut46 :: (HappyAbsSyn ) -> ([ExtFCode LocalReg])
happyOut46 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut46 #-}
happyIn47 :: ([ExtFCode LocalReg]) -> (HappyAbsSyn )
happyIn47 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn47 #-}
happyOut47 :: (HappyAbsSyn ) -> ([ExtFCode LocalReg])
happyOut47 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut47 #-}
happyIn48 :: (ExtFCode LocalReg) -> (HappyAbsSyn )
happyIn48 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn48 #-}
happyOut48 :: (HappyAbsSyn ) -> (ExtFCode LocalReg)
happyOut48 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut48 #-}
happyIn49 :: (ExtFCode (Maybe UpdateFrame)) -> (HappyAbsSyn )
happyIn49 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn49 #-}
happyOut49 :: (HappyAbsSyn ) -> (ExtFCode (Maybe UpdateFrame))
happyOut49 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut49 #-}
happyIn50 :: (ExtFCode (Maybe BlockId)) -> (HappyAbsSyn )
happyIn50 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn50 #-}
happyOut50 :: (HappyAbsSyn ) -> (ExtFCode (Maybe BlockId))
happyOut50 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut50 #-}
happyIn51 :: (CmmType) -> (HappyAbsSyn )
happyIn51 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn51 #-}
happyOut51 :: (HappyAbsSyn ) -> (CmmType)
happyOut51 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut51 #-}
happyIn52 :: (CmmType) -> (HappyAbsSyn )
happyIn52 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn52 #-}
happyOut52 :: (HappyAbsSyn ) -> (CmmType)
happyOut52 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut52 #-}
happyInTok :: (Located CmmToken) -> (HappyAbsSyn )
happyInTok x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyInTok #-}
happyOutTok :: (HappyAbsSyn ) -> (Located CmmToken)
happyOutTok x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOutTok #-}


happyActOffsets :: HappyAddr
happyActOffsets = HappyA# "\x33\x01\x00\x00\x57\x03\x33\x01\x00\x00\x00\x00\x92\x03\x00\x00\x47\x03\x00\x00\x71\x03\x70\x03\x6f\x03\x6c\x03\x66\x03\x65\x03\x29\x03\x31\x03\x05\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x60\x03\x2b\x03\x3c\x01\x4a\x03\x32\x03\x00\x00\x26\x03\x46\x03\x38\x03\x30\x03\x23\x03\x21\x03\x1d\x03\x1c\x03\x1b\x03\x0b\x03\x28\x03\x09\x00\x00\x00\xf8\x02\x00\x00\x0a\x03\x00\x00\x2c\x03\x2a\x03\x25\x03\x1a\x03\x17\x03\x16\x03\xeb\x02\x00\x00\x47\x01\x00\x00\x05\x01\x00\x00\x10\x03\x00\x00\x0c\x03\xe8\x02\xed\x02\x08\x03\x61\x00\x00\x00\x3c\x01\x00\x00\x00\x00\x0d\x03\x47\x01\xff\xff\x07\x03\x09\x03\xd0\x02\x05\x03\xfa\x02\x00\x00\xc6\x02\xc4\x02\xb8\x02\xb5\x02\xb3\x02\xa9\x02\x00\x00\xe2\x02\x1a\x00\xde\x02\xdb\x02\x12\x00\xd9\x02\xd5\x02\xd4\x02\x00\x00\x02\x00\xd8\x02\x99\x02\x95\x02\xa4\x01\xce\x02\x00\x00\xcf\x02\x00\x00\x61\x00\x61\x00\x96\x02\x61\x00\x00\x00\x00\x00\x00\x00\xb7\x02\xb7\x02\x00\x00\x00\x00\x00\x00\x37\x02\x1a\x00\xca\x02\x1a\x00\x1a\x00\xa7\x00\xc0\x02\x0d\x00\x00\x00\xf8\x00\x88\x02\x54\x00\x61\x00\xb9\x02\xb6\x02\x00\x00\x1c\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x00\x00\x3c\x01\x00\x00\x02\x01\xa1\x02\x00\x00\x4f\x02\x61\x00\x78\x02\x00\x00\xb4\x02\xa3\x02\x00\x00\x59\x02\xa5\x02\x74\x02\x5b\x02\x53\x02\x00\x00\x3c\x01\x4d\x02\x86\x02\x61\x00\x7f\x02\x00\x00\x82\x03\x8b\x02\x6a\x02\x75\x02\x69\x02\x68\x02\x66\x02\x79\x02\x77\x02\x60\x02\x65\x02\x5c\x02\xec\x01\x00\x00\x61\x00\x00\x00\xaa\x03\xaa\x03\xaa\x03\xaa\x03\x7b\x00\x7b\x00\xaa\x03\xaa\x03\xbe\x03\xc5\x03\xf9\x00\x02\x01\x02\x01\x00\x00\x00\x00\x00\x00\x6e\x03\x5d\x02\x00\x00\x00\x00\x61\x00\x61\x00\x17\x02\x58\x02\x61\x00\x1e\x02\x4d\x00\x00\x00\x96\x03\x54\x00\x54\x00\x56\x02\x45\x02\x3a\x02\x00\x00\x00\x00\x0f\x02\x61\x00\x61\x00\x0d\x02\x34\x02\x00\x00\x00\x00\x00\x00\x01\x02\x61\x00\x90\x01\xd2\x01\x00\x00\xf8\x00\x36\x02\x00\x00\x00\x00\x00\x01\x38\x02\x4f\x02\x1a\x00\x54\x00\x54\x00\x35\x02\x99\x00\x2e\x02\x00\x00\x10\x02\x00\x00\xf7\x01\xb8\x01\x2d\x02\x00\x00\x61\x00\x2c\x02\x00\x00\x43\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe8\x01\xe6\x01\xe5\x01\x00\x00\xd9\x01\x00\x00\x00\x00\x08\x02\x07\x02\x06\x02\xfa\x01\x00\x00\x00\x00\x00\x00\x0c\x02\xd7\x01\xc3\x01\x61\x00\x00\x00\x00\x00\x00\x00\x00\x01\xe4\x01\xff\x01\x00\x00\x00\x00\x00\x00\xf9\x01\x00\x00\x05\x02\xf0\x01\x61\x00\x61\x00\x61\x00\xce\x01\x00\x00\xef\x01\xbd\x01\xb3\x01\xb1\x01\x00\x00\xaa\x01\xa8\x01\xa7\x01\x9c\x01\xc6\x01\xc5\x01\xc4\x01\xd1\x01\xcf\x01\xbb\x01\x00\x00\xcb\x01\xcd\x01\x00\x00\x00\x00\xba\x01\x7c\x01\xb4\x01\x9f\x01\x68\x01\x68\x01\x00\x00\x1a\x00\xa5\x01\x00\x00\x78\x01\x92\x01\x00\x00\x53\x01\x52\x01\x45\x01\x74\x01\x67\x01\x65\x01\x1a\x00\x00\x00\x1a\x00\x66\x01\x63\x01\x00\x00\x63\x01\x64\x01\x06\x00\x35\x01\x00\x00\x60\x01\x5e\x01\x22\x01\x19\x01\x00\x00\x11\x00\x4b\x01\x00\x00\x00\x00\x4d\x01\x15\x01\x41\x01\x00\x00\x38\x01\x00\x00\xfe\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0b\x01\x32\x01\x00\x00\x00\x00\x00\x00"#

happyGotoOffsets :: HappyAddr
happyGotoOffsets = HappyA# "\xb9\x00\x00\x00\x00\x00\x2d\x00\x00\x00\x00\x00\x0e\x01\x00\x00\x29\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x1d\x01\x00\x00\x0d\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x09\x01\x01\x01\xb2\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xee\x00\x00\x00\xed\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x06\x01\x00\x00\xac\x00\x00\x00\xdc\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xd6\x00\x00\x00\x56\x03\x00\x00\xa0\x00\x00\x00\x00\x00\x00\x00\x01\x00\x45\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x04\x01\xf3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x3f\x03\x3b\x03\x00\x00\x35\x03\x00\x00\x00\x00\x00\x00\xe5\x00\xd5\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf7\x00\x00\x00\xf5\x00\xcc\x00\x00\x00\x00\x00\xe3\x00\x00\x00\xd0\x00\x00\x00\x31\x01\x24\x03\xc7\x00\xdf\x00\x00\x00\x00\x00\x81\x02\x22\x03\x1e\x03\x14\x03\x06\x03\x04\x03\x02\x03\xf4\x02\xea\x02\xe6\x02\xe4\x02\xd3\x02\xcd\x02\xc9\x02\xc3\x02\xb2\x02\xb0\x02\x00\x00\x9e\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xac\x02\x00\x00\x00\x00\x00\x00\xdd\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x48\x00\x00\x00\x00\x00\xa2\x02\x00\x00\x00\x00\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x71\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x67\x02\x94\x02\x00\x00\x00\x00\x55\x02\xaa\x00\x00\x00\x00\x00\x00\x00\x2f\x01\x21\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x9a\x00\x92\x02\x8f\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x84\x02\x00\x00\x00\x00\x00\x00\x97\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xca\x00\x13\x01\xfb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x76\x02\x00\x00\x00\x00\xae\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x9c\x00\x00\x00\x57\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x46\x00\xf5\xff\xfc\xff\x58\x00\x00\x00\x00\x00\x80\x00\x64\x00\x47\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x59\x00\x56\x00\x00\x00\xbd\x00\x00\x00\x00\x00\x1b\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xbb\x00\x00\x00\xfa\xff\x00\x00\x14\x00\x00\x00\x0e\x00\x00\x00\x08\x00\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf6\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"#

happyDefActions :: HappyAddr
happyDefActions = HappyA# "\xfe\xff\x00\x00\x00\x00\xfe\xff\xfb\xff\xfc\xff\x7a\xff\xfa\xff\x00\x00\x6d\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x6e\xff\x6c\xff\x6b\xff\x6a\xff\x69\xff\x68\xff\x67\xff\x7a\xff\x70\xff\x78\xff\x00\x00\xdb\xff\xd9\xff\x00\x00\x00\x00\x00\x00\xd7\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x70\xff\xfd\xff\x72\xff\xea\xff\x00\x00\xde\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xdc\xff\xf7\xff\xd8\xff\x00\x00\xdd\xff\x00\x00\x77\xff\x75\xff\x00\x00\x72\xff\x00\x00\x00\x00\x73\xff\x76\xff\x79\xff\xda\xff\x00\x00\xf7\xff\x00\x00\x6d\xff\x00\x00\x00\x00\x6e\xff\x00\x00\xd6\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x6f\xff\x00\x00\xe1\xff\xed\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf5\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x9c\xff\x98\xff\x00\x00\xf3\xff\x00\x00\x00\x00\x00\x00\x00\x00\x85\xff\x86\xff\x99\xff\x94\xff\x94\xff\xf6\xff\xf8\xff\x74\xff\x00\x00\xe1\xff\x00\x00\xe1\xff\xe1\xff\x00\x00\x00\x00\x00\x00\xd5\xff\x00\x00\x00\x00\x00\x00\x00\x00\x92\xff\xb9\xff\x7b\xff\x7c\xff\x8a\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x9a\xff\x00\x00\x9b\xff\x9e\xff\x00\x00\x9f\xff\x00\x00\x00\x00\x00\x00\xf4\xff\x00\x00\xed\xff\xef\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe3\xff\x78\xff\x00\x00\x00\x00\x00\x00\x00\x00\xeb\xff\xed\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x95\xff\x8a\xff\x93\xff\xa1\xff\xa0\xff\xa3\xff\xa5\xff\xa9\xff\xaa\xff\xa2\xff\xa4\xff\xa6\xff\xa7\xff\xa8\xff\xab\xff\xac\xff\xad\xff\xae\xff\xaf\xff\x88\xff\x00\x00\x89\xff\xd4\xff\x8a\xff\x00\x00\x00\x00\x00\x00\x90\xff\x92\xff\x00\x00\xc7\xff\xc6\xff\x00\x00\x00\x00\x00\x00\x00\x00\x82\xff\x7f\xff\x7d\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xdf\xff\xe0\xff\xe9\xff\x00\x00\x00\x00\x00\x00\x00\x00\x7e\xff\x81\xff\x00\x00\xcd\xff\xc3\xff\x00\x00\xc7\xff\xc6\xff\xe1\xff\x00\x00\x00\x00\x00\x00\x8c\xff\x00\x00\x8f\xff\x8e\xff\xcb\xff\x00\x00\x00\x00\x00\x00\x71\xff\x00\x00\x00\x00\x97\xff\x00\x00\xf0\xff\xee\xff\xf2\xff\xf1\xff\x00\x00\x00\x00\x00\x00\xe2\xff\x00\x00\xf9\xff\xec\xff\x00\x00\x00\x00\x00\x00\x00\x00\x9d\xff\x96\xff\x87\xff\x00\x00\xb8\xff\x00\x00\x00\x00\x91\xff\x8b\xff\xcc\xff\xc4\xff\xc5\xff\x00\x00\xc2\xff\x83\xff\x80\xff\x00\x00\xd3\xff\x00\x00\x00\x00\x90\xff\x90\xff\x00\x00\xb1\xff\x8d\xff\x00\x00\xb2\xff\xb8\xff\x00\x00\xcf\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xb5\xff\xb7\xff\x00\x00\x00\x00\xba\xff\xca\xff\x00\x00\x00\x00\x00\x00\x00\x00\xc1\xff\xc1\xff\xd2\xff\xe1\xff\x00\x00\xce\xff\x00\x00\x00\x00\xe4\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe1\xff\xb4\xff\xe1\xff\x00\x00\xbf\xff\xc0\xff\xbf\xff\x00\x00\x00\x00\xc9\xff\xb0\xff\x00\x00\x00\x00\x00\x00\x00\x00\xe8\xff\x00\x00\x00\x00\xb6\xff\xb3\xff\x00\x00\x00\x00\x00\x00\xbe\xff\xbc\xff\xd0\xff\x00\x00\xbd\xff\xc8\xff\xd1\xff\xe5\xff\xe7\xff\x00\x00\x00\x00\xbb\xff\xe6\xff"#

happyCheck :: HappyAddr
happyCheck = HappyA# "\xff\xff\x02\x00\x08\x00\x09\x00\x03\x00\x04\x00\x07\x00\x0d\x00\x06\x00\x13\x00\x0b\x00\x02\x00\x06\x00\x0e\x00\x0f\x00\x1a\x00\x1b\x00\x0e\x00\x05\x00\x1e\x00\x1f\x00\x20\x00\x1a\x00\x1b\x00\x23\x00\x08\x00\x08\x00\x13\x00\x02\x00\x01\x00\x24\x00\x23\x00\x12\x00\x07\x00\x28\x00\x07\x00\x2f\x00\x30\x00\x12\x00\x16\x00\x16\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x00\x00\x01\x00\x02\x00\x2f\x00\x30\x00\x17\x00\x06\x00\x07\x00\x2c\x00\x09\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x43\x00\x29\x00\x42\x00\x3f\x00\x2c\x00\x2d\x00\x2e\x00\x2f\x00\x07\x00\x31\x00\x32\x00\x40\x00\x34\x00\x35\x00\x03\x00\x0e\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x07\x00\x2f\x00\x30\x00\x17\x00\x0b\x00\x1a\x00\x1b\x00\x0e\x00\x0f\x00\x1e\x00\x1f\x00\x20\x00\x11\x00\x07\x00\x23\x00\x11\x00\x17\x00\x0b\x00\x20\x00\x21\x00\x0e\x00\x0f\x00\x19\x00\x2a\x00\x2b\x00\x2c\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x15\x00\x16\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x43\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x43\x00\x18\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x43\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x03\x00\x04\x00\x15\x00\x16\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x00\x00\x01\x00\x02\x00\x25\x00\x26\x00\x27\x00\x06\x00\x07\x00\x27\x00\x09\x00\x08\x00\x09\x00\x08\x00\x09\x00\x1d\x00\x0d\x00\x1b\x00\x0d\x00\x2b\x00\x2c\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x23\x00\x08\x00\x09\x00\x08\x00\x09\x00\x2f\x00\x0d\x00\x31\x00\x0d\x00\x41\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x24\x00\x05\x00\x24\x00\x05\x00\x28\x00\x1d\x00\x28\x00\x0a\x00\x0b\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x24\x00\x0c\x00\x24\x00\x1c\x00\x28\x00\x14\x00\x28\x00\x25\x00\x26\x00\x27\x00\x05\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x08\x00\x09\x00\x08\x00\x09\x00\x1c\x00\x0d\x00\x2d\x00\x0d\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x0f\x00\x10\x00\x08\x00\x09\x00\x0c\x00\x0d\x00\x0e\x00\x0d\x00\x0c\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x0a\x00\x0b\x00\x24\x00\x2d\x00\x24\x00\x2e\x00\x28\x00\x23\x00\x28\x00\x20\x00\x21\x00\x0f\x00\x10\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x24\x00\x0c\x00\x2f\x00\x30\x00\x28\x00\x1a\x00\x1b\x00\x2e\x00\x0f\x00\x10\x00\x29\x00\x2f\x00\x30\x00\x0c\x00\x23\x00\x29\x00\x40\x00\x41\x00\x08\x00\x1a\x00\x1b\x00\x3f\x00\x0f\x00\x10\x00\x0f\x00\x10\x00\x2f\x00\x30\x00\x23\x00\x40\x00\x41\x00\x06\x00\x33\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x42\x00\x16\x00\x02\x00\x2f\x00\x30\x00\x23\x00\x08\x00\x23\x00\x22\x00\x23\x00\x24\x00\x25\x00\x26\x00\x27\x00\x42\x00\x29\x00\x2a\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x04\x00\x41\x00\x04\x00\x30\x00\x02\x00\x34\x00\x05\x00\x22\x00\x04\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x2b\x00\x40\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x16\x00\x08\x00\x16\x00\x02\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x41\x00\x40\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x02\x00\x41\x00\x41\x00\x03\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x02\x00\x08\x00\x03\x00\x41\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x42\x00\x03\x00\x08\x00\x03\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x01\x00\x04\x00\x01\x00\x16\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x06\x00\x08\x00\x16\x00\x16\x00\x16\x00\x41\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x41\x00\x36\x00\x42\x00\x41\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x06\x00\x42\x00\x37\x00\x06\x00\x28\x00\x07\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x09\x00\x04\x00\x20\x00\x42\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x07\x00\x36\x00\x02\x00\x18\x00\x16\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x42\x00\x16\x00\x16\x00\x16\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x07\x00\x16\x00\x42\x00\x42\x00\x41\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x08\x00\x08\x00\x08\x00\x02\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x07\x00\x09\x00\x08\x00\x40\x00\x0e\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x08\x00\x41\x00\x40\x00\x16\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x08\x00\x02\x00\x42\x00\x02\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x08\x00\x0a\x00\x02\x00\x08\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x1e\x00\x1f\x00\x20\x00\x1f\x00\x20\x00\x23\x00\x02\x00\x23\x00\x02\x00\x16\x00\x08\x00\x16\x00\x16\x00\x16\x00\x1a\x00\x1b\x00\x04\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x21\x00\x22\x00\x23\x00\x1a\x00\x1b\x00\x02\x00\x08\x00\x42\x00\x1a\x00\x1b\x00\x21\x00\x22\x00\x23\x00\x42\x00\x2f\x00\x30\x00\x22\x00\x23\x00\x41\x00\x1a\x00\x1b\x00\x42\x00\x1a\x00\x1b\x00\x2f\x00\x30\x00\x21\x00\x22\x00\x23\x00\x2f\x00\x30\x00\x23\x00\x07\x00\x1a\x00\x1b\x00\x06\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x2f\x00\x30\x00\x23\x00\x2f\x00\x30\x00\x23\x00\x42\x00\x23\x00\x40\x00\x16\x00\x06\x00\x05\x00\x1a\x00\x1b\x00\x2f\x00\x30\x00\x07\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x23\x00\x1a\x00\x1b\x00\x40\x00\x09\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x04\x00\x23\x00\x19\x00\x2f\x00\x30\x00\x23\x00\x05\x00\x23\x00\x40\x00\x42\x00\x0a\x00\x40\x00\x02\x00\x2f\x00\x30\x00\x1a\x00\x1b\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x1a\x00\x1b\x00\x03\x00\x23\x00\x1a\x00\x1b\x00\x40\x00\x16\x00\x16\x00\x23\x00\x1a\x00\x1b\x00\x16\x00\x23\x00\x16\x00\x2f\x00\x30\x00\x16\x00\x42\x00\x23\x00\x42\x00\x2f\x00\x30\x00\x42\x00\x01\x00\x2f\x00\x30\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x2f\x00\x30\x00\x1a\x00\x1b\x00\x42\x00\x23\x00\x42\x00\x23\x00\x05\x00\x03\x00\x05\x00\x23\x00\x1a\x00\x1b\x00\x07\x00\x04\x00\x42\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x23\x00\x08\x00\x2f\x00\x30\x00\x2e\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x16\x00\x2f\x00\x30\x00\x23\x00\x2e\x00\x23\x00\x40\x00\x23\x00\x02\x00\x40\x00\x16\x00\x16\x00\x1a\x00\x1b\x00\x16\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x23\x00\x1a\x00\x1b\x00\x02\x00\x16\x00\x1a\x00\x1b\x00\x1a\x00\x1b\x00\x16\x00\x23\x00\x16\x00\x2f\x00\x30\x00\x23\x00\x16\x00\x23\x00\x16\x00\x03\x00\x40\x00\x40\x00\x02\x00\x2f\x00\x30\x00\x1a\x00\x1b\x00\x2f\x00\x30\x00\x2f\x00\x30\x00\x1a\x00\x1b\x00\x2c\x00\x23\x00\x1a\x00\x1b\x00\x40\x00\x40\x00\x40\x00\x23\x00\x1a\x00\x1b\x00\x40\x00\x23\x00\x40\x00\x2f\x00\x30\x00\x40\x00\x07\x00\x23\x00\x40\x00\x2f\x00\x30\x00\x07\x00\x07\x00\x2f\x00\x30\x00\x1a\x00\x1b\x00\x41\x00\x07\x00\x2f\x00\x30\x00\x07\x00\x07\x00\x07\x00\x23\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x16\x00\x2f\x00\x30\x00\x40\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x16\x00\x07\x00\xff\xff\x44\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\xff\xff\xff\xff\xff\xff\xff\xff\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\xff\xff\xff\xff\xff\xff\xff\xff\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\xff\xff\x1a\x00\x1b\x00\xff\xff\xff\xff\x2a\x00\x2b\x00\x2c\x00\x1a\x00\x1b\x00\x2f\x00\x30\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"#

happyTable :: HappyAddr
happyTable = HappyA# "\x00\x00\x6a\x00\x64\x01\x79\x00\x73\x00\x49\x00\x6b\x00\x7a\x00\xa6\x00\x7b\x01\x6c\x00\x2f\x00\x71\x01\x6d\x00\x6e\x00\xfd\x00\x66\x00\x6d\x01\xe7\x00\x48\x01\xff\x00\x00\x01\x47\x01\x66\x00\x67\x00\x79\x01\xab\x00\x6f\x01\x7f\x00\xd5\x00\x7b\x00\x67\x00\x60\x01\x80\x00\x7c\x00\xd6\x00\x68\x00\x09\x00\x62\x01\x7a\x01\xac\x00\x7d\x00\x09\x00\x68\x00\x09\x00\x2c\x00\x03\x00\x04\x00\x4a\x00\x4b\x00\x5a\x01\x05\x00\x06\x00\x30\x00\x07\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x6f\x00\x70\x00\x71\x00\x72\x00\x73\x00\x11\x00\xa7\x00\x72\x01\x81\x00\x82\x00\x83\x00\x84\xff\x6b\x00\x84\xff\x84\x00\x24\x00\x13\x00\x85\x00\xfa\x00\x6d\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x86\x00\x87\x00\xdf\x00\x08\x00\x09\x00\x3f\x01\x6c\x00\xfd\x00\x66\x00\x6d\x00\x6e\x00\x49\x01\xff\x00\x00\x01\x5d\x01\x6b\x00\x67\x00\x5f\x01\xe0\x00\x6c\x00\xfb\x00\xfc\x00\x6d\x00\x6e\x00\x45\x01\xb4\x00\x3e\x00\x3f\x00\x68\x00\x09\x00\x40\x00\x09\x00\x41\x01\x34\x01\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x6f\x00\x70\x00\x71\x00\x72\x00\x73\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x6f\x00\x70\x00\x71\x00\x72\x00\x73\x00\x42\x01\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x6f\x00\x70\x00\x71\x00\x72\x00\x73\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x48\x00\x49\x00\x33\x01\x34\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x02\x00\x03\x00\x04\x00\x28\x01\xe2\x00\xe3\x00\x05\x00\x06\x00\xf1\x00\x07\x00\x65\x01\x79\x00\x5c\x01\x79\x00\xfc\x00\x7a\x00\x19\x01\x7a\x00\x75\x00\x3f\x00\xc0\x00\x09\x00\x40\x00\x09\x00\x67\x00\x25\x01\x79\x00\xea\x00\x79\x00\xe9\x00\x7a\x00\xea\x00\x7a\x00\x22\x01\x4a\x00\x4b\x00\x68\x00\x09\x00\x7b\x00\x14\x01\x7b\x00\xba\x00\x7c\x00\xd8\x00\x7c\x00\x47\x00\x1e\x00\x08\x00\x09\x00\x7d\x00\x09\x00\x7d\x00\x09\x00\x7b\x00\x2a\x00\x7b\x00\x98\x00\x7c\x00\xd6\x00\x7c\x00\xe1\x00\xe2\x00\xe3\x00\xad\x00\x7d\x00\x09\x00\x7d\x00\x09\x00\xeb\x00\x79\x00\x78\x00\x79\x00\x9a\x00\x7a\x00\x42\x00\x7a\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x23\x01\xdc\x00\xaf\x00\x79\x00\x89\x00\x8a\x00\x8b\x00\x7a\x00\x50\x00\x93\x00\x94\x00\xdd\x00\x66\x00\x1d\x00\x1e\x00\x7b\x00\x58\x00\x7b\x00\x2d\x00\x7c\x00\x67\x00\x7c\x00\xfb\x00\xfc\x00\x24\x01\xdc\x00\x7d\x00\x09\x00\x7d\x00\x09\x00\x7b\x00\x22\x00\x68\x00\x09\x00\x7c\x00\xdd\x00\x66\x00\x41\x00\xf5\x00\xdc\x00\x1b\x00\x7d\x00\x09\x00\x2a\x00\x67\x00\x2b\x00\xe5\x00\xe6\x00\x7d\x01\xdd\x00\x66\x00\x72\x01\xf6\x00\xf7\x00\xdb\x00\xdc\x00\x68\x00\x09\x00\x67\x00\x20\x00\x21\x00\x75\x01\x76\x01\xf8\x00\x66\x00\xdd\x00\x66\x00\x7b\x01\x74\x01\x77\x01\x68\x00\x09\x00\x67\x00\x78\x01\x67\x00\x0b\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x6a\x01\x11\x00\x12\x00\x68\x00\x09\x00\x68\x00\x09\x00\x6c\x01\x6b\x01\x6d\x01\x6f\x01\x73\x01\x13\x00\x62\x01\x4d\x00\x64\x01\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x4e\x00\x1b\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x67\x01\x69\x01\x68\x01\x4d\x01\x4f\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x57\x01\x50\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x2b\x01\x58\x01\x59\x01\x5a\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\xa2\x00\x4b\x01\x5c\x01\x5f\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x41\x01\x1e\x01\x4c\x01\x4e\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x4f\x01\x50\x01\x52\x01\x51\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x2a\x01\x53\x01\x54\x01\x55\x01\x56\x01\x3c\x01\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x3d\x01\x36\x01\x3e\x01\x3f\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x09\x01\x41\x01\x44\x01\x45\x01\x47\x01\x2e\x01\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x30\x01\x31\x01\xfb\x00\x33\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x2f\x01\x36\x01\x37\x01\x1f\x01\x38\x01\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x16\x01\x39\x01\x3a\x01\x3b\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\xda\x00\x20\x01\x17\x01\x18\x01\x19\x01\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x1b\x01\x1d\x01\x21\x01\x23\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x88\x00\x28\x01\x27\x01\x2d\x01\xee\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\xf4\x00\xef\x00\xe5\x00\xf3\x00\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\xbf\x00\xf5\x00\x03\x01\x02\x01\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x06\x01\x0a\x01\x0b\x01\x0c\x01\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\xfd\x00\x66\x00\xfd\x00\x66\x00\xfe\x00\xff\x00\x00\x01\x31\x01\x00\x01\x67\x00\x0d\x01\x67\x00\x0e\x01\x0f\x01\x12\x01\x10\x01\x11\x01\x13\x01\xd1\x00\x66\x00\xb1\x00\x68\x00\x09\x00\x68\x00\x09\x00\x04\x01\xd3\x00\x67\x00\xd1\x00\x66\x00\x14\x01\xb3\x00\xb4\x00\xd1\x00\x66\x00\x07\x01\xd3\x00\x67\x00\xb6\x00\x68\x00\x09\x00\x1b\x01\x67\x00\xba\x00\xd1\x00\x66\x00\xb7\x00\x2b\x01\x66\x00\x68\x00\x09\x00\xd2\x00\xd3\x00\x67\x00\x68\x00\x09\x00\x67\x00\xc0\x00\xef\x00\x66\x00\xb9\x00\xf0\x00\x66\x00\x03\x01\x66\x00\x68\x00\x09\x00\x67\x00\x68\x00\x09\x00\x67\x00\xb8\x00\x67\x00\xbd\x00\xaf\x00\xbc\x00\xd8\x00\xb1\x00\x66\x00\x68\x00\x09\x00\xda\x00\x68\x00\x09\x00\x68\x00\x09\x00\x67\x00\xbd\x00\x66\x00\xe1\x00\xe8\x00\xc1\x00\x66\x00\xc2\x00\x66\x00\xed\x00\x67\x00\x9a\x00\x68\x00\x09\x00\x67\x00\xa0\x00\x67\x00\x9d\x00\xa3\x00\xa1\x00\xa4\x00\xa5\x00\x68\x00\x09\x00\xc3\x00\x66\x00\x68\x00\x09\x00\x68\x00\x09\x00\xc4\x00\x66\x00\x5a\x00\x67\x00\xc5\x00\x66\x00\x5b\x00\xa8\x00\xa9\x00\x67\x00\xc6\x00\x66\x00\xaa\x00\x67\x00\xad\x00\x68\x00\x09\x00\xaf\x00\x5c\x00\x67\x00\x5d\x00\x68\x00\x09\x00\x5e\x00\x61\x00\x68\x00\x09\x00\xc7\x00\x66\x00\xc8\x00\x66\x00\x68\x00\x09\x00\xc9\x00\x66\x00\x5f\x00\x67\x00\x60\x00\x67\x00\x62\x00\x78\x00\x65\x00\x67\x00\xca\x00\x66\x00\x64\x00\x75\x00\x63\x00\x68\x00\x09\x00\x68\x00\x09\x00\x67\x00\x47\x00\x68\x00\x09\x00\x44\x00\xcb\x00\x66\x00\xcc\x00\x66\x00\xcd\x00\x66\x00\x46\x00\x68\x00\x09\x00\x67\x00\x44\x00\x67\x00\x45\x00\x67\x00\x31\x00\x24\x00\x52\x00\x53\x00\xce\x00\x66\x00\x54\x00\x68\x00\x09\x00\x68\x00\x09\x00\x68\x00\x09\x00\x67\x00\xcf\x00\x66\x00\x39\x00\x55\x00\xd0\x00\x66\x00\xda\x00\x66\x00\x56\x00\x67\x00\x57\x00\x68\x00\x09\x00\x67\x00\x38\x00\x67\x00\x3c\x00\x3a\x00\x58\x00\x32\x00\x3d\x00\x68\x00\x09\x00\x9b\x00\x66\x00\x68\x00\x09\x00\x68\x00\x09\x00\x9d\x00\x66\x00\x30\x00\x67\x00\x9e\x00\x66\x00\x33\x00\x34\x00\x35\x00\x67\x00\x65\x00\x66\x00\x36\x00\x67\x00\x37\x00\x68\x00\x09\x00\x3b\x00\x1d\x00\x67\x00\x24\x00\x68\x00\x09\x00\x25\x00\x26\x00\x68\x00\x09\x00\x76\x00\x66\x00\x22\x00\x27\x00\x68\x00\x09\x00\x28\x00\x29\x00\x2a\x00\x67\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x07\x01\x68\x00\x09\x00\x24\x00\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\xaf\x00\x1d\x00\x00\x00\xff\xff\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x00\x00\x00\x00\x00\x00\x00\x00\x93\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x93\x00\x94\x00\x00\x00\x00\x00\x00\x00\x00\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x89\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x00\x00\x93\x00\x94\x00\x00\x00\x00\x00\x3d\x00\x3e\x00\x3f\x00\x93\x00\x94\x00\x40\x00\x09\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"#

happyReduceArr = Happy_Data_Array.array (1, 152) [
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
	(46 , happyReduce_46),
	(47 , happyReduce_47),
	(48 , happyReduce_48),
	(49 , happyReduce_49),
	(50 , happyReduce_50),
	(51 , happyReduce_51),
	(52 , happyReduce_52),
	(53 , happyReduce_53),
	(54 , happyReduce_54),
	(55 , happyReduce_55),
	(56 , happyReduce_56),
	(57 , happyReduce_57),
	(58 , happyReduce_58),
	(59 , happyReduce_59),
	(60 , happyReduce_60),
	(61 , happyReduce_61),
	(62 , happyReduce_62),
	(63 , happyReduce_63),
	(64 , happyReduce_64),
	(65 , happyReduce_65),
	(66 , happyReduce_66),
	(67 , happyReduce_67),
	(68 , happyReduce_68),
	(69 , happyReduce_69),
	(70 , happyReduce_70),
	(71 , happyReduce_71),
	(72 , happyReduce_72),
	(73 , happyReduce_73),
	(74 , happyReduce_74),
	(75 , happyReduce_75),
	(76 , happyReduce_76),
	(77 , happyReduce_77),
	(78 , happyReduce_78),
	(79 , happyReduce_79),
	(80 , happyReduce_80),
	(81 , happyReduce_81),
	(82 , happyReduce_82),
	(83 , happyReduce_83),
	(84 , happyReduce_84),
	(85 , happyReduce_85),
	(86 , happyReduce_86),
	(87 , happyReduce_87),
	(88 , happyReduce_88),
	(89 , happyReduce_89),
	(90 , happyReduce_90),
	(91 , happyReduce_91),
	(92 , happyReduce_92),
	(93 , happyReduce_93),
	(94 , happyReduce_94),
	(95 , happyReduce_95),
	(96 , happyReduce_96),
	(97 , happyReduce_97),
	(98 , happyReduce_98),
	(99 , happyReduce_99),
	(100 , happyReduce_100),
	(101 , happyReduce_101),
	(102 , happyReduce_102),
	(103 , happyReduce_103),
	(104 , happyReduce_104),
	(105 , happyReduce_105),
	(106 , happyReduce_106),
	(107 , happyReduce_107),
	(108 , happyReduce_108),
	(109 , happyReduce_109),
	(110 , happyReduce_110),
	(111 , happyReduce_111),
	(112 , happyReduce_112),
	(113 , happyReduce_113),
	(114 , happyReduce_114),
	(115 , happyReduce_115),
	(116 , happyReduce_116),
	(117 , happyReduce_117),
	(118 , happyReduce_118),
	(119 , happyReduce_119),
	(120 , happyReduce_120),
	(121 , happyReduce_121),
	(122 , happyReduce_122),
	(123 , happyReduce_123),
	(124 , happyReduce_124),
	(125 , happyReduce_125),
	(126 , happyReduce_126),
	(127 , happyReduce_127),
	(128 , happyReduce_128),
	(129 , happyReduce_129),
	(130 , happyReduce_130),
	(131 , happyReduce_131),
	(132 , happyReduce_132),
	(133 , happyReduce_133),
	(134 , happyReduce_134),
	(135 , happyReduce_135),
	(136 , happyReduce_136),
	(137 , happyReduce_137),
	(138 , happyReduce_138),
	(139 , happyReduce_139),
	(140 , happyReduce_140),
	(141 , happyReduce_141),
	(142 , happyReduce_142),
	(143 , happyReduce_143),
	(144 , happyReduce_144),
	(145 , happyReduce_145),
	(146 , happyReduce_146),
	(147 , happyReduce_147),
	(148 , happyReduce_148),
	(149 , happyReduce_149),
	(150 , happyReduce_150),
	(151 , happyReduce_151),
	(152 , happyReduce_152)
	]

happy_n_terms = 69 :: Int
happy_n_nonterms = 49 :: Int

happyReduce_1 = happySpecReduce_0  0# happyReduction_1
happyReduction_1  =  happyIn4
		 (return ()
	)

happyReduce_2 = happySpecReduce_2  0# happyReduction_2
happyReduction_2 happy_x_2
	happy_x_1
	 =  case happyOut5 happy_x_1 of { happy_var_1 -> 
	case happyOut4 happy_x_2 of { happy_var_2 -> 
	happyIn4
		 (do happy_var_1; happy_var_2
	)}}

happyReduce_3 = happySpecReduce_1  1# happyReduction_3
happyReduction_3 happy_x_1
	 =  case happyOut10 happy_x_1 of { happy_var_1 -> 
	happyIn5
		 (happy_var_1
	)}

happyReduce_4 = happySpecReduce_1  1# happyReduction_4
happyReduction_4 happy_x_1
	 =  case happyOut6 happy_x_1 of { happy_var_1 -> 
	happyIn5
		 (happy_var_1
	)}

happyReduce_5 = happySpecReduce_1  1# happyReduction_5
happyReduction_5 happy_x_1
	 =  case happyOut13 happy_x_1 of { happy_var_1 -> 
	happyIn5
		 (happy_var_1
	)}

happyReduce_6 = happyMonadReduce 8# 1# happyReduction_6
happyReduction_6 (happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Name	happy_var_5)) -> 
	case happyOut9 happy_x_6 of { happy_var_6 -> 
	( withThisPackage $ \pkg -> 
		   do lits <- sequence happy_var_6;
		      staticClosure pkg happy_var_3 happy_var_5 (map getLit lits))}}}
	) (\r -> happyReturn (happyIn5 r))

happyReduce_7 = happyReduce 5# 2# happyReduction_7
happyReduction_7 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_2 of { (L _ (CmmT_String	happy_var_2)) -> 
	case happyOut7 happy_x_4 of { happy_var_4 -> 
	happyIn6
		 (do ss <- sequence happy_var_4;
		     code (emitData (section happy_var_2) (concat ss))
	) `HappyStk` happyRest}}

happyReduce_8 = happySpecReduce_0  3# happyReduction_8
happyReduction_8  =  happyIn7
		 ([]
	)

happyReduce_9 = happySpecReduce_2  3# happyReduction_9
happyReduction_9 happy_x_2
	happy_x_1
	 =  case happyOut8 happy_x_1 of { happy_var_1 -> 
	case happyOut7 happy_x_2 of { happy_var_2 -> 
	happyIn7
		 (happy_var_1 : happy_var_2
	)}}

happyReduce_10 = happyMonadReduce 2# 4# happyReduction_10
happyReduction_10 (happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	( withThisPackage $ \pkg -> 
		   return [CmmDataLabel (mkCmmDataLabel pkg happy_var_1)])}
	) (\r -> happyReturn (happyIn8 r))

happyReduce_11 = happySpecReduce_3  4# happyReduction_11
happyReduction_11 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_2 of { happy_var_2 -> 
	happyIn8
		 (do e <- happy_var_2;
			     return [CmmStaticLit (getLit e)]
	)}

happyReduce_12 = happySpecReduce_2  4# happyReduction_12
happyReduction_12 happy_x_2
	happy_x_1
	 =  case happyOut51 happy_x_1 of { happy_var_1 -> 
	happyIn8
		 (return [CmmUninitialised
							(widthInBytes (typeWidth happy_var_1))]
	)}

happyReduce_13 = happyReduce 5# 4# happyReduction_13
happyReduction_13 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_4 of { (L _ (CmmT_String	happy_var_4)) -> 
	happyIn8
		 (return [mkString happy_var_4]
	) `HappyStk` happyRest}

happyReduce_14 = happyReduce 5# 4# happyReduction_14
happyReduction_14 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_3 of { (L _ (CmmT_Int		happy_var_3)) -> 
	happyIn8
		 (return [CmmUninitialised 
							(fromIntegral happy_var_3)]
	) `HappyStk` happyRest}

happyReduce_15 = happyReduce 5# 4# happyReduction_15
happyReduction_15 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut52 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_3 of { (L _ (CmmT_Int		happy_var_3)) -> 
	happyIn8
		 (return [CmmUninitialised 
						(widthInBytes (typeWidth happy_var_1) * 
							fromIntegral happy_var_3)]
	) `HappyStk` happyRest}}

happyReduce_16 = happySpecReduce_3  4# happyReduction_16
happyReduction_16 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_2 of { (L _ (CmmT_Int		happy_var_2)) -> 
	happyIn8
		 (return [CmmAlign (fromIntegral happy_var_2)]
	)}

happyReduce_17 = happyReduce 5# 4# happyReduction_17
happyReduction_17 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOut9 happy_x_4 of { happy_var_4 -> 
	happyIn8
		 (do lits <- sequence happy_var_4;
		     return $ map CmmStaticLit $
                       mkStaticClosure (mkForeignLabel happy_var_3 Nothing ForeignLabelInExternalPackage IsData)
                         -- mkForeignLabel because these are only used
                         -- for CHARLIKE and INTLIKE closures in the RTS.
			 dontCareCCS (map getLit lits) [] [] []
	) `HappyStk` happyRest}}

happyReduce_18 = happySpecReduce_0  5# happyReduction_18
happyReduction_18  =  happyIn9
		 ([]
	)

happyReduce_19 = happySpecReduce_3  5# happyReduction_19
happyReduction_19 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_2 of { happy_var_2 -> 
	case happyOut9 happy_x_3 of { happy_var_3 -> 
	happyIn9
		 (happy_var_2 : happy_var_3
	)}}

happyReduce_20 = happyReduce 7# 6# happyReduction_20
happyReduction_20 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut11 happy_x_1 of { happy_var_1 -> 
	case happyOut45 happy_x_2 of { happy_var_2 -> 
	case happyOut50 happy_x_3 of { happy_var_3 -> 
	case happyOut49 happy_x_4 of { happy_var_4 -> 
	case happyOut12 happy_x_6 of { happy_var_6 -> 
	happyIn10
		 (do ((entry_ret_label, info, live, formals, gc_block, frame), stmts) <-
		       getCgStmtsEC' $ loopDecls $ do {
		         (entry_ret_label, info, live) <- happy_var_1;
		         formals <- sequence happy_var_2;
		         gc_block <- happy_var_3;
		         frame <- happy_var_4;
		         happy_var_6;
		         return (entry_ret_label, info, live, formals, gc_block, frame) }
		     blks <- code (cgStmtsToBlocks stmts)
		     code (emitInfoTableAndCode entry_ret_label (CmmInfo gc_block frame info) formals blks)
	) `HappyStk` happyRest}}}}}

happyReduce_21 = happySpecReduce_3  6# happyReduction_21
happyReduction_21 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut11 happy_x_1 of { happy_var_1 -> 
	case happyOut45 happy_x_2 of { happy_var_2 -> 
	happyIn10
		 (do (entry_ret_label, info, live) <- happy_var_1;
		     formals <- sequence happy_var_2;
		     code (emitInfoTableAndCode entry_ret_label (CmmInfo Nothing Nothing info) formals [])
	)}}

happyReduce_22 = happyMonadReduce 7# 6# happyReduction_22
happyReduction_22 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	case happyOut45 happy_x_2 of { happy_var_2 -> 
	case happyOut50 happy_x_3 of { happy_var_3 -> 
	case happyOut49 happy_x_4 of { happy_var_4 -> 
	case happyOut12 happy_x_6 of { happy_var_6 -> 
	( withThisPackage $ \pkg ->
		   do	newFunctionName happy_var_1 pkg
		   	((formals, gc_block, frame), stmts) <-
			 	getCgStmtsEC' $ loopDecls $ do {
		          		formals <- sequence happy_var_2;
		          		gc_block <- happy_var_3;
			  		frame <- happy_var_4;
		          		happy_var_6;
		          		return (formals, gc_block, frame) }
			blks <- code (cgStmtsToBlocks stmts)
			code (emitProc (CmmInfo gc_block frame CmmNonInfoTable) (mkCmmCodeLabel pkg happy_var_1) formals blks))}}}}}
	) (\r -> happyReturn (happyIn10 r))

happyReduce_23 = happyMonadReduce 14# 7# happyReduction_23
happyReduction_23 (happy_x_14 `HappyStk`
	happy_x_13 `HappyStk`
	happy_x_12 `HappyStk`
	happy_x_11 `HappyStk`
	happy_x_10 `HappyStk`
	happy_x_9 `HappyStk`
	happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Int		happy_var_5)) -> 
	case happyOutTok happy_x_7 of { (L _ (CmmT_Int		happy_var_7)) -> 
	case happyOutTok happy_x_9 of { (L _ (CmmT_Int		happy_var_9)) -> 
	case happyOutTok happy_x_11 of { (L _ (CmmT_String	happy_var_11)) -> 
	case happyOutTok happy_x_13 of { (L _ (CmmT_String	happy_var_13)) -> 
	( withThisPackage $ \pkg ->
		   do prof <- profilingInfo happy_var_11 happy_var_13
		      return (mkCmmEntryLabel pkg happy_var_3,
			CmmInfoTable False prof (fromIntegral happy_var_9)
				     (ThunkInfo (fromIntegral happy_var_5, fromIntegral happy_var_7) NoC_SRT),
			[]))}}}}}}
	) (\r -> happyReturn (happyIn11 r))

happyReduce_24 = happyMonadReduce 16# 7# happyReduction_24
happyReduction_24 (happy_x_16 `HappyStk`
	happy_x_15 `HappyStk`
	happy_x_14 `HappyStk`
	happy_x_13 `HappyStk`
	happy_x_12 `HappyStk`
	happy_x_11 `HappyStk`
	happy_x_10 `HappyStk`
	happy_x_9 `HappyStk`
	happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Int		happy_var_5)) -> 
	case happyOutTok happy_x_7 of { (L _ (CmmT_Int		happy_var_7)) -> 
	case happyOutTok happy_x_9 of { (L _ (CmmT_Int		happy_var_9)) -> 
	case happyOutTok happy_x_11 of { (L _ (CmmT_String	happy_var_11)) -> 
	case happyOutTok happy_x_13 of { (L _ (CmmT_String	happy_var_13)) -> 
	case happyOutTok happy_x_15 of { (L _ (CmmT_Int		happy_var_15)) -> 
	( withThisPackage $ \pkg -> 
		   do prof <- profilingInfo happy_var_11 happy_var_13
		      return (mkCmmEntryLabel pkg happy_var_3,
			CmmInfoTable False prof (fromIntegral happy_var_9)
				     (FunInfo (fromIntegral happy_var_5, fromIntegral happy_var_7) NoC_SRT
				      0  -- Arity zero
				      (ArgSpec (fromIntegral happy_var_15))
				      zeroCLit),
			[]))}}}}}}}
	) (\r -> happyReturn (happyIn11 r))

happyReduce_25 = happyMonadReduce 18# 7# happyReduction_25
happyReduction_25 (happy_x_18 `HappyStk`
	happy_x_17 `HappyStk`
	happy_x_16 `HappyStk`
	happy_x_15 `HappyStk`
	happy_x_14 `HappyStk`
	happy_x_13 `HappyStk`
	happy_x_12 `HappyStk`
	happy_x_11 `HappyStk`
	happy_x_10 `HappyStk`
	happy_x_9 `HappyStk`
	happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Int		happy_var_5)) -> 
	case happyOutTok happy_x_7 of { (L _ (CmmT_Int		happy_var_7)) -> 
	case happyOutTok happy_x_9 of { (L _ (CmmT_Int		happy_var_9)) -> 
	case happyOutTok happy_x_11 of { (L _ (CmmT_String	happy_var_11)) -> 
	case happyOutTok happy_x_13 of { (L _ (CmmT_String	happy_var_13)) -> 
	case happyOutTok happy_x_15 of { (L _ (CmmT_Int		happy_var_15)) -> 
	case happyOutTok happy_x_17 of { (L _ (CmmT_Int		happy_var_17)) -> 
	( withThisPackage $ \pkg ->
		   do prof <- profilingInfo happy_var_11 happy_var_13
		      return (mkCmmEntryLabel pkg happy_var_3,
			CmmInfoTable False prof (fromIntegral happy_var_9)
				     (FunInfo (fromIntegral happy_var_5, fromIntegral happy_var_7) NoC_SRT (fromIntegral happy_var_17)
				      (ArgSpec (fromIntegral happy_var_15))
				      zeroCLit),
			[]))}}}}}}}}
	) (\r -> happyReturn (happyIn11 r))

happyReduce_26 = happyMonadReduce 16# 7# happyReduction_26
happyReduction_26 (happy_x_16 `HappyStk`
	happy_x_15 `HappyStk`
	happy_x_14 `HappyStk`
	happy_x_13 `HappyStk`
	happy_x_12 `HappyStk`
	happy_x_11 `HappyStk`
	happy_x_10 `HappyStk`
	happy_x_9 `HappyStk`
	happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Int		happy_var_5)) -> 
	case happyOutTok happy_x_7 of { (L _ (CmmT_Int		happy_var_7)) -> 
	case happyOutTok happy_x_9 of { (L _ (CmmT_Int		happy_var_9)) -> 
	case happyOutTok happy_x_11 of { (L _ (CmmT_Int		happy_var_11)) -> 
	case happyOutTok happy_x_13 of { (L _ (CmmT_String	happy_var_13)) -> 
	case happyOutTok happy_x_15 of { (L _ (CmmT_String	happy_var_15)) -> 
	( withThisPackage $ \pkg ->
		   do prof <- profilingInfo happy_var_13 happy_var_15
		     -- If profiling is on, this string gets duplicated,
		     -- but that's the way the old code did it we can fix it some other time.
		      desc_lit <- code $ mkStringCLit happy_var_13
		      return (mkCmmEntryLabel pkg happy_var_3,
			CmmInfoTable False prof (fromIntegral happy_var_11)
				     (ConstrInfo (fromIntegral happy_var_5, fromIntegral happy_var_7) (fromIntegral happy_var_9) desc_lit),
			[]))}}}}}}}
	) (\r -> happyReturn (happyIn11 r))

happyReduce_27 = happyMonadReduce 12# 7# happyReduction_27
happyReduction_27 (happy_x_12 `HappyStk`
	happy_x_11 `HappyStk`
	happy_x_10 `HappyStk`
	happy_x_9 `HappyStk`
	happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Int		happy_var_5)) -> 
	case happyOutTok happy_x_7 of { (L _ (CmmT_Int		happy_var_7)) -> 
	case happyOutTok happy_x_9 of { (L _ (CmmT_String	happy_var_9)) -> 
	case happyOutTok happy_x_11 of { (L _ (CmmT_String	happy_var_11)) -> 
	( withThisPackage $ \pkg ->
		   do prof <- profilingInfo happy_var_9 happy_var_11
		      return (mkCmmEntryLabel pkg happy_var_3,
			CmmInfoTable False prof (fromIntegral happy_var_7)
				     (ThunkSelectorInfo (fromIntegral happy_var_5) NoC_SRT),
			[]))}}}}}
	) (\r -> happyReturn (happyIn11 r))

happyReduce_28 = happyMonadReduce 6# 7# happyReduction_28
happyReduction_28 (happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Int		happy_var_5)) -> 
	( withThisPackage $ \pkg ->
		   do let infoLabel = mkCmmInfoLabel pkg happy_var_3
		      return (mkCmmRetLabel pkg happy_var_3,
			CmmInfoTable False (ProfilingInfo zeroCLit zeroCLit) (fromIntegral happy_var_5)
				     (ContInfo [] NoC_SRT),
			[]))}}
	) (\r -> happyReturn (happyIn11 r))

happyReduce_29 = happyMonadReduce 8# 7# happyReduction_29
happyReduction_29 (happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Int		happy_var_5)) -> 
	case happyOut46 happy_x_7 of { happy_var_7 -> 
	( withThisPackage $ \pkg ->
		   do live <- sequence (map (liftM Just) happy_var_7)
		      return (mkCmmRetLabel pkg happy_var_3,
			CmmInfoTable False (ProfilingInfo zeroCLit zeroCLit) (fromIntegral happy_var_5)
			             (ContInfo live NoC_SRT),
			live))}}}
	) (\r -> happyReturn (happyIn11 r))

happyReduce_30 = happySpecReduce_0  8# happyReduction_30
happyReduction_30  =  happyIn12
		 (return ()
	)

happyReduce_31 = happySpecReduce_2  8# happyReduction_31
happyReduction_31 happy_x_2
	happy_x_1
	 =  case happyOut13 happy_x_1 of { happy_var_1 -> 
	case happyOut12 happy_x_2 of { happy_var_2 -> 
	happyIn12
		 (do happy_var_1; happy_var_2
	)}}

happyReduce_32 = happySpecReduce_2  8# happyReduction_32
happyReduction_32 happy_x_2
	happy_x_1
	 =  case happyOut17 happy_x_1 of { happy_var_1 -> 
	case happyOut12 happy_x_2 of { happy_var_2 -> 
	happyIn12
		 (do happy_var_1; happy_var_2
	)}}

happyReduce_33 = happySpecReduce_3  9# happyReduction_33
happyReduction_33 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut51 happy_x_1 of { happy_var_1 -> 
	case happyOut16 happy_x_2 of { happy_var_2 -> 
	happyIn13
		 (mapM_ (newLocal happy_var_1) happy_var_2
	)}}

happyReduce_34 = happySpecReduce_3  9# happyReduction_34
happyReduction_34 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut14 happy_x_2 of { happy_var_2 -> 
	happyIn13
		 (mapM_ newImport happy_var_2
	)}

happyReduce_35 = happySpecReduce_3  9# happyReduction_35
happyReduction_35 happy_x_3
	happy_x_2
	happy_x_1
	 =  happyIn13
		 (return ()
	)

happyReduce_36 = happySpecReduce_1  10# happyReduction_36
happyReduction_36 happy_x_1
	 =  case happyOut15 happy_x_1 of { happy_var_1 -> 
	happyIn14
		 ([happy_var_1]
	)}

happyReduce_37 = happySpecReduce_3  10# happyReduction_37
happyReduction_37 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut15 happy_x_1 of { happy_var_1 -> 
	case happyOut14 happy_x_3 of { happy_var_3 -> 
	happyIn14
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_38 = happySpecReduce_1  11# happyReduction_38
happyReduction_38 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn15
		 ((happy_var_1, mkForeignLabel happy_var_1 Nothing ForeignLabelInExternalPackage IsFunction)
	)}

happyReduce_39 = happySpecReduce_2  11# happyReduction_39
happyReduction_39 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_String	happy_var_1)) -> 
	case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn15
		 ((happy_var_2, mkCmmCodeLabel (fsToPackageId (mkFastString happy_var_1)) happy_var_2)
	)}}

happyReduce_40 = happySpecReduce_1  12# happyReduction_40
happyReduction_40 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn16
		 ([happy_var_1]
	)}

happyReduce_41 = happySpecReduce_3  12# happyReduction_41
happyReduction_41 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	case happyOut16 happy_x_3 of { happy_var_3 -> 
	happyIn16
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_42 = happySpecReduce_1  13# happyReduction_42
happyReduction_42 happy_x_1
	 =  happyIn17
		 (nopEC
	)

happyReduce_43 = happySpecReduce_2  13# happyReduction_43
happyReduction_43 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn17
		 (do l <- newLabel happy_var_1; code (labelC l)
	)}

happyReduce_44 = happyReduce 4# 13# happyReduction_44
happyReduction_44 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut44 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn17
		 (do reg <- happy_var_1; e <- happy_var_3; stmtEC (CmmAssign reg e)
	) `HappyStk` happyRest}}

happyReduce_45 = happyReduce 7# 13# happyReduction_45
happyReduction_45 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut51 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	case happyOut30 happy_x_6 of { happy_var_6 -> 
	happyIn17
		 (doStore happy_var_1 happy_var_3 happy_var_6
	) `HappyStk` happyRest}}}

happyReduce_46 = happyMonadReduce 11# 13# happyReduction_46
happyReduction_46 (happy_x_11 `HappyStk`
	happy_x_10 `HappyStk`
	happy_x_9 `HappyStk`
	happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOut40 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_3 of { (L _ (CmmT_String	happy_var_3)) -> 
	case happyOut30 happy_x_4 of { happy_var_4 -> 
	case happyOut34 happy_x_6 of { happy_var_6 -> 
	case happyOut21 happy_x_8 of { happy_var_8 -> 
	case happyOut22 happy_x_9 of { happy_var_9 -> 
	case happyOut18 happy_x_10 of { happy_var_10 -> 
	( foreignCall happy_var_3 happy_var_1 happy_var_4 happy_var_6 happy_var_9 happy_var_8 happy_var_10)}}}}}}}
	) (\r -> happyReturn (happyIn17 r))

happyReduce_47 = happyMonadReduce 10# 13# happyReduction_47
happyReduction_47 (happy_x_10 `HappyStk`
	happy_x_9 `HappyStk`
	happy_x_8 `HappyStk`
	happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOut40 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_4 of { (L _ (CmmT_Name	happy_var_4)) -> 
	case happyOut34 happy_x_6 of { happy_var_6 -> 
	case happyOut21 happy_x_8 of { happy_var_8 -> 
	case happyOut22 happy_x_9 of { happy_var_9 -> 
	( primCall happy_var_1 happy_var_4 happy_var_6 happy_var_9 happy_var_8)}}}}}
	) (\r -> happyReturn (happyIn17 r))

happyReduce_48 = happyMonadReduce 5# 13# happyReduction_48
happyReduction_48 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	case happyOut37 happy_x_3 of { happy_var_3 -> 
	( stmtMacro happy_var_1 happy_var_3)}}
	) (\r -> happyReturn (happyIn17 r))

happyReduce_49 = happyReduce 7# 13# happyReduction_49
happyReduction_49 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut24 happy_x_2 of { happy_var_2 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	case happyOut25 happy_x_5 of { happy_var_5 -> 
	case happyOut28 happy_x_6 of { happy_var_6 -> 
	happyIn17
		 (doSwitch happy_var_2 happy_var_3 happy_var_5 happy_var_6
	) `HappyStk` happyRest}}}}

happyReduce_50 = happySpecReduce_3  13# happyReduction_50
happyReduction_50 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn17
		 (do l <- lookupLabel happy_var_2; stmtEC (CmmBranch l)
	)}

happyReduce_51 = happyReduce 4# 13# happyReduction_51
happyReduction_51 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut30 happy_x_2 of { happy_var_2 -> 
	case happyOut33 happy_x_3 of { happy_var_3 -> 
	happyIn17
		 (do e1 <- happy_var_2; e2 <- sequence happy_var_3; stmtEC (CmmJump e1 e2)
	) `HappyStk` happyRest}}

happyReduce_52 = happySpecReduce_3  13# happyReduction_52
happyReduction_52 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut33 happy_x_2 of { happy_var_2 -> 
	happyIn17
		 (do e <- sequence happy_var_2; stmtEC (CmmReturn e)
	)}

happyReduce_53 = happyReduce 6# 13# happyReduction_53
happyReduction_53 (happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut19 happy_x_2 of { happy_var_2 -> 
	case happyOut12 happy_x_4 of { happy_var_4 -> 
	case happyOut29 happy_x_6 of { happy_var_6 -> 
	happyIn17
		 (cmmIfThenElse happy_var_2 happy_var_4 happy_var_6
	) `HappyStk` happyRest}}}

happyReduce_54 = happySpecReduce_0  14# happyReduction_54
happyReduction_54  =  happyIn18
		 (CmmMayReturn
	)

happyReduce_55 = happySpecReduce_2  14# happyReduction_55
happyReduction_55 happy_x_2
	happy_x_1
	 =  happyIn18
		 (CmmNeverReturns
	)

happyReduce_56 = happySpecReduce_1  15# happyReduction_56
happyReduction_56 happy_x_1
	 =  case happyOut20 happy_x_1 of { happy_var_1 -> 
	happyIn19
		 (happy_var_1
	)}

happyReduce_57 = happySpecReduce_1  15# happyReduction_57
happyReduction_57 happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	happyIn19
		 (do e <- happy_var_1; return (BoolTest e)
	)}

happyReduce_58 = happySpecReduce_3  16# happyReduction_58
happyReduction_58 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut19 happy_x_1 of { happy_var_1 -> 
	case happyOut19 happy_x_3 of { happy_var_3 -> 
	happyIn20
		 (do e1 <- happy_var_1; e2 <- happy_var_3; 
					  return (BoolAnd e1 e2)
	)}}

happyReduce_59 = happySpecReduce_3  16# happyReduction_59
happyReduction_59 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut19 happy_x_1 of { happy_var_1 -> 
	case happyOut19 happy_x_3 of { happy_var_3 -> 
	happyIn20
		 (do e1 <- happy_var_1; e2 <- happy_var_3; 
					  return (BoolOr e1 e2)
	)}}

happyReduce_60 = happySpecReduce_2  16# happyReduction_60
happyReduction_60 happy_x_2
	happy_x_1
	 =  case happyOut19 happy_x_2 of { happy_var_2 -> 
	happyIn20
		 (do e <- happy_var_2; return (BoolNot e)
	)}

happyReduce_61 = happySpecReduce_3  16# happyReduction_61
happyReduction_61 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut20 happy_x_2 of { happy_var_2 -> 
	happyIn20
		 (happy_var_2
	)}

happyReduce_62 = happySpecReduce_0  17# happyReduction_62
happyReduction_62  =  happyIn21
		 (CmmUnsafe
	)

happyReduce_63 = happyMonadReduce 1# 17# happyReduction_63
happyReduction_63 (happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_String	happy_var_1)) -> 
	( parseSafety happy_var_1)}
	) (\r -> happyReturn (happyIn21 r))

happyReduce_64 = happySpecReduce_0  18# happyReduction_64
happyReduction_64  =  happyIn22
		 (Nothing
	)

happyReduce_65 = happySpecReduce_2  18# happyReduction_65
happyReduction_65 happy_x_2
	happy_x_1
	 =  happyIn22
		 (Just []
	)

happyReduce_66 = happySpecReduce_3  18# happyReduction_66
happyReduction_66 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut23 happy_x_2 of { happy_var_2 -> 
	happyIn22
		 (Just happy_var_2
	)}

happyReduce_67 = happySpecReduce_1  19# happyReduction_67
happyReduction_67 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_GlobalReg   happy_var_1)) -> 
	happyIn23
		 ([happy_var_1]
	)}

happyReduce_68 = happySpecReduce_3  19# happyReduction_68
happyReduction_68 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_GlobalReg   happy_var_1)) -> 
	case happyOut23 happy_x_3 of { happy_var_3 -> 
	happyIn23
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_69 = happyReduce 5# 20# happyReduction_69
happyReduction_69 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_2 of { (L _ (CmmT_Int		happy_var_2)) -> 
	case happyOutTok happy_x_4 of { (L _ (CmmT_Int		happy_var_4)) -> 
	happyIn24
		 (Just (fromIntegral happy_var_2, fromIntegral happy_var_4)
	) `HappyStk` happyRest}}

happyReduce_70 = happySpecReduce_0  20# happyReduction_70
happyReduction_70  =  happyIn24
		 (Nothing
	)

happyReduce_71 = happySpecReduce_0  21# happyReduction_71
happyReduction_71  =  happyIn25
		 ([]
	)

happyReduce_72 = happySpecReduce_2  21# happyReduction_72
happyReduction_72 happy_x_2
	happy_x_1
	 =  case happyOut26 happy_x_1 of { happy_var_1 -> 
	case happyOut25 happy_x_2 of { happy_var_2 -> 
	happyIn25
		 (happy_var_1 : happy_var_2
	)}}

happyReduce_73 = happyReduce 6# 22# happyReduction_73
happyReduction_73 (happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut27 happy_x_2 of { happy_var_2 -> 
	case happyOut12 happy_x_5 of { happy_var_5 -> 
	happyIn26
		 ((happy_var_2, happy_var_5)
	) `HappyStk` happyRest}}

happyReduce_74 = happySpecReduce_1  23# happyReduction_74
happyReduction_74 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Int		happy_var_1)) -> 
	happyIn27
		 ([ fromIntegral happy_var_1 ]
	)}

happyReduce_75 = happySpecReduce_3  23# happyReduction_75
happyReduction_75 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Int		happy_var_1)) -> 
	case happyOut27 happy_x_3 of { happy_var_3 -> 
	happyIn27
		 (fromIntegral happy_var_1 : happy_var_3
	)}}

happyReduce_76 = happyReduce 5# 24# happyReduction_76
happyReduction_76 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut12 happy_x_4 of { happy_var_4 -> 
	happyIn28
		 (Just happy_var_4
	) `HappyStk` happyRest}

happyReduce_77 = happySpecReduce_0  24# happyReduction_77
happyReduction_77  =  happyIn28
		 (Nothing
	)

happyReduce_78 = happySpecReduce_0  25# happyReduction_78
happyReduction_78  =  happyIn29
		 (nopEC
	)

happyReduce_79 = happyReduce 4# 25# happyReduction_79
happyReduction_79 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut12 happy_x_3 of { happy_var_3 -> 
	happyIn29
		 (happy_var_3
	) `HappyStk` happyRest}

happyReduce_80 = happySpecReduce_3  26# happyReduction_80
happyReduction_80 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_U_Quot [happy_var_1,happy_var_3]
	)}}

happyReduce_81 = happySpecReduce_3  26# happyReduction_81
happyReduction_81 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_Mul [happy_var_1,happy_var_3]
	)}}

happyReduce_82 = happySpecReduce_3  26# happyReduction_82
happyReduction_82 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_U_Rem [happy_var_1,happy_var_3]
	)}}

happyReduce_83 = happySpecReduce_3  26# happyReduction_83
happyReduction_83 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_Sub [happy_var_1,happy_var_3]
	)}}

happyReduce_84 = happySpecReduce_3  26# happyReduction_84
happyReduction_84 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_Add [happy_var_1,happy_var_3]
	)}}

happyReduce_85 = happySpecReduce_3  26# happyReduction_85
happyReduction_85 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_U_Shr [happy_var_1,happy_var_3]
	)}}

happyReduce_86 = happySpecReduce_3  26# happyReduction_86
happyReduction_86 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_Shl [happy_var_1,happy_var_3]
	)}}

happyReduce_87 = happySpecReduce_3  26# happyReduction_87
happyReduction_87 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_And [happy_var_1,happy_var_3]
	)}}

happyReduce_88 = happySpecReduce_3  26# happyReduction_88
happyReduction_88 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_Xor [happy_var_1,happy_var_3]
	)}}

happyReduce_89 = happySpecReduce_3  26# happyReduction_89
happyReduction_89 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_Or [happy_var_1,happy_var_3]
	)}}

happyReduce_90 = happySpecReduce_3  26# happyReduction_90
happyReduction_90 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_U_Ge [happy_var_1,happy_var_3]
	)}}

happyReduce_91 = happySpecReduce_3  26# happyReduction_91
happyReduction_91 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_U_Gt [happy_var_1,happy_var_3]
	)}}

happyReduce_92 = happySpecReduce_3  26# happyReduction_92
happyReduction_92 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_U_Le [happy_var_1,happy_var_3]
	)}}

happyReduce_93 = happySpecReduce_3  26# happyReduction_93
happyReduction_93 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_U_Lt [happy_var_1,happy_var_3]
	)}}

happyReduce_94 = happySpecReduce_3  26# happyReduction_94
happyReduction_94 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_Ne [happy_var_1,happy_var_3]
	)}}

happyReduce_95 = happySpecReduce_3  26# happyReduction_95
happyReduction_95 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn30
		 (mkMachOp MO_Eq [happy_var_1,happy_var_3]
	)}}

happyReduce_96 = happySpecReduce_2  26# happyReduction_96
happyReduction_96 happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_2 of { happy_var_2 -> 
	happyIn30
		 (mkMachOp MO_Not [happy_var_2]
	)}

happyReduce_97 = happySpecReduce_2  26# happyReduction_97
happyReduction_97 happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_2 of { happy_var_2 -> 
	happyIn30
		 (mkMachOp MO_S_Neg [happy_var_2]
	)}

happyReduce_98 = happyMonadReduce 5# 26# happyReduction_98
happyReduction_98 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOut31 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOut31 happy_x_5 of { happy_var_5 -> 
	( do { mo <- nameToMachOp happy_var_3 ;
					        return (mkMachOp mo [happy_var_1,happy_var_5]) })}}}
	) (\r -> happyReturn (happyIn30 r))

happyReduce_99 = happySpecReduce_1  26# happyReduction_99
happyReduction_99 happy_x_1
	 =  case happyOut31 happy_x_1 of { happy_var_1 -> 
	happyIn30
		 (happy_var_1
	)}

happyReduce_100 = happySpecReduce_2  27# happyReduction_100
happyReduction_100 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Int		happy_var_1)) -> 
	case happyOut32 happy_x_2 of { happy_var_2 -> 
	happyIn31
		 (return (CmmLit (CmmInt happy_var_1 (typeWidth happy_var_2)))
	)}}

happyReduce_101 = happySpecReduce_2  27# happyReduction_101
happyReduction_101 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Float	happy_var_1)) -> 
	case happyOut32 happy_x_2 of { happy_var_2 -> 
	happyIn31
		 (return (CmmLit (CmmFloat happy_var_1 (typeWidth happy_var_2)))
	)}}

happyReduce_102 = happySpecReduce_1  27# happyReduction_102
happyReduction_102 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_String	happy_var_1)) -> 
	happyIn31
		 (do s <- code (mkStringCLit happy_var_1); 
				      return (CmmLit s)
	)}

happyReduce_103 = happySpecReduce_1  27# happyReduction_103
happyReduction_103 happy_x_1
	 =  case happyOut39 happy_x_1 of { happy_var_1 -> 
	happyIn31
		 (happy_var_1
	)}

happyReduce_104 = happyReduce 4# 27# happyReduction_104
happyReduction_104 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut51 happy_x_1 of { happy_var_1 -> 
	case happyOut30 happy_x_3 of { happy_var_3 -> 
	happyIn31
		 (do e <- happy_var_3; return (CmmLoad e happy_var_1)
	) `HappyStk` happyRest}}

happyReduce_105 = happyMonadReduce 5# 27# happyReduction_105
happyReduction_105 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	case happyOut37 happy_x_4 of { happy_var_4 -> 
	( exprOp happy_var_2 happy_var_4)}}
	) (\r -> happyReturn (happyIn31 r))

happyReduce_106 = happySpecReduce_3  27# happyReduction_106
happyReduction_106 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_2 of { happy_var_2 -> 
	happyIn31
		 (happy_var_2
	)}

happyReduce_107 = happySpecReduce_0  28# happyReduction_107
happyReduction_107  =  happyIn32
		 (bWord
	)

happyReduce_108 = happySpecReduce_2  28# happyReduction_108
happyReduction_108 happy_x_2
	happy_x_1
	 =  case happyOut51 happy_x_2 of { happy_var_2 -> 
	happyIn32
		 (happy_var_2
	)}

happyReduce_109 = happySpecReduce_0  29# happyReduction_109
happyReduction_109  =  happyIn33
		 ([]
	)

happyReduce_110 = happySpecReduce_3  29# happyReduction_110
happyReduction_110 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut34 happy_x_2 of { happy_var_2 -> 
	happyIn33
		 (happy_var_2
	)}

happyReduce_111 = happySpecReduce_0  30# happyReduction_111
happyReduction_111  =  happyIn34
		 ([]
	)

happyReduce_112 = happySpecReduce_1  30# happyReduction_112
happyReduction_112 happy_x_1
	 =  case happyOut35 happy_x_1 of { happy_var_1 -> 
	happyIn34
		 (happy_var_1
	)}

happyReduce_113 = happySpecReduce_1  31# happyReduction_113
happyReduction_113 happy_x_1
	 =  case happyOut36 happy_x_1 of { happy_var_1 -> 
	happyIn35
		 ([happy_var_1]
	)}

happyReduce_114 = happySpecReduce_3  31# happyReduction_114
happyReduction_114 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut36 happy_x_1 of { happy_var_1 -> 
	case happyOut35 happy_x_3 of { happy_var_3 -> 
	happyIn35
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_115 = happySpecReduce_1  32# happyReduction_115
happyReduction_115 happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	happyIn36
		 (do e <- happy_var_1; return (CmmHinted e (inferCmmHint e))
	)}

happyReduce_116 = happyMonadReduce 2# 32# happyReduction_116
happyReduction_116 (happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_2 of { (L _ (CmmT_String	happy_var_2)) -> 
	( do h <- parseCmmHint happy_var_2;
					      return $ do
						e <- happy_var_1; return (CmmHinted e h))}}
	) (\r -> happyReturn (happyIn36 r))

happyReduce_117 = happySpecReduce_0  33# happyReduction_117
happyReduction_117  =  happyIn37
		 ([]
	)

happyReduce_118 = happySpecReduce_1  33# happyReduction_118
happyReduction_118 happy_x_1
	 =  case happyOut38 happy_x_1 of { happy_var_1 -> 
	happyIn37
		 (happy_var_1
	)}

happyReduce_119 = happySpecReduce_1  34# happyReduction_119
happyReduction_119 happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	happyIn38
		 ([ happy_var_1 ]
	)}

happyReduce_120 = happySpecReduce_3  34# happyReduction_120
happyReduction_120 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut30 happy_x_1 of { happy_var_1 -> 
	case happyOut38 happy_x_3 of { happy_var_3 -> 
	happyIn38
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_121 = happySpecReduce_1  35# happyReduction_121
happyReduction_121 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn39
		 (lookupName happy_var_1
	)}

happyReduce_122 = happySpecReduce_1  35# happyReduction_122
happyReduction_122 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_GlobalReg   happy_var_1)) -> 
	happyIn39
		 (return (CmmReg (CmmGlobal happy_var_1))
	)}

happyReduce_123 = happySpecReduce_0  36# happyReduction_123
happyReduction_123  =  happyIn40
		 ([]
	)

happyReduce_124 = happyReduce 4# 36# happyReduction_124
happyReduction_124 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut41 happy_x_2 of { happy_var_2 -> 
	happyIn40
		 (happy_var_2
	) `HappyStk` happyRest}

happyReduce_125 = happySpecReduce_1  37# happyReduction_125
happyReduction_125 happy_x_1
	 =  case happyOut42 happy_x_1 of { happy_var_1 -> 
	happyIn41
		 ([happy_var_1]
	)}

happyReduce_126 = happySpecReduce_2  37# happyReduction_126
happyReduction_126 happy_x_2
	happy_x_1
	 =  case happyOut42 happy_x_1 of { happy_var_1 -> 
	happyIn41
		 ([happy_var_1]
	)}

happyReduce_127 = happySpecReduce_3  37# happyReduction_127
happyReduction_127 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut42 happy_x_1 of { happy_var_1 -> 
	case happyOut41 happy_x_3 of { happy_var_3 -> 
	happyIn41
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_128 = happySpecReduce_1  38# happyReduction_128
happyReduction_128 happy_x_1
	 =  case happyOut43 happy_x_1 of { happy_var_1 -> 
	happyIn42
		 (do e <- happy_var_1; return (CmmHinted e (inferCmmHint (CmmReg (CmmLocal e))))
	)}

happyReduce_129 = happyMonadReduce 2# 38# happyReduction_129
happyReduction_129 (happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_String	happy_var_1)) -> 
	case happyOut43 happy_x_2 of { happy_var_2 -> 
	( do h <- parseCmmHint happy_var_1;
					      return $ do
						e <- happy_var_2; return (CmmHinted e h))}}
	) (\r -> happyReturn (happyIn42 r))

happyReduce_130 = happySpecReduce_1  39# happyReduction_130
happyReduction_130 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn43
		 (do e <- lookupName happy_var_1;
				     return $
				       case e of 
					CmmReg (CmmLocal r) -> r
					other -> pprPanic "CmmParse:" (ftext happy_var_1 <> text " not a local register")
	)}

happyReduce_131 = happySpecReduce_1  40# happyReduction_131
happyReduction_131 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn44
		 (do e <- lookupName happy_var_1;
				     return $
				       case e of 
					CmmReg r -> r
					other -> pprPanic "CmmParse:" (ftext happy_var_1 <> text " not a register")
	)}

happyReduce_132 = happySpecReduce_1  40# happyReduction_132
happyReduction_132 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_GlobalReg   happy_var_1)) -> 
	happyIn44
		 (return (CmmGlobal happy_var_1)
	)}

happyReduce_133 = happySpecReduce_0  41# happyReduction_133
happyReduction_133  =  happyIn45
		 ([]
	)

happyReduce_134 = happySpecReduce_3  41# happyReduction_134
happyReduction_134 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut46 happy_x_2 of { happy_var_2 -> 
	happyIn45
		 (happy_var_2
	)}

happyReduce_135 = happySpecReduce_0  42# happyReduction_135
happyReduction_135  =  happyIn46
		 ([]
	)

happyReduce_136 = happySpecReduce_1  42# happyReduction_136
happyReduction_136 happy_x_1
	 =  case happyOut47 happy_x_1 of { happy_var_1 -> 
	happyIn46
		 (happy_var_1
	)}

happyReduce_137 = happySpecReduce_2  43# happyReduction_137
happyReduction_137 happy_x_2
	happy_x_1
	 =  case happyOut48 happy_x_1 of { happy_var_1 -> 
	happyIn47
		 ([happy_var_1]
	)}

happyReduce_138 = happySpecReduce_1  43# happyReduction_138
happyReduction_138 happy_x_1
	 =  case happyOut48 happy_x_1 of { happy_var_1 -> 
	happyIn47
		 ([happy_var_1]
	)}

happyReduce_139 = happySpecReduce_3  43# happyReduction_139
happyReduction_139 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut48 happy_x_1 of { happy_var_1 -> 
	case happyOut47 happy_x_3 of { happy_var_3 -> 
	happyIn47
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_140 = happySpecReduce_2  44# happyReduction_140
happyReduction_140 happy_x_2
	happy_x_1
	 =  case happyOut51 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn48
		 (newLocal happy_var_1 happy_var_2
	)}}

happyReduce_141 = happySpecReduce_0  45# happyReduction_141
happyReduction_141  =  happyIn49
		 (return Nothing
	)

happyReduce_142 = happyReduce 5# 45# happyReduction_142
happyReduction_142 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut30 happy_x_2 of { happy_var_2 -> 
	case happyOut37 happy_x_4 of { happy_var_4 -> 
	happyIn49
		 (do { target <- happy_var_2;
					       args <- sequence happy_var_4;
					       return $ Just (UpdateFrame target args) }
	) `HappyStk` happyRest}}

happyReduce_143 = happySpecReduce_0  46# happyReduction_143
happyReduction_143  =  happyIn50
		 (return Nothing
	)

happyReduce_144 = happySpecReduce_2  46# happyReduction_144
happyReduction_144 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn50
		 (do l <- lookupLabel happy_var_2; return (Just l)
	)}

happyReduce_145 = happySpecReduce_1  47# happyReduction_145
happyReduction_145 happy_x_1
	 =  happyIn51
		 (b8
	)

happyReduce_146 = happySpecReduce_1  47# happyReduction_146
happyReduction_146 happy_x_1
	 =  case happyOut52 happy_x_1 of { happy_var_1 -> 
	happyIn51
		 (happy_var_1
	)}

happyReduce_147 = happySpecReduce_1  48# happyReduction_147
happyReduction_147 happy_x_1
	 =  happyIn52
		 (b16
	)

happyReduce_148 = happySpecReduce_1  48# happyReduction_148
happyReduction_148 happy_x_1
	 =  happyIn52
		 (b32
	)

happyReduce_149 = happySpecReduce_1  48# happyReduction_149
happyReduction_149 happy_x_1
	 =  happyIn52
		 (b64
	)

happyReduce_150 = happySpecReduce_1  48# happyReduction_150
happyReduction_150 happy_x_1
	 =  happyIn52
		 (f32
	)

happyReduce_151 = happySpecReduce_1  48# happyReduction_151
happyReduction_151 happy_x_1
	 =  happyIn52
		 (f64
	)

happyReduce_152 = happySpecReduce_1  48# happyReduction_152
happyReduction_152 happy_x_1
	 =  happyIn52
		 (gcWord
	)

happyNewToken action sts stk
	= cmmlex(\tk -> 
	let cont i = happyDoAction i tk action sts stk in
	case tk of {
	L _ CmmT_EOF -> happyDoAction 68# tk action sts stk;
	L _ (CmmT_SpecChar ':') -> cont 1#;
	L _ (CmmT_SpecChar ';') -> cont 2#;
	L _ (CmmT_SpecChar '{') -> cont 3#;
	L _ (CmmT_SpecChar '}') -> cont 4#;
	L _ (CmmT_SpecChar '[') -> cont 5#;
	L _ (CmmT_SpecChar ']') -> cont 6#;
	L _ (CmmT_SpecChar '(') -> cont 7#;
	L _ (CmmT_SpecChar ')') -> cont 8#;
	L _ (CmmT_SpecChar '=') -> cont 9#;
	L _ (CmmT_SpecChar '`') -> cont 10#;
	L _ (CmmT_SpecChar '~') -> cont 11#;
	L _ (CmmT_SpecChar '/') -> cont 12#;
	L _ (CmmT_SpecChar '*') -> cont 13#;
	L _ (CmmT_SpecChar '%') -> cont 14#;
	L _ (CmmT_SpecChar '-') -> cont 15#;
	L _ (CmmT_SpecChar '+') -> cont 16#;
	L _ (CmmT_SpecChar '&') -> cont 17#;
	L _ (CmmT_SpecChar '^') -> cont 18#;
	L _ (CmmT_SpecChar '|') -> cont 19#;
	L _ (CmmT_SpecChar '>') -> cont 20#;
	L _ (CmmT_SpecChar '<') -> cont 21#;
	L _ (CmmT_SpecChar ',') -> cont 22#;
	L _ (CmmT_SpecChar '!') -> cont 23#;
	L _ (CmmT_DotDot) -> cont 24#;
	L _ (CmmT_DoubleColon) -> cont 25#;
	L _ (CmmT_Shr) -> cont 26#;
	L _ (CmmT_Shl) -> cont 27#;
	L _ (CmmT_Ge) -> cont 28#;
	L _ (CmmT_Le) -> cont 29#;
	L _ (CmmT_Eq) -> cont 30#;
	L _ (CmmT_Ne) -> cont 31#;
	L _ (CmmT_BoolAnd) -> cont 32#;
	L _ (CmmT_BoolOr) -> cont 33#;
	L _ (CmmT_CLOSURE) -> cont 34#;
	L _ (CmmT_INFO_TABLE) -> cont 35#;
	L _ (CmmT_INFO_TABLE_RET) -> cont 36#;
	L _ (CmmT_INFO_TABLE_FUN) -> cont 37#;
	L _ (CmmT_INFO_TABLE_CONSTR) -> cont 38#;
	L _ (CmmT_INFO_TABLE_SELECTOR) -> cont 39#;
	L _ (CmmT_else) -> cont 40#;
	L _ (CmmT_export) -> cont 41#;
	L _ (CmmT_section) -> cont 42#;
	L _ (CmmT_align) -> cont 43#;
	L _ (CmmT_goto) -> cont 44#;
	L _ (CmmT_if) -> cont 45#;
	L _ (CmmT_jump) -> cont 46#;
	L _ (CmmT_foreign) -> cont 47#;
	L _ (CmmT_never) -> cont 48#;
	L _ (CmmT_prim) -> cont 49#;
	L _ (CmmT_return) -> cont 50#;
	L _ (CmmT_returns) -> cont 51#;
	L _ (CmmT_import) -> cont 52#;
	L _ (CmmT_switch) -> cont 53#;
	L _ (CmmT_case) -> cont 54#;
	L _ (CmmT_default) -> cont 55#;
	L _ (CmmT_bits8) -> cont 56#;
	L _ (CmmT_bits16) -> cont 57#;
	L _ (CmmT_bits32) -> cont 58#;
	L _ (CmmT_bits64) -> cont 59#;
	L _ (CmmT_float32) -> cont 60#;
	L _ (CmmT_float64) -> cont 61#;
	L _ (CmmT_gcptr) -> cont 62#;
	L _ (CmmT_GlobalReg   happy_dollar_dollar) -> cont 63#;
	L _ (CmmT_Name	happy_dollar_dollar) -> cont 64#;
	L _ (CmmT_String	happy_dollar_dollar) -> cont 65#;
	L _ (CmmT_Int		happy_dollar_dollar) -> cont 66#;
	L _ (CmmT_Float	happy_dollar_dollar) -> cont 67#;
	_ -> happyError' tk
	})

happyError_ tk = happyError' tk

happyThen :: () => P a -> (a -> P b) -> P b
happyThen = (>>=)
happyReturn :: () => a -> P a
happyReturn = (return)
happyThen1 = happyThen
happyReturn1 :: () => a -> P a
happyReturn1 = happyReturn
happyError' :: () => (Located CmmToken) -> P a
happyError' tk = (\token -> happyError) tk

cmmParse = happySomeParser where
  happySomeParser = happyThen (happyParse 0#) (\x -> happyReturn (happyOut4 x))

happySeq = happyDoSeq


section :: String -> Section
section "text"	 = Text
section "data" 	 = Data
section "rodata" = ReadOnlyData
section "relrodata" = RelocatableReadOnlyData
section "bss"	 = UninitialisedData
section s	 = OtherSection s

mkString :: String -> CmmStatic
mkString s = CmmString (map (fromIntegral.ord) s)

-- mkMachOp infers the type of the MachOp from the type of its first
-- argument.  We assume that this is correct: for MachOps that don't have
-- symmetrical args (e.g. shift ops), the first arg determines the type of
-- the op.
mkMachOp :: (Width -> MachOp) -> [ExtFCode CmmExpr] -> ExtFCode CmmExpr
mkMachOp fn args = do
  arg_exprs <- sequence args
  return (CmmMachOp (fn (typeWidth (cmmExprType (head arg_exprs)))) arg_exprs)

getLit :: CmmExpr -> CmmLit
getLit (CmmLit l) = l
getLit (CmmMachOp (MO_S_Neg _) [CmmLit (CmmInt i r)])  = CmmInt (negate i) r
getLit _ = panic "invalid literal" -- TODO messy failure

nameToMachOp :: FastString -> P (Width -> MachOp)
nameToMachOp name = 
  case lookupUFM machOps name of
	Nothing -> fail ("unknown primitive " ++ unpackFS name)
	Just m  -> return m

exprOp :: FastString -> [ExtFCode CmmExpr] -> P (ExtFCode CmmExpr)
exprOp name args_code =
  case lookupUFM exprMacros name of
     Just f  -> return $ do
        args <- sequence args_code
	return (f args)
     Nothing -> do
	mo <- nameToMachOp name
	return $ mkMachOp mo args_code

exprMacros :: UniqFM ([CmmExpr] -> CmmExpr)
exprMacros = listToUFM [
  ( fsLit "ENTRY_CODE",   \ [x] -> entryCode x ),
  ( fsLit "INFO_PTR",     \ [x] -> closureInfoPtr x ),
  ( fsLit "STD_INFO",     \ [x] -> infoTable x ),
  ( fsLit "FUN_INFO",     \ [x] -> funInfoTable x ),
  ( fsLit "GET_ENTRY",    \ [x] -> entryCode (closureInfoPtr x) ),
  ( fsLit "GET_STD_INFO", \ [x] -> infoTable (closureInfoPtr x) ),
  ( fsLit "GET_FUN_INFO", \ [x] -> funInfoTable (closureInfoPtr x) ),
  ( fsLit "INFO_TYPE",    \ [x] -> infoTableClosureType x ),
  ( fsLit "INFO_PTRS",    \ [x] -> infoTablePtrs x ),
  ( fsLit "INFO_NPTRS",   \ [x] -> infoTableNonPtrs x )
  ]

-- we understand a subset of C-- primitives:
machOps = listToUFM $
	map (\(x, y) -> (mkFastString x, y)) [
	( "add",	MO_Add ),
	( "sub",	MO_Sub ),
	( "eq",		MO_Eq ),
	( "ne",		MO_Ne ),
	( "mul",	MO_Mul ),
	( "neg",	MO_S_Neg ),
	( "quot",	MO_S_Quot ),
	( "rem",	MO_S_Rem ),
	( "divu",	MO_U_Quot ),
	( "modu",	MO_U_Rem ),

	( "ge",		MO_S_Ge ),
	( "le",		MO_S_Le ),
	( "gt",		MO_S_Gt ),
	( "lt",		MO_S_Lt ),

	( "geu",	MO_U_Ge ),
	( "leu",	MO_U_Le ),
	( "gtu",	MO_U_Gt ),
	( "ltu",	MO_U_Lt ),

	( "flt",	MO_S_Lt ),
	( "fle",	MO_S_Le ),
	( "feq",	MO_Eq ),
	( "fne",	MO_Ne ),
	( "fgt",	MO_S_Gt ),
	( "fge",	MO_S_Ge ),
	( "fneg",	MO_S_Neg ),

	( "and",	MO_And ),
	( "or",		MO_Or ),
	( "xor",	MO_Xor ),
	( "com",	MO_Not ),
	( "shl",	MO_Shl ),
	( "shrl",	MO_U_Shr ),
	( "shra",	MO_S_Shr ),

	( "lobits8",  flip MO_UU_Conv W8  ),
	( "lobits16", flip MO_UU_Conv W16 ),
	( "lobits32", flip MO_UU_Conv W32 ),
	( "lobits64", flip MO_UU_Conv W64 ),

	( "zx16",     flip MO_UU_Conv W16 ),
	( "zx32",     flip MO_UU_Conv W32 ),
	( "zx64",     flip MO_UU_Conv W64 ),

	( "sx16",     flip MO_SS_Conv W16 ),
	( "sx32",     flip MO_SS_Conv W32 ),
	( "sx64",     flip MO_SS_Conv W64 ),

	( "f2f32",    flip MO_FF_Conv W32 ),  -- TODO; rounding mode
	( "f2f64",    flip MO_FF_Conv W64 ),  -- TODO; rounding mode
	( "f2i8",     flip MO_FS_Conv W8 ),
	( "f2i16",    flip MO_FS_Conv W16 ),
	( "f2i32",    flip MO_FS_Conv W32 ),
	( "f2i64",    flip MO_FS_Conv W64 ),
	( "i2f32",    flip MO_SF_Conv W32 ),
	( "i2f64",    flip MO_SF_Conv W64 )
	]

callishMachOps = listToUFM $
	map (\(x, y) -> (mkFastString x, y)) [
        ( "write_barrier", MO_WriteBarrier )
        -- ToDo: the rest, maybe
    ]

parseSafety :: String -> P CmmSafety
parseSafety "safe"   = return (CmmSafe NoC_SRT)
parseSafety "unsafe" = return CmmUnsafe
parseSafety str      = fail ("unrecognised safety: " ++ str)

parseCmmHint :: String -> P ForeignHint
parseCmmHint "ptr"    = return AddrHint
parseCmmHint "signed" = return SignedHint
parseCmmHint str      = fail ("unrecognised hint: " ++ str)

-- labels are always pointers, so we might as well infer the hint
inferCmmHint :: CmmExpr -> ForeignHint
inferCmmHint (CmmLit (CmmLabel _)) = AddrHint
inferCmmHint (CmmReg (CmmGlobal g)) | isPtrGlobalReg g = AddrHint
inferCmmHint _ = NoHint

isPtrGlobalReg Sp		     = True
isPtrGlobalReg SpLim		     = True
isPtrGlobalReg Hp		     = True
isPtrGlobalReg HpLim		     = True
isPtrGlobalReg CurrentTSO	     = True
isPtrGlobalReg CurrentNursery	     = True
isPtrGlobalReg (VanillaReg _ VGcPtr) = True
isPtrGlobalReg _		     = False

happyError :: P a
happyError = srcParseFail

-- -----------------------------------------------------------------------------
-- Statement-level macros

stmtMacro :: FastString -> [ExtFCode CmmExpr] -> P ExtCode
stmtMacro fun args_code = do
  case lookupUFM stmtMacros fun of
    Nothing -> fail ("unknown macro: " ++ unpackFS fun)
    Just fcode -> return $ do
	args <- sequence args_code
	code (fcode args)

stmtMacros :: UniqFM ([CmmExpr] -> Code)
stmtMacros = listToUFM [
  ( fsLit "CCS_ALLOC",		   \[words,ccs]  -> profAlloc words ccs ),
  ( fsLit "CLOSE_NURSERY",	   \[]  -> emitCloseNursery ),
  ( fsLit "ENTER_CCS_PAP_CL",     \[e] -> enterCostCentrePAP e ),
  ( fsLit "ENTER_CCS_THUNK",      \[e] -> enterCostCentreThunk e ),
  ( fsLit "HP_CHK_GEN",           \[words,liveness,reentry] -> 
                                      hpChkGen words liveness reentry ),
  ( fsLit "HP_CHK_NP_ASSIGN_SP0", \[e,f] -> hpChkNodePointsAssignSp0 e f ),
  ( fsLit "LOAD_THREAD_STATE",    \[] -> emitLoadThreadState ),
  ( fsLit "LDV_ENTER",            \[e] -> ldvEnter e ),
  ( fsLit "LDV_RECORD_CREATE",    \[e] -> ldvRecordCreate e ),
  ( fsLit "OPEN_NURSERY",	   \[]  -> emitOpenNursery ),
  ( fsLit "PUSH_UPD_FRAME",	   \[sp,e] -> emitPushUpdateFrame sp e ),
  ( fsLit "SAVE_THREAD_STATE",    \[] -> emitSaveThreadState ),
  ( fsLit "SET_HDR",		   \[ptr,info,ccs] -> 
					emitSetDynHdr ptr info ccs ),
  ( fsLit "STK_CHK_GEN",          \[words,liveness,reentry] -> 
                                      stkChkGen words liveness reentry ),
  ( fsLit "STK_CHK_NP",	   \[e] -> stkChkNodePoints e ),
  ( fsLit "TICK_ALLOC_PRIM", 	   \[hdr,goods,slop] -> 
					tickyAllocPrim hdr goods slop ),
  ( fsLit "TICK_ALLOC_PAP",       \[goods,slop] -> 
					tickyAllocPAP goods slop ),
  ( fsLit "TICK_ALLOC_UP_THK",    \[goods,slop] -> 
					tickyAllocThunk goods slop ),
  ( fsLit "UPD_BH_UPDATABLE",       \[] -> emitBlackHoleCode False ),
  ( fsLit "UPD_BH_SINGLE_ENTRY",    \[] -> emitBlackHoleCode True ),

  ( fsLit "RET_P",	\[a] ->       emitRetUT [(PtrArg,a)]),
  ( fsLit "RET_N",	\[a] ->       emitRetUT [(NonPtrArg,a)]),
  ( fsLit "RET_PP",	\[a,b] ->     emitRetUT [(PtrArg,a),(PtrArg,b)]),
  ( fsLit "RET_NN",	\[a,b] ->     emitRetUT [(NonPtrArg,a),(NonPtrArg,b)]),
  ( fsLit "RET_NP",	\[a,b] ->     emitRetUT [(NonPtrArg,a),(PtrArg,b)]),
  ( fsLit "RET_PPP",	\[a,b,c] ->   emitRetUT [(PtrArg,a),(PtrArg,b),(PtrArg,c)]),
  ( fsLit "RET_NPP",	\[a,b,c] ->   emitRetUT [(NonPtrArg,a),(PtrArg,b),(PtrArg,c)]),
  ( fsLit "RET_NNP",	\[a,b,c] ->   emitRetUT [(NonPtrArg,a),(NonPtrArg,b),(PtrArg,c)]),
  ( fsLit "RET_NNN",  \[a,b,c] -> emitRetUT [(NonPtrArg,a),(NonPtrArg,b),(NonPtrArg,c)]),
  ( fsLit "RET_NNNN",  \[a,b,c,d] -> emitRetUT [(NonPtrArg,a),(NonPtrArg,b),(NonPtrArg,c),(NonPtrArg,d)]),
  ( fsLit "RET_NNNP",	\[a,b,c,d] -> emitRetUT [(NonPtrArg,a),(NonPtrArg,b),(NonPtrArg,c),(PtrArg,d)]),
  ( fsLit "RET_NPNP",	\[a,b,c,d] -> emitRetUT [(NonPtrArg,a),(PtrArg,b),(NonPtrArg,c),(PtrArg,d)])

 ]



profilingInfo desc_str ty_str = do
  lit1 <- if opt_SccProfilingOn 
		   then code $ mkStringCLit desc_str
		   else return (mkIntCLit 0)
  lit2 <- if opt_SccProfilingOn 
		   then code $ mkStringCLit ty_str
		   else return (mkIntCLit 0)
  return (ProfilingInfo lit1 lit2)


staticClosure :: PackageId -> FastString -> FastString -> [CmmLit] -> ExtCode
staticClosure pkg cl_label info payload
  = code $ emitDataLits (mkCmmDataLabel pkg cl_label) lits
  where  lits = mkStaticClosure (mkCmmInfoLabel pkg info) dontCareCCS payload [] [] []

foreignCall
	:: String
	-> [ExtFCode HintedCmmFormal]
	-> ExtFCode CmmExpr
	-> [ExtFCode HintedCmmActual]
	-> Maybe [GlobalReg]
        -> CmmSafety
        -> CmmReturnInfo
        -> P ExtCode
foreignCall conv_string results_code expr_code args_code vols safety ret
  = do  convention <- case conv_string of
          "C" -> return CCallConv
          "stdcall" -> return StdCallConv
          "C--" -> return CmmCallConv
          _ -> fail ("unknown calling convention: " ++ conv_string)
	return $ do
	  results <- sequence results_code
	  expr <- expr_code
	  args <- sequence args_code
	  --code (stmtC (CmmCall (CmmCallee expr convention) results args safety))
          case convention of
            -- Temporary hack so at least some functions are CmmSafe
            CmmCallConv -> code (stmtC (CmmCall (CmmCallee expr convention) results args safety ret))
            _ ->
              let expr' = adjCallTarget convention expr args in
              case safety of
	      CmmUnsafe ->
                code (emitForeignCall' PlayRisky results 
                   (CmmCallee expr' convention) args vols NoC_SRT ret)
              CmmSafe srt ->
                code (emitForeignCall' (PlaySafe unused) results 
                   (CmmCallee expr' convention) args vols NoC_SRT ret) where
	        unused = panic "not used by emitForeignCall'"

adjCallTarget :: CCallConv -> CmmExpr -> [CmmHinted CmmExpr] -> CmmExpr
#ifdef mingw32_TARGET_OS
-- On Windows, we have to add the '@N' suffix to the label when making
-- a call with the stdcall calling convention.
adjCallTarget StdCallConv (CmmLit (CmmLabel lbl)) args
  = CmmLit (CmmLabel (addLabelSize lbl (sum (map size args))))
  where size (CmmHinted e _) = max wORD_SIZE (widthInBytes (typeWidth (cmmExprType e)))
                 -- c.f. CgForeignCall.emitForeignCall
#endif
adjCallTarget _ expr _
  = expr

primCall
	:: [ExtFCode HintedCmmFormal]
	-> FastString
	-> [ExtFCode HintedCmmActual]
	-> Maybe [GlobalReg]
        -> CmmSafety
        -> P ExtCode
primCall results_code name args_code vols safety
  = case lookupUFM callishMachOps name of
	Nothing -> fail ("unknown primitive " ++ unpackFS name)
	Just p  -> return $ do
		results <- sequence results_code
		args <- sequence args_code
		case safety of
		  CmmUnsafe ->
		    code (emitForeignCall' PlayRisky results
		      (CmmPrim p) args vols NoC_SRT CmmMayReturn)
		  CmmSafe srt ->
		    code (emitForeignCall' (PlaySafe unused) results 
		      (CmmPrim p) args vols NoC_SRT CmmMayReturn) where
		    unused = panic "not used by emitForeignCall'"

doStore :: CmmType -> ExtFCode CmmExpr  -> ExtFCode CmmExpr -> ExtCode
doStore rep addr_code val_code
  = do addr <- addr_code
       val <- val_code
	-- if the specified store type does not match the type of the expr
	-- on the rhs, then we insert a coercion that will cause the type
	-- mismatch to be flagged by cmm-lint.  If we don't do this, then
	-- the store will happen at the wrong type, and the error will not
	-- be noticed.
       let val_width = typeWidth (cmmExprType val)
           rep_width = typeWidth rep
       let coerce_val 
		| val_width /= rep_width = CmmMachOp (MO_UU_Conv val_width rep_width) [val]
		| otherwise              = val
       stmtEC (CmmStore addr coerce_val)

-- Return an unboxed tuple.
emitRetUT :: [(CgRep,CmmExpr)] -> Code
emitRetUT args = do
  tickyUnboxedTupleReturn (length args)  -- TICK
  (sp, stmts) <- pushUnboxedTuple 0 args
  emitSimultaneously stmts -- NB. the args might overlap with the stack slots
                           -- or regs that we assign to, so better use
                           -- simultaneous assignments here (#3546)
  when (sp /= 0) $ stmtC (CmmAssign spReg (cmmRegOffW spReg (-sp)))
  stmtC (CmmJump (entryCode (CmmLoad (cmmRegOffW spReg sp) bWord)) [])
  -- TODO (when using CPS): emitStmt (CmmReturn (map snd args))

-- -----------------------------------------------------------------------------
-- If-then-else and boolean expressions

data BoolExpr
  = BoolExpr `BoolAnd` BoolExpr
  | BoolExpr `BoolOr`  BoolExpr
  | BoolNot BoolExpr
  | BoolTest CmmExpr

-- ToDo: smart constructors which simplify the boolean expression.

cmmIfThenElse cond then_part else_part = do
     then_id <- code newLabelC
     join_id <- code newLabelC
     c <- cond
     emitCond c then_id
     else_part
     stmtEC (CmmBranch join_id)
     code (labelC then_id)
     then_part
     -- fall through to join
     code (labelC join_id)

-- 'emitCond cond true_id'  emits code to test whether the cond is true,
-- branching to true_id if so, and falling through otherwise.
emitCond (BoolTest e) then_id = do
  stmtEC (CmmCondBranch e then_id)
emitCond (BoolNot (BoolTest (CmmMachOp op args))) then_id
  | Just op' <- maybeInvertComparison op
  = emitCond (BoolTest (CmmMachOp op' args)) then_id
emitCond (BoolNot e) then_id = do
  else_id <- code newLabelC
  emitCond e else_id
  stmtEC (CmmBranch then_id)
  code (labelC else_id)
emitCond (e1 `BoolOr` e2) then_id = do
  emitCond e1 then_id
  emitCond e2 then_id
emitCond (e1 `BoolAnd` e2) then_id = do
	-- we'd like to invert one of the conditionals here to avoid an
	-- extra branch instruction, but we can't use maybeInvertComparison
	-- here because we can't look too closely at the expression since
	-- we're in a loop.
  and_id <- code newLabelC
  else_id <- code newLabelC
  emitCond e1 and_id
  stmtEC (CmmBranch else_id)
  code (labelC and_id)
  emitCond e2 then_id
  code (labelC else_id)


-- -----------------------------------------------------------------------------
-- Table jumps

-- We use a simplified form of C-- switch statements for now.  A
-- switch statement always compiles to a table jump.  Each arm can
-- specify a list of values (not ranges), and there can be a single
-- default branch.  The range of the table is given either by the
-- optional range on the switch (eg. switch [0..7] {...}), or by
-- the minimum/maximum values from the branches.

doSwitch :: Maybe (Int,Int) -> ExtFCode CmmExpr -> [([Int],ExtCode)]
         -> Maybe ExtCode -> ExtCode
doSwitch mb_range scrut arms deflt
   = do 
	-- Compile code for the default branch
	dflt_entry <- 
		case deflt of
		  Nothing -> return Nothing
		  Just e  -> do b <- forkLabelledCodeEC e; return (Just b)

	-- Compile each case branch
	table_entries <- mapM emitArm arms

	-- Construct the table
	let
	    all_entries = concat table_entries
	    ixs = map fst all_entries
	    (min,max) 
		| Just (l,u) <- mb_range = (l,u)
		| otherwise              = (minimum ixs, maximum ixs)

	    entries = elems (accumArray (\_ a -> Just a) dflt_entry (min,max)
				all_entries)
	expr <- scrut
	-- ToDo: check for out of range and jump to default if necessary
        stmtEC (CmmSwitch expr entries)
   where
	emitArm :: ([Int],ExtCode) -> ExtFCode [(Int,BlockId)]
	emitArm (ints,code) = do
	   blockid <- forkLabelledCodeEC code
	   return [ (i,blockid) | i <- ints ]


-- -----------------------------------------------------------------------------
-- Putting it all together

-- The initial environment: we define some constants that the compiler
-- knows about here.
initEnv :: Env
initEnv = listToUFM [
  ( fsLit "SIZEOF_StgHeader", 
    Var (CmmLit (CmmInt (fromIntegral (fixedHdrSize * wORD_SIZE)) wordWidth) )),
  ( fsLit "SIZEOF_StgInfoTable",
    Var (CmmLit (CmmInt (fromIntegral stdInfoTableSizeB) wordWidth) ))
  ]

parseCmmFile :: DynFlags -> FilePath -> IO (Messages, Maybe Cmm)
parseCmmFile dflags filename = do
  showPass dflags "ParseCmm"
  buf <- hGetStringBuffer filename
  let
	init_loc = mkSrcLoc (mkFastString filename) 1 1
	init_state = (mkPState dflags buf init_loc) { lex_state = [0] }
		-- reset the lex_state: the Lexer monad leaves some stuff
		-- in there we don't want.
  case unP cmmParse init_state of
    PFailed span err -> do
        let msg = mkPlainErrMsg span err
        return ((emptyBag, unitBag msg), Nothing)
    POk pst code -> do
        cmm <- initC dflags no_module (getCmm (unEC code initEnv [] >> return ()))
        let ms = getMessages pst
        if (errorsFound dflags ms)
         then return (ms, Nothing)
         else do
           dumpIfSet_dyn dflags Opt_D_dump_cmm "Cmm" (ppr cmm)
           return (ms, Just cmm)
  where
	no_module = panic "parseCmmFile: no module"
{-# LINE 1 "templates/GenericTemplate.hs" #-}
{-# LINE 1 "templates/GenericTemplate.hs" #-}
{-# LINE 1 "<built-in>" #-}
{-# LINE 1 "<command-line>" #-}
{-# LINE 1 "templates/GenericTemplate.hs" #-}
-- Id: GenericTemplate.hs,v 1.26 2005/01/14 14:47:22 simonmar Exp 

{-# LINE 28 "templates/GenericTemplate.hs" #-}


data Happy_IntList = HappyCons Happy_GHC_Exts.Int# Happy_IntList





{-# LINE 49 "templates/GenericTemplate.hs" #-}

{-# LINE 59 "templates/GenericTemplate.hs" #-}

{-# LINE 68 "templates/GenericTemplate.hs" #-}

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
				     where new_state = (n Happy_GHC_Exts.-# (1# :: Happy_GHC_Exts.Int#))
   where off    = indexShortOffAddr happyActOffsets st
	 off_i  = (off Happy_GHC_Exts.+# i)
	 check  = if (off_i Happy_GHC_Exts.>=# (0# :: Happy_GHC_Exts.Int#))
			then (indexShortOffAddr happyCheck off_i Happy_GHC_Exts.==#  i)
			else False
 	 action | check     = indexShortOffAddr happyTable off_i
		| otherwise = indexShortOffAddr happyDefActions st

{-# LINE 127 "templates/GenericTemplate.hs" #-}


indexShortOffAddr (HappyA# arr) off =
#if __GLASGOW_HASKELL__ > 500
	Happy_GHC_Exts.narrow16Int# i
#elif __GLASGOW_HASKELL__ == 500
	Happy_GHC_Exts.intToInt16# i
#else
	Happy_GHC_Exts.iShiftRA# (Happy_GHC_Exts.iShiftL# i 16#) 16#
#endif
  where
#if __GLASGOW_HASKELL__ >= 503
	i = Happy_GHC_Exts.word2Int# (Happy_GHC_Exts.or# (Happy_GHC_Exts.uncheckedShiftL# high 8#) low)
#else
	i = Happy_GHC_Exts.word2Int# (Happy_GHC_Exts.or# (Happy_GHC_Exts.shiftL# high 8#) low)
#endif
	high = Happy_GHC_Exts.int2Word# (Happy_GHC_Exts.ord# (Happy_GHC_Exts.indexCharOffAddr# arr (off' Happy_GHC_Exts.+# 1#)))
	low  = Happy_GHC_Exts.int2Word# (Happy_GHC_Exts.ord# (Happy_GHC_Exts.indexCharOffAddr# arr off'))
	off' = off Happy_GHC_Exts.*# 2#





data HappyAddr = HappyA# Happy_GHC_Exts.Addr#




-----------------------------------------------------------------------------
-- HappyState data type (not arrays)

{-# LINE 170 "templates/GenericTemplate.hs" #-}

-----------------------------------------------------------------------------
-- Shifting a token

happyShift new_state 0# tk st sts stk@(x `HappyStk` _) =
     let i = (case Happy_GHC_Exts.unsafeCoerce# x of { (Happy_GHC_Exts.I# (i)) -> i }) in
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
       where sts1@((HappyCons (st1@(action)) (_))) = happyDrop k (HappyCons (st) (sts))
             drop_stk = happyDropStk k stk

happyMonad2Reduce k nt fn 0# tk st sts stk
     = happyFail 0# tk st sts stk
happyMonad2Reduce k nt fn j tk st sts stk =
       happyThen1 (fn stk tk) (\r -> happyNewToken new_state sts1 (r `HappyStk` drop_stk))
       where sts1@((HappyCons (st1@(action)) (_))) = happyDrop k (HappyCons (st) (sts))
             drop_stk = happyDropStk k stk

             off    = indexShortOffAddr happyGotoOffsets st1
             off_i  = (off Happy_GHC_Exts.+# nt)
             new_state = indexShortOffAddr happyTable off_i




happyDrop 0# l = l
happyDrop n (HappyCons (_) (t)) = happyDrop (n Happy_GHC_Exts.-# (1# :: Happy_GHC_Exts.Int#)) t

happyDropStk 0# l = l
happyDropStk n (x `HappyStk` xs) = happyDropStk (n Happy_GHC_Exts.-# (1#::Happy_GHC_Exts.Int#)) xs

-----------------------------------------------------------------------------
-- Moving to a new state after a reduction


happyGoto nt j tk st = 
   {- nothing -}
   happyDoAction j tk new_state
   where off    = indexShortOffAddr happyGotoOffsets st
	 off_i  = (off Happy_GHC_Exts.+# nt)
 	 new_state = indexShortOffAddr happyTable off_i




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
