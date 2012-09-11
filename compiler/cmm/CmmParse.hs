{-# OPTIONS_GHC -w #-}
{-# OPTIONS -fglasgow-exts -cpp #-}
{-# LANGUAGE BangPatterns #-} -- required for versions of Happy before 1.18.6
{-# OPTIONS -Wwarn -w #-}
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
import OldCmm
import OldPprCmm()
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
import qualified Data.Array as Happy_Data_Array
import qualified GHC.Exts as Happy_GHC_Exts

-- parser produced by Happy Version 1.18.6

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
happyIn7 :: (ExtFCode CLabel) -> (HappyAbsSyn )
happyIn7 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn7 #-}
happyOut7 :: (HappyAbsSyn ) -> (ExtFCode CLabel)
happyOut7 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut7 #-}
happyIn8 :: ([ExtFCode [CmmStatic]]) -> (HappyAbsSyn )
happyIn8 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn8 #-}
happyOut8 :: (HappyAbsSyn ) -> ([ExtFCode [CmmStatic]])
happyOut8 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut8 #-}
happyIn9 :: (ExtFCode [CmmStatic]) -> (HappyAbsSyn )
happyIn9 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn9 #-}
happyOut9 :: (HappyAbsSyn ) -> (ExtFCode [CmmStatic])
happyOut9 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut9 #-}
happyIn10 :: ([ExtFCode CmmExpr]) -> (HappyAbsSyn )
happyIn10 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn10 #-}
happyOut10 :: (HappyAbsSyn ) -> ([ExtFCode CmmExpr])
happyOut10 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut10 #-}
happyIn11 :: (ExtCode) -> (HappyAbsSyn )
happyIn11 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn11 #-}
happyOut11 :: (HappyAbsSyn ) -> (ExtCode)
happyOut11 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut11 #-}
happyIn12 :: (ExtFCode (CLabel, CmmInfoTable, [Maybe LocalReg])) -> (HappyAbsSyn )
happyIn12 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn12 #-}
happyOut12 :: (HappyAbsSyn ) -> (ExtFCode (CLabel, CmmInfoTable, [Maybe LocalReg]))
happyOut12 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut12 #-}
happyIn13 :: (ExtCode) -> (HappyAbsSyn )
happyIn13 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn13 #-}
happyOut13 :: (HappyAbsSyn ) -> (ExtCode)
happyOut13 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut13 #-}
happyIn14 :: (ExtCode) -> (HappyAbsSyn )
happyIn14 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn14 #-}
happyOut14 :: (HappyAbsSyn ) -> (ExtCode)
happyOut14 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut14 #-}
happyIn15 :: ([(FastString, CLabel)]) -> (HappyAbsSyn )
happyIn15 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn15 #-}
happyOut15 :: (HappyAbsSyn ) -> ([(FastString, CLabel)])
happyOut15 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut15 #-}
happyIn16 :: ((FastString,  CLabel)) -> (HappyAbsSyn )
happyIn16 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn16 #-}
happyOut16 :: (HappyAbsSyn ) -> ((FastString,  CLabel))
happyOut16 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut16 #-}
happyIn17 :: ([FastString]) -> (HappyAbsSyn )
happyIn17 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn17 #-}
happyOut17 :: (HappyAbsSyn ) -> ([FastString])
happyOut17 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut17 #-}
happyIn18 :: (ExtCode) -> (HappyAbsSyn )
happyIn18 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn18 #-}
happyOut18 :: (HappyAbsSyn ) -> (ExtCode)
happyOut18 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut18 #-}
happyIn19 :: (CmmReturnInfo) -> (HappyAbsSyn )
happyIn19 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn19 #-}
happyOut19 :: (HappyAbsSyn ) -> (CmmReturnInfo)
happyOut19 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut19 #-}
happyIn20 :: (ExtFCode BoolExpr) -> (HappyAbsSyn )
happyIn20 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn20 #-}
happyOut20 :: (HappyAbsSyn ) -> (ExtFCode BoolExpr)
happyOut20 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut20 #-}
happyIn21 :: (ExtFCode BoolExpr) -> (HappyAbsSyn )
happyIn21 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn21 #-}
happyOut21 :: (HappyAbsSyn ) -> (ExtFCode BoolExpr)
happyOut21 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut21 #-}
happyIn22 :: (CmmSafety) -> (HappyAbsSyn )
happyIn22 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn22 #-}
happyOut22 :: (HappyAbsSyn ) -> (CmmSafety)
happyOut22 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut22 #-}
happyIn23 :: (Maybe [GlobalReg]) -> (HappyAbsSyn )
happyIn23 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn23 #-}
happyOut23 :: (HappyAbsSyn ) -> (Maybe [GlobalReg])
happyOut23 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut23 #-}
happyIn24 :: ([GlobalReg]) -> (HappyAbsSyn )
happyIn24 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn24 #-}
happyOut24 :: (HappyAbsSyn ) -> ([GlobalReg])
happyOut24 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut24 #-}
happyIn25 :: (Maybe (Int,Int)) -> (HappyAbsSyn )
happyIn25 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn25 #-}
happyOut25 :: (HappyAbsSyn ) -> (Maybe (Int,Int))
happyOut25 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut25 #-}
happyIn26 :: ([ExtFCode ([Int],Either BlockId ExtCode)]) -> (HappyAbsSyn )
happyIn26 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn26 #-}
happyOut26 :: (HappyAbsSyn ) -> ([ExtFCode ([Int],Either BlockId ExtCode)])
happyOut26 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut26 #-}
happyIn27 :: (ExtFCode ([Int],Either BlockId ExtCode)) -> (HappyAbsSyn )
happyIn27 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn27 #-}
happyOut27 :: (HappyAbsSyn ) -> (ExtFCode ([Int],Either BlockId ExtCode))
happyOut27 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut27 #-}
happyIn28 :: (ExtFCode (Either BlockId ExtCode)) -> (HappyAbsSyn )
happyIn28 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn28 #-}
happyOut28 :: (HappyAbsSyn ) -> (ExtFCode (Either BlockId ExtCode))
happyOut28 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut28 #-}
happyIn29 :: ([Int]) -> (HappyAbsSyn )
happyIn29 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn29 #-}
happyOut29 :: (HappyAbsSyn ) -> ([Int])
happyOut29 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut29 #-}
happyIn30 :: (Maybe ExtCode) -> (HappyAbsSyn )
happyIn30 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn30 #-}
happyOut30 :: (HappyAbsSyn ) -> (Maybe ExtCode)
happyOut30 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut30 #-}
happyIn31 :: (ExtCode) -> (HappyAbsSyn )
happyIn31 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn31 #-}
happyOut31 :: (HappyAbsSyn ) -> (ExtCode)
happyOut31 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut31 #-}
happyIn32 :: (ExtFCode CmmExpr) -> (HappyAbsSyn )
happyIn32 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn32 #-}
happyOut32 :: (HappyAbsSyn ) -> (ExtFCode CmmExpr)
happyOut32 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut32 #-}
happyIn33 :: (ExtFCode CmmExpr) -> (HappyAbsSyn )
happyIn33 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn33 #-}
happyOut33 :: (HappyAbsSyn ) -> (ExtFCode CmmExpr)
happyOut33 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut33 #-}
happyIn34 :: (CmmType) -> (HappyAbsSyn )
happyIn34 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn34 #-}
happyOut34 :: (HappyAbsSyn ) -> (CmmType)
happyOut34 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut34 #-}
happyIn35 :: ([ExtFCode HintedCmmActual]) -> (HappyAbsSyn )
happyIn35 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn35 #-}
happyOut35 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmActual])
happyOut35 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut35 #-}
happyIn36 :: ([ExtFCode HintedCmmActual]) -> (HappyAbsSyn )
happyIn36 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn36 #-}
happyOut36 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmActual])
happyOut36 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut36 #-}
happyIn37 :: ([ExtFCode HintedCmmActual]) -> (HappyAbsSyn )
happyIn37 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn37 #-}
happyOut37 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmActual])
happyOut37 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut37 #-}
happyIn38 :: (ExtFCode HintedCmmActual) -> (HappyAbsSyn )
happyIn38 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn38 #-}
happyOut38 :: (HappyAbsSyn ) -> (ExtFCode HintedCmmActual)
happyOut38 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut38 #-}
happyIn39 :: ([ExtFCode CmmExpr]) -> (HappyAbsSyn )
happyIn39 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn39 #-}
happyOut39 :: (HappyAbsSyn ) -> ([ExtFCode CmmExpr])
happyOut39 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut39 #-}
happyIn40 :: ([ExtFCode CmmExpr]) -> (HappyAbsSyn )
happyIn40 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn40 #-}
happyOut40 :: (HappyAbsSyn ) -> ([ExtFCode CmmExpr])
happyOut40 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut40 #-}
happyIn41 :: (ExtFCode CmmExpr) -> (HappyAbsSyn )
happyIn41 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn41 #-}
happyOut41 :: (HappyAbsSyn ) -> (ExtFCode CmmExpr)
happyOut41 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut41 #-}
happyIn42 :: ([ExtFCode HintedCmmFormal]) -> (HappyAbsSyn )
happyIn42 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn42 #-}
happyOut42 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmFormal])
happyOut42 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut42 #-}
happyIn43 :: ([ExtFCode HintedCmmFormal]) -> (HappyAbsSyn )
happyIn43 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn43 #-}
happyOut43 :: (HappyAbsSyn ) -> ([ExtFCode HintedCmmFormal])
happyOut43 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut43 #-}
happyIn44 :: (ExtFCode HintedCmmFormal) -> (HappyAbsSyn )
happyIn44 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn44 #-}
happyOut44 :: (HappyAbsSyn ) -> (ExtFCode HintedCmmFormal)
happyOut44 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut44 #-}
happyIn45 :: (ExtFCode LocalReg) -> (HappyAbsSyn )
happyIn45 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn45 #-}
happyOut45 :: (HappyAbsSyn ) -> (ExtFCode LocalReg)
happyOut45 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut45 #-}
happyIn46 :: (ExtFCode CmmReg) -> (HappyAbsSyn )
happyIn46 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn46 #-}
happyOut46 :: (HappyAbsSyn ) -> (ExtFCode CmmReg)
happyOut46 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut46 #-}
happyIn47 :: ([ExtFCode LocalReg]) -> (HappyAbsSyn )
happyIn47 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn47 #-}
happyOut47 :: (HappyAbsSyn ) -> ([ExtFCode LocalReg])
happyOut47 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut47 #-}
happyIn48 :: ([ExtFCode LocalReg]) -> (HappyAbsSyn )
happyIn48 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn48 #-}
happyOut48 :: (HappyAbsSyn ) -> ([ExtFCode LocalReg])
happyOut48 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut48 #-}
happyIn49 :: ([ExtFCode LocalReg]) -> (HappyAbsSyn )
happyIn49 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn49 #-}
happyOut49 :: (HappyAbsSyn ) -> ([ExtFCode LocalReg])
happyOut49 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut49 #-}
happyIn50 :: (ExtFCode LocalReg) -> (HappyAbsSyn )
happyIn50 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn50 #-}
happyOut50 :: (HappyAbsSyn ) -> (ExtFCode LocalReg)
happyOut50 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut50 #-}
happyIn51 :: (ExtFCode (Maybe UpdateFrame)) -> (HappyAbsSyn )
happyIn51 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn51 #-}
happyOut51 :: (HappyAbsSyn ) -> (ExtFCode (Maybe UpdateFrame))
happyOut51 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut51 #-}
happyIn52 :: (ExtFCode (Maybe BlockId)) -> (HappyAbsSyn )
happyIn52 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn52 #-}
happyOut52 :: (HappyAbsSyn ) -> (ExtFCode (Maybe BlockId))
happyOut52 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut52 #-}
happyIn53 :: (CmmType) -> (HappyAbsSyn )
happyIn53 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn53 #-}
happyOut53 :: (HappyAbsSyn ) -> (CmmType)
happyOut53 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut53 #-}
happyIn54 :: (CmmType) -> (HappyAbsSyn )
happyIn54 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyIn54 #-}
happyOut54 :: (HappyAbsSyn ) -> (CmmType)
happyOut54 x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOut54 #-}
happyInTok :: (Located CmmToken) -> (HappyAbsSyn )
happyInTok x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyInTok #-}
happyOutTok :: (HappyAbsSyn ) -> (Located CmmToken)
happyOutTok x = Happy_GHC_Exts.unsafeCoerce# x
{-# INLINE happyOutTok #-}


happyActOffsets :: HappyAddr
happyActOffsets = HappyA# "\x37\x01\x00\x00\x34\x03\x37\x01\x00\x00\x00\x00\x6f\x03\x00\x00\x26\x03\x00\x00\x6e\x03\x6c\x03\x66\x03\x61\x03\x60\x03\x5e\x03\x23\x03\x1c\x03\x22\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x51\x03\x2b\x03\x94\x00\x54\x03\x37\x03\x00\x00\x15\x03\x44\x03\x3b\x03\x21\x03\x13\x03\x08\x03\x06\x03\x05\x03\x03\x03\xf8\x02\x33\x03\x05\x00\x00\x00\xf7\x02\x00\x00\xf3\x02\x00\x00\x20\x03\x17\x03\x12\x03\x11\x03\x07\x03\x01\x03\xe6\x02\x00\x00\xe3\x02\x00\x00\x22\x01\x00\x00\x10\x03\x00\x00\x00\x03\xd5\x02\xe5\x02\x0a\x03\x61\x00\x00\x00\x94\x00\x00\x00\x00\x00\x3c\x00\x02\x03\x00\x00\xc6\x02\xc3\x02\xb5\x02\xb4\x02\xa3\x02\xb3\x02\x00\x00\xf2\x02\x1a\x00\xf1\x02\xf0\x02\x0c\x00\xe7\x02\xe2\x02\xd7\x02\x00\x00\xe4\x02\x3c\x00\xff\xff\xe1\x02\xe0\x02\xde\x02\x00\x00\x27\x02\xcc\x02\x00\x00\xd8\x02\x61\x00\x61\x00\x98\x02\x61\x00\x00\x00\x00\x00\x00\x00\xbe\x02\xbe\x02\x1a\x00\xd1\x02\x1a\x00\x1a\x00\xe7\xff\xc4\x02\x0d\x00\x00\x00\x0b\x01\x93\x02\x54\x00\x61\x00\xc1\x02\xc2\x02\x00\x00\x14\x00\x00\x00\x94\x00\x00\x00\xd2\x00\xb6\x02\x00\x00\x3f\x02\x61\x00\x86\x02\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x61\x00\x02\x00\x77\x02\x83\x02\x94\x01\x00\x00\x00\x00\x00\x00\x81\x02\x76\x02\x73\x02\x00\x00\x94\x00\x65\x02\xab\x02\x61\x00\xa1\x02\x00\x00\x9a\x03\x96\x02\xa0\x02\xa5\x02\x92\x02\x90\x02\x87\x02\x00\x00\x91\x02\x80\x02\x52\x02\x89\x02\xc2\x03\xc2\x03\xc2\x03\xc2\x03\x7b\x00\x7b\x00\xc2\x03\xc2\x03\xd6\x03\xfc\x00\xdd\x03\xd2\x00\xd2\x00\x00\x00\x00\x00\x00\x00\x86\x03\x84\x02\x00\x00\x7b\x02\xdc\x01\x00\x00\x61\x00\x00\x00\x00\x00\x61\x00\x61\x00\x49\x02\x82\x02\x61\x00\x0e\x02\x08\x00\x00\x00\xae\x03\x54\x00\x54\x00\x75\x02\x61\x02\x5a\x02\x00\x00\x00\x00\x3a\x02\x61\x00\x61\x00\x21\x02\x53\x02\x00\x00\x00\x00\x00\x00\x17\x02\x61\x00\x80\x01\xc2\x01\x00\x00\x0b\x01\x4f\x02\x00\x00\x00\x00\x0d\x01\x4e\x02\x3f\x02\x1a\x00\x54\x00\x54\x00\x15\x02\x48\x02\x99\x00\x41\x02\x00\x00\x32\x02\x00\x00\x28\x02\xa8\x01\x37\x02\x36\x02\x00\x00\x43\x00\x00\x00\x61\x00\x3b\x02\x30\x02\x29\x02\x2e\x02\xee\x01\xe5\x01\xe4\x01\x00\x00\xe2\x01\x00\x00\x00\x00\x0f\x02\x03\x02\x02\x02\x01\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0b\x02\xe0\x01\xcc\x01\x61\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0d\x01\xec\x01\x07\x02\x00\x00\x00\x00\x00\x00\xf7\x01\x00\x00\xf5\x01\xf8\x01\x61\x00\x61\x00\x61\x00\xd6\x01\x00\x00\xef\x01\xc6\x01\xbe\x01\xb1\x01\x00\x00\xa6\x01\xb0\x01\xa5\x01\xa4\x01\xce\x01\xcd\x01\xc5\x01\xd2\x01\xd7\x01\xc3\x01\x00\x00\xc9\x01\xcb\x01\x00\x00\x00\x00\xc8\x01\x6c\x01\xb9\x01\xb8\x01\x89\x01\x89\x01\x00\x00\x1a\x00\xaa\x01\x00\x00\x87\x01\x24\x00\x00\x00\x7e\x01\x7d\x01\x6b\x01\xa2\x01\x83\x01\x6f\x01\x00\x00\x1a\x00\x58\x01\x00\x00\x1a\x00\x93\x01\x7f\x01\x00\x00\x7f\x01\x81\x01\x06\x00\x46\x01\x00\x00\x66\x01\x64\x01\x5b\x01\x12\x01\x0c\x01\x00\x00\x45\x01\x41\x01\x00\x00\x00\x00\x00\x00\x3c\x01\x08\x01\x29\x01\x00\x00\x02\x01\x00\x00\xe3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"#

happyGotoOffsets :: HappyAddr
happyGotoOffsets = HappyA# "\xb9\x00\x00\x00\x00\x00\x2b\x00\x00\x00\x00\x00\x0e\x01\x00\x00\x1a\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x17\x01\x00\x00\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf5\x00\xee\x00\x3b\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe5\x00\x00\x00\xe4\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x04\x01\x00\x00\x03\x01\x00\x00\xed\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xce\x00\x00\x00\x5f\x03\x00\x00\x40\x00\x00\x00\x00\x00\xab\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x06\x01\xfe\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xfe\xff\x5d\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x4f\x03\x4d\x03\x00\x00\x3f\x03\x00\x00\x00\x00\x00\x00\xdc\x00\xd7\x00\xf9\x00\x00\x00\xf7\x00\xe8\x00\x00\x00\x00\x00\xd9\x00\x00\x00\x95\x00\x00\x00\x33\x01\x3d\x03\xc3\x00\xcf\x00\x00\x00\x00\x00\x00\x00\xb7\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x2f\x03\x00\x00\x7d\x02\x2d\x03\x1f\x03\x1d\x03\x0f\x03\x0d\x03\xff\x02\xfd\x02\xef\x02\xed\x02\xdf\x02\xdd\x02\xcf\x02\xcd\x02\xbf\x02\xbd\x02\xaf\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x38\x00\x00\x00\x00\x00\xad\x02\x00\x00\x00\x00\xd3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xc4\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x6d\x02\x00\x00\x00\x00\x63\x02\x9f\x02\x00\x00\x00\x00\x51\x02\xb6\x00\x00\x00\x00\x00\x00\x00\x25\x01\x23\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x9f\x00\x9d\x02\x8f\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x8d\x02\x00\x00\x00\x00\x00\x00\xf6\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xcd\x00\x15\x01\xf4\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf2\xff\x00\x00\x7f\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x9b\x00\x00\x00\x5c\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x4a\x02\x43\x02\x20\x01\xa7\x00\x00\x00\x00\x00\xa5\x00\x4a\x00\x5a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x86\x00\x0e\x00\x00\x00\xca\x00\x00\x00\x00\x00\x4e\x00\x1e\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xbd\x00\x00\x00\x00\x00\xbb\x00\x00\x00\x1b\x00\x00\x00\x07\x00\x00\x00\x16\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf5\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"#

happyDefActions :: HappyAddr
happyDefActions = HappyA# "\xfe\xff\x00\x00\x00\x00\xfe\xff\xfb\xff\xfc\xff\x79\xff\xfa\xff\x00\x00\x6c\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x6d\xff\x6b\xff\x6a\xff\x69\xff\x68\xff\x67\xff\x66\xff\x79\xff\x6f\xff\x77\xff\x00\x00\xdd\xff\xdb\xff\x00\x00\x00\x00\x00\x00\xd9\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x6f\xff\xfd\xff\x71\xff\xeb\xff\x00\x00\xe0\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xde\xff\x00\x00\xda\xff\x00\x00\xdf\xff\x00\x00\x76\xff\x74\xff\x00\x00\x71\xff\x00\x00\x00\x00\x72\xff\x75\xff\x78\xff\xdc\xff\xf6\xff\x00\x00\xd8\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x6e\xff\x00\x00\xe3\xff\xee\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf7\xff\x00\x00\xf6\xff\x00\x00\x6c\xff\x00\x00\x6d\xff\x73\xff\x00\x00\x9b\xff\x97\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x84\xff\x85\xff\x98\xff\x93\xff\x93\xff\xe3\xff\x00\x00\xe3\xff\xe3\xff\x00\x00\x00\x00\x00\x00\xd7\xff\x00\x00\x00\x00\x00\x00\x00\x00\x91\xff\xba\xff\x7a\xff\x7b\xff\x99\xff\x00\x00\x9a\xff\x9d\xff\x00\x00\x9e\xff\x00\x00\x00\x00\x00\x00\x89\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf3\xff\xf5\xff\xf8\xff\x00\x00\x00\x00\x00\x00\xe5\xff\x77\xff\x00\x00\x00\x00\x00\x00\x00\x00\xec\xff\xee\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\xff\x00\x00\xee\xff\x00\x00\x00\x00\xa0\xff\x9f\xff\xa2\xff\xa4\xff\xa8\xff\xa9\xff\xa1\xff\xa3\xff\xa5\xff\xa6\xff\xa7\xff\xaa\xff\xab\xff\xac\xff\xad\xff\xae\xff\x87\xff\x00\x00\x88\xff\x00\x00\x00\x00\x94\xff\x89\xff\x92\xff\xd6\xff\x89\xff\x00\x00\x00\x00\x00\x00\x8f\xff\x91\xff\x00\x00\xc8\xff\xc7\xff\x00\x00\x00\x00\x00\x00\x00\x00\x81\xff\x7e\xff\x7c\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe1\xff\xe2\xff\xea\xff\x00\x00\x00\x00\x00\x00\x00\x00\x7d\xff\x80\xff\x00\x00\xcf\xff\xc4\xff\x00\x00\xc8\xff\xc7\xff\xe3\xff\x00\x00\x00\x00\x00\x00\x00\x00\x8b\xff\x00\x00\x8e\xff\x8d\xff\xcd\xff\x00\x00\x00\x00\x00\x00\x00\x00\x96\xff\x00\x00\x70\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe4\xff\x00\x00\xf9\xff\xed\xff\x00\x00\x00\x00\x00\x00\x00\x00\xf0\xff\xef\xff\xf2\xff\xf1\xff\x86\xff\x9c\xff\x95\xff\x00\x00\xb9\xff\x00\x00\x00\x00\x90\xff\x8a\xff\xce\xff\xcc\xff\xc5\xff\xc6\xff\x00\x00\xc3\xff\x82\xff\x7f\xff\x00\x00\xd5\xff\x00\x00\x00\x00\x8f\xff\x8f\xff\x00\x00\xb0\xff\x8c\xff\x00\x00\xb1\xff\xb9\xff\x00\x00\xd1\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xb4\xff\xb8\xff\x00\x00\x00\x00\xbb\xff\xcb\xff\x00\x00\x00\x00\x00\x00\x00\x00\xc2\xff\xc2\xff\xd4\xff\xe3\xff\x00\x00\xd0\xff\x00\x00\x00\x00\xe6\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xb7\xff\xe3\xff\x00\x00\xb3\xff\xe3\xff\x00\x00\xc0\xff\xc1\xff\xc0\xff\x00\x00\x00\x00\xca\xff\xaf\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe9\xff\x00\x00\x00\x00\xb6\xff\xb5\xff\xb2\xff\x00\x00\x00\x00\x00\x00\xbf\xff\xbd\xff\xd2\xff\x00\x00\xbe\xff\xc9\xff\xd3\xff\xe7\xff\xe8\xff\xbc\xff"#

happyCheck :: HappyAddr
happyCheck = HappyA# "\xff\xff\x02\x00\x04\x00\x05\x00\x10\x00\x11\x00\x07\x00\x02\x00\x06\x00\x14\x00\x0b\x00\x03\x00\x06\x00\x0e\x00\x0f\x00\x1d\x00\x1c\x00\x1d\x00\x05\x00\x0f\x00\x08\x00\x01\x00\x2f\x00\x25\x00\x31\x00\x25\x00\x13\x00\x07\x00\x02\x00\x27\x00\x28\x00\x29\x00\x12\x00\x07\x00\x16\x00\x31\x00\x32\x00\x31\x00\x32\x00\x03\x00\x20\x00\x21\x00\x14\x00\x00\x00\x01\x00\x02\x00\x13\x00\x31\x00\x32\x00\x2c\x00\x07\x00\x08\x00\x2c\x00\x0a\x00\x18\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x43\x00\x29\x00\x42\x00\x3f\x00\x2c\x00\x2d\x00\x2e\x00\x2f\x00\x07\x00\x31\x00\x32\x00\x40\x00\x34\x00\x35\x00\x2c\x00\x0e\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x07\x00\x31\x00\x32\x00\x22\x00\x0b\x00\x16\x00\x17\x00\x0e\x00\x0f\x00\x2c\x00\x2d\x00\x2e\x00\x19\x00\x07\x00\x31\x00\x32\x00\x17\x00\x0b\x00\x2d\x00\x2e\x00\x0e\x00\x0f\x00\x31\x00\x32\x00\x19\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x43\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x43\x00\x12\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x3f\x00\x40\x00\x41\x00\x42\x00\x43\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x04\x00\x05\x00\x16\x00\x17\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x00\x00\x01\x00\x02\x00\x27\x00\x28\x00\x29\x00\x1a\x00\x07\x00\x08\x00\x1b\x00\x0a\x00\x09\x00\x0a\x00\x09\x00\x0a\x00\x29\x00\x0e\x00\x06\x00\x0e\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x09\x00\x0a\x00\x1f\x00\x09\x00\x0a\x00\x0e\x00\x06\x00\x41\x00\x0e\x00\x31\x00\x32\x00\x0c\x00\x0d\x00\x0e\x00\x26\x00\x1f\x00\x26\x00\x15\x00\x2a\x00\x0d\x00\x2a\x00\x31\x00\x32\x00\x31\x00\x32\x00\x31\x00\x32\x00\x31\x00\x32\x00\x26\x00\x09\x00\x0a\x00\x26\x00\x2a\x00\x1e\x00\x0e\x00\x2a\x00\x0b\x00\x0c\x00\x1e\x00\x31\x00\x32\x00\x2f\x00\x31\x00\x32\x00\x09\x00\x0a\x00\x09\x00\x0a\x00\x06\x00\x0e\x00\x03\x00\x0e\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x26\x00\x09\x00\x0a\x00\x0d\x00\x2a\x00\x2f\x00\x0e\x00\x30\x00\x1a\x00\x1b\x00\x16\x00\x31\x00\x32\x00\x0b\x00\x0c\x00\x26\x00\x30\x00\x26\x00\x2b\x00\x2a\x00\x3f\x00\x2a\x00\x0d\x00\x10\x00\x11\x00\x0d\x00\x31\x00\x32\x00\x31\x00\x32\x00\x26\x00\x20\x00\x21\x00\x06\x00\x2a\x00\x1c\x00\x1d\x00\x10\x00\x11\x00\x10\x00\x11\x00\x31\x00\x32\x00\x2b\x00\x25\x00\x33\x00\x1c\x00\x1d\x00\x02\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x10\x00\x11\x00\x25\x00\x31\x00\x32\x00\x25\x00\x08\x00\x25\x00\x40\x00\x41\x00\x08\x00\x42\x00\x1c\x00\x1d\x00\x31\x00\x32\x00\x41\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x22\x00\x23\x00\x24\x00\x25\x00\x26\x00\x27\x00\x04\x00\x29\x00\x2a\x00\x40\x00\x41\x00\x31\x00\x32\x00\x02\x00\x2c\x00\x2d\x00\x2e\x00\x04\x00\x34\x00\x31\x00\x32\x00\x02\x00\x38\x00\x39\x00\x3a\x00\x3b\x00\x3c\x00\x3d\x00\x3e\x00\x30\x00\x40\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x02\x00\x02\x00\x05\x00\x16\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x02\x00\x04\x00\x40\x00\x16\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x08\x00\x03\x00\x41\x00\x03\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x41\x00\x41\x00\x08\x00\x08\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x06\x00\x42\x00\x41\x00\x03\x00\x01\x00\x04\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x01\x00\x16\x00\x08\x00\x16\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x06\x00\x16\x00\x16\x00\x41\x00\x41\x00\x41\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x42\x00\x42\x00\x36\x00\x06\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x07\x00\x37\x00\x28\x00\x07\x00\x09\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x04\x00\x20\x00\x02\x00\x42\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x07\x00\x36\x00\x16\x00\x16\x00\x16\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x42\x00\x16\x00\x42\x00\x42\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x07\x00\x41\x00\x02\x00\x08\x00\x02\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x02\x00\x08\x00\x08\x00\x18\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x08\x00\x16\x00\x08\x00\x02\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x40\x00\x08\x00\x40\x00\x09\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x1c\x00\x1d\x00\x0e\x00\x41\x00\x20\x00\x21\x00\x22\x00\x1c\x00\x1d\x00\x25\x00\x08\x00\x20\x00\x21\x00\x22\x00\x1c\x00\x1d\x00\x25\x00\x16\x00\x20\x00\x21\x00\x22\x00\x31\x00\x32\x00\x25\x00\x02\x00\x1c\x00\x1d\x00\x40\x00\x31\x00\x32\x00\x21\x00\x22\x00\x1c\x00\x1d\x00\x25\x00\x31\x00\x32\x00\x02\x00\x0a\x00\x23\x00\x24\x00\x25\x00\x1c\x00\x1d\x00\x42\x00\x08\x00\x31\x00\x32\x00\x06\x00\x23\x00\x24\x00\x25\x00\x41\x00\x31\x00\x32\x00\x16\x00\x06\x00\x02\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x16\x00\x31\x00\x32\x00\x23\x00\x24\x00\x25\x00\x24\x00\x25\x00\x04\x00\x16\x00\x42\x00\x16\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x08\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x08\x00\x25\x00\x42\x00\x16\x00\x40\x00\x42\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x07\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x42\x00\x25\x00\x42\x00\x40\x00\x05\x00\x07\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x09\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x40\x00\x25\x00\x04\x00\x0a\x00\x19\x00\x40\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x05\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x05\x00\x25\x00\x42\x00\x05\x00\x07\x00\x04\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x16\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x40\x00\x25\x00\x03\x00\x42\x00\x42\x00\x16\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x16\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x01\x00\x25\x00\x42\x00\x16\x00\x16\x00\x42\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x03\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x2e\x00\x25\x00\x40\x00\x16\x00\x16\x00\x08\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x16\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x40\x00\x25\x00\x2e\x00\x40\x00\x16\x00\x16\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x16\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x40\x00\x25\x00\x02\x00\x16\x00\x16\x00\x40\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x02\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x40\x00\x25\x00\x40\x00\x40\x00\x03\x00\x40\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x16\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x40\x00\x25\x00\x40\x00\x02\x00\x2c\x00\x07\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x41\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x40\x00\x25\x00\x07\x00\x40\x00\x07\x00\x07\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\x07\x00\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\x07\x00\x25\x00\x07\x00\x07\x00\xff\xff\x44\x00\x1c\x00\x1d\x00\x1c\x00\x1d\x00\xff\xff\x31\x00\x32\x00\x31\x00\x32\x00\x25\x00\xff\xff\x25\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x31\x00\x32\x00\x31\x00\x32\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x16\x00\xff\xff\xff\xff\xff\xff\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x16\x00\xff\xff\xff\xff\xff\xff\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\xff\xff\xff\xff\xff\xff\xff\xff\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\xff\xff\xff\xff\xff\xff\xff\xff\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\xff\xff\xff\xff\x1a\x00\x1b\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x1a\x00\x1b\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"#

happyTable :: HappyAddr
happyTable = HappyA# "\x00\x00\x9e\x00\x9e\x00\x5c\x00\x23\x01\xd6\x00\x67\x00\x2f\x00\xb5\x00\x7d\x01\x68\x00\xf4\x00\x75\x01\x69\x00\x6a\x00\x19\x01\xd7\x00\x63\x00\xe1\x00\x71\x01\xa4\x00\xcf\x00\xe3\x00\x64\x00\xe4\x00\x64\x00\x62\x01\xd0\x00\x77\x00\x28\x01\xdc\x00\xdd\x00\x5f\x01\x78\x00\xa5\x00\x65\x00\x09\x00\x65\x00\x09\x00\x5b\x01\xf5\x00\xf6\x00\x73\x01\x2c\x00\x03\x00\x04\x00\x64\x01\x5d\x00\x5e\x00\x30\x00\x05\x00\x06\x00\xf7\x00\x07\x00\x59\x01\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x6b\x00\x6c\x00\x6d\x00\x6e\x00\x6f\x00\x11\x00\xb6\x00\x76\x01\x79\x00\x7a\x00\x7b\x00\x83\xff\x67\x00\x83\xff\x7c\x00\x24\x00\x13\x00\x7d\x00\x5c\x01\x69\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x7e\x00\x7f\x00\xd9\x00\x08\x00\x09\x00\x60\x00\x68\x00\x41\x01\x34\x01\x69\x00\x6a\x00\xad\x00\x3e\x00\x3f\x00\x5c\x01\x67\x00\x40\x00\x09\x00\xda\x00\x68\x00\x61\x00\x3f\x00\x69\x00\x6a\x00\x40\x00\x09\x00\x3f\x01\x61\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x6b\x00\x6c\x00\x6d\x00\x6e\x00\x6f\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x6b\x00\x6c\x00\x6d\x00\x6e\x00\x6f\x00\x61\x01\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x6b\x00\x6c\x00\x6d\x00\x6e\x00\x6f\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x5b\x00\x5c\x00\x33\x01\x34\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x02\x00\x03\x00\x04\x00\xdb\x00\xdc\x00\xdd\x00\x42\x01\x05\x00\x06\x00\x45\x01\x07\x00\x66\x01\x71\x00\x68\x01\x71\x00\xeb\x00\x72\x00\x07\x01\x72\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x5e\x01\x71\x00\xf7\x00\x25\x01\x71\x00\x72\x00\x0f\x01\x21\x01\x72\x00\x5d\x00\x5e\x00\x8a\x00\x8b\x00\x8c\x00\x73\x00\xd2\x00\x73\x00\xd0\x00\x74\x00\x2a\x00\x74\x00\xcd\x00\x09\x00\x08\x00\x09\x00\x75\x00\x09\x00\x75\x00\x09\x00\x73\x00\xe4\x00\x71\x00\x73\x00\x74\x00\x7f\x00\x72\x00\x74\x00\x47\x00\x1e\x00\x81\x00\x75\x00\x09\x00\x42\x00\x75\x00\x09\x00\xe5\x00\x71\x00\x70\x00\x71\x00\xa6\x00\x72\x00\x48\x00\x72\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x73\x00\xa8\x00\x71\x00\x4a\x00\x74\x00\x52\x00\x72\x00\x2d\x00\x94\x00\x95\x00\x78\x01\x75\x00\x09\x00\x1d\x00\x1e\x00\x73\x00\x41\x00\x73\x00\x1b\x00\x74\x00\x76\x01\x74\x00\x22\x00\x24\x01\xd6\x00\x2a\x00\x75\x00\x09\x00\x75\x00\x09\x00\x73\x00\xf5\x00\xf6\x00\x79\x01\x74\x00\xd7\x00\x63\x00\xef\x00\xd6\x00\xf0\x00\xf1\x00\x75\x00\x09\x00\x2b\x00\x64\x00\x7a\x01\x47\x01\x63\x00\x7b\x01\xd7\x00\x63\x00\xf2\x00\x63\x00\xd5\x00\xd6\x00\x64\x00\x65\x00\x09\x00\x64\x00\x7c\x01\x64\x00\xdf\x00\xe0\x00\x7d\x01\x6d\x01\xd7\x00\x63\x00\x65\x00\x09\x00\x6e\x01\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x0b\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x6f\x01\x11\x00\x12\x00\x20\x00\x21\x00\x65\x00\x09\x00\x70\x01\x3d\x00\x3e\x00\x3f\x00\x71\x01\x13\x00\x40\x00\x09\x00\x4d\x01\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x73\x01\x1b\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x2b\x01\x77\x01\x64\x01\x6a\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\xb2\x00\x66\x01\x68\x01\x6b\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x6c\x01\x1d\x01\x57\x01\x5e\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x58\x01\x59\x01\x4b\x01\x4c\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x2a\x01\x41\x01\x61\x01\x4e\x01\x4f\x01\x50\x01\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x52\x01\x51\x01\x53\x01\x54\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x02\x01\x55\x01\x56\x01\x3c\x01\x3d\x01\x3f\x01\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x3e\x01\x41\x01\x36\x01\x45\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x2f\x01\x44\x01\x47\x01\x2e\x01\x30\x01\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x31\x01\xf5\x00\x37\x01\x33\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\xd4\x00\x36\x01\x38\x01\x39\x01\x3a\x01\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x11\x01\x3b\x01\x12\x01\x13\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x89\x00\x14\x01\x15\x01\x16\x01\x17\x01\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x18\x01\x1b\x01\x1c\x01\x1e\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\xcc\x00\x1f\x01\x20\x01\x22\x01\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x23\x01\x27\x01\x2d\x01\x28\x01\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\xf8\x00\x63\x00\xe8\x00\xe9\x00\x48\x01\xfa\x00\xfb\x00\xf8\x00\x63\x00\x64\x00\xee\x00\x49\x01\xfa\x00\xfb\x00\xf8\x00\x63\x00\x64\x00\xed\x00\xf9\x00\xfa\x00\xfb\x00\x65\x00\x09\x00\x64\x00\xef\x00\xf8\x00\x63\x00\xdf\x00\x65\x00\x09\x00\x31\x01\xfb\x00\xc6\x00\x63\x00\x64\x00\x65\x00\x09\x00\xfd\x00\x03\x01\xff\x00\xc8\x00\x64\x00\xc6\x00\x63\x00\xfe\x00\x04\x01\x65\x00\x09\x00\x06\x01\x00\x01\xc8\x00\x64\x00\x07\x01\x65\x00\x09\x00\xa8\x00\x09\x01\x0f\x01\xc6\x00\x63\x00\xc6\x00\x63\x00\x0a\x01\x65\x00\x09\x00\xc7\x00\xc8\x00\x64\x00\x18\x01\x64\x00\xaa\x00\x0b\x01\xad\x00\x0c\x01\x2b\x01\x63\x00\xe9\x00\x63\x00\x0d\x01\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\xac\x00\x64\x00\xaf\x00\x0e\x01\xb4\x00\xb0\x00\xea\x00\x63\x00\xfe\x00\x63\x00\xcd\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\xb1\x00\x64\x00\xb3\x00\xca\x00\xd2\x00\xd4\x00\xaa\x00\x63\x00\xb6\x00\x63\x00\xe2\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\xdb\x00\x64\x00\xe7\x00\x88\x00\x81\x00\x84\x00\xb7\x00\x63\x00\xb8\x00\x63\x00\x87\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x9a\x00\x64\x00\x56\x00\x9c\x00\x9b\x00\xa0\x00\xb9\x00\x63\x00\xba\x00\x63\x00\xa1\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x55\x00\x64\x00\x54\x00\x57\x00\x58\x00\xa2\x00\xbb\x00\x63\x00\xbc\x00\x63\x00\xa3\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x5b\x00\x64\x00\x59\x00\xa6\x00\xa8\x00\x5a\x00\xbd\x00\x63\x00\xbe\x00\x63\x00\x70\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x44\x00\x64\x00\x45\x00\x46\x00\x4c\x00\x47\x00\xbf\x00\x63\x00\xc0\x00\x63\x00\x4d\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x4a\x00\x64\x00\x44\x00\x24\x00\x4e\x00\x4f\x00\xc1\x00\x63\x00\xc2\x00\x63\x00\x50\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x52\x00\x64\x00\x31\x00\x51\x00\x38\x00\x32\x00\xc3\x00\x63\x00\xc4\x00\x63\x00\x39\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x33\x00\x64\x00\x34\x00\x35\x00\x3a\x00\x36\x00\xc5\x00\x63\x00\xca\x00\x63\x00\x3c\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x37\x00\x64\x00\x3b\x00\x3d\x00\x30\x00\x1d\x00\xd4\x00\x63\x00\x82\x00\x63\x00\x22\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x24\x00\x64\x00\x25\x00\x24\x00\x26\x00\x27\x00\x84\x00\x63\x00\x85\x00\x63\x00\x28\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x29\x00\x64\x00\x2a\x00\x1d\x00\x00\x00\xff\xff\x9c\x00\x63\x00\x62\x00\x63\x00\x00\x00\x65\x00\x09\x00\x65\x00\x09\x00\x64\x00\x00\x00\x64\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x65\x00\x09\x00\x65\x00\x09\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x05\x01\x00\x00\x00\x00\x00\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\xa8\x00\x00\x00\x00\x00\x00\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x92\x00\x93\x00\x00\x00\x00\x00\x00\x00\x00\x00\x94\x00\x95\x00\x96\x00\x97\x00\x98\x00\x99\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x91\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x94\x00\x95\x00\x00\x00\x00\x00\x00\x00\x00\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x8f\x00\x90\x00\x8a\x00\x8b\x00\x8c\x00\x8d\x00\x8e\x00\x00\x00\x00\x00\x94\x00\x95\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x94\x00\x95\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"#

happyReduceArr = Happy_Data_Array.array (1, 153) [
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
	(152 , happyReduce_152),
	(153 , happyReduce_153)
	]

happy_n_terms = 69 :: Int
happy_n_nonterms = 51 :: Int

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
	 =  case happyOut11 happy_x_1 of { happy_var_1 -> 
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
	 =  case happyOut14 happy_x_1 of { happy_var_1 -> 
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
	case happyOut10 happy_x_6 of { happy_var_6 -> 
	( withThisPackage $ \pkg -> 
		   do lits <- sequence happy_var_6;
		      staticClosure pkg happy_var_3 happy_var_5 (map getLit lits))}}}
	) (\r -> happyReturn (happyIn5 r))

happyReduce_7 = happyReduce 6# 2# happyReduction_7
happyReduction_7 (happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_2 of { (L _ (CmmT_String	happy_var_2)) -> 
	case happyOut7 happy_x_4 of { happy_var_4 -> 
	case happyOut8 happy_x_5 of { happy_var_5 -> 
	happyIn6
		 (do lbl <- happy_var_4;
		     ss <- sequence happy_var_5;
		     code (emitDecl (CmmData (section happy_var_2) (Statics lbl $ concat ss)))
	) `HappyStk` happyRest}}}

happyReduce_8 = happyMonadReduce 2# 3# happyReduction_8
happyReduction_8 (happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	( withThisPackage $ \pkg -> 
		   return (mkCmmDataLabel pkg happy_var_1))}
	) (\r -> happyReturn (happyIn7 r))

happyReduce_9 = happySpecReduce_0  4# happyReduction_9
happyReduction_9  =  happyIn8
		 ([]
	)

happyReduce_10 = happySpecReduce_2  4# happyReduction_10
happyReduction_10 happy_x_2
	happy_x_1
	 =  case happyOut9 happy_x_1 of { happy_var_1 -> 
	case happyOut8 happy_x_2 of { happy_var_2 -> 
	happyIn8
		 (happy_var_1 : happy_var_2
	)}}

happyReduce_11 = happySpecReduce_3  5# happyReduction_11
happyReduction_11 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_2 of { happy_var_2 -> 
	happyIn9
		 (do e <- happy_var_2;
			     return [CmmStaticLit (getLit e)]
	)}

happyReduce_12 = happySpecReduce_2  5# happyReduction_12
happyReduction_12 happy_x_2
	happy_x_1
	 =  case happyOut53 happy_x_1 of { happy_var_1 -> 
	happyIn9
		 (return [CmmUninitialised
							(widthInBytes (typeWidth happy_var_1))]
	)}

happyReduce_13 = happyReduce 5# 5# happyReduction_13
happyReduction_13 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_4 of { (L _ (CmmT_String	happy_var_4)) -> 
	happyIn9
		 (return [mkString happy_var_4]
	) `HappyStk` happyRest}

happyReduce_14 = happyReduce 5# 5# happyReduction_14
happyReduction_14 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_3 of { (L _ (CmmT_Int		happy_var_3)) -> 
	happyIn9
		 (return [CmmUninitialised 
							(fromIntegral happy_var_3)]
	) `HappyStk` happyRest}

happyReduce_15 = happyReduce 5# 5# happyReduction_15
happyReduction_15 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut54 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_3 of { (L _ (CmmT_Int		happy_var_3)) -> 
	happyIn9
		 (return [CmmUninitialised 
						(widthInBytes (typeWidth happy_var_1) * 
							fromIntegral happy_var_3)]
	) `HappyStk` happyRest}}

happyReduce_16 = happyReduce 5# 5# happyReduction_16
happyReduction_16 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOut10 happy_x_4 of { happy_var_4 -> 
	happyIn9
		 (do lits <- sequence happy_var_4;
		     return $ map CmmStaticLit $
                       mkStaticClosure (mkForeignLabel happy_var_3 Nothing ForeignLabelInExternalPackage IsData)
                         -- mkForeignLabel because these are only used
                         -- for CHARLIKE and INTLIKE closures in the RTS.
			 dontCareCCS (map getLit lits) [] [] []
	) `HappyStk` happyRest}}

happyReduce_17 = happySpecReduce_0  6# happyReduction_17
happyReduction_17  =  happyIn10
		 ([]
	)

happyReduce_18 = happySpecReduce_3  6# happyReduction_18
happyReduction_18 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_2 of { happy_var_2 -> 
	case happyOut10 happy_x_3 of { happy_var_3 -> 
	happyIn10
		 (happy_var_2 : happy_var_3
	)}}

happyReduce_19 = happyReduce 7# 7# happyReduction_19
happyReduction_19 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut12 happy_x_1 of { happy_var_1 -> 
	case happyOut47 happy_x_2 of { happy_var_2 -> 
	case happyOut52 happy_x_3 of { happy_var_3 -> 
	case happyOut51 happy_x_4 of { happy_var_4 -> 
	case happyOut13 happy_x_6 of { happy_var_6 -> 
	happyIn11
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

happyReduce_20 = happySpecReduce_3  7# happyReduction_20
happyReduction_20 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut12 happy_x_1 of { happy_var_1 -> 
	case happyOut47 happy_x_2 of { happy_var_2 -> 
	happyIn11
		 (do (entry_ret_label, info, live) <- happy_var_1;
		     formals <- sequence happy_var_2;
		     code (emitInfoTableAndCode entry_ret_label (CmmInfo Nothing Nothing info) formals [])
	)}}

happyReduce_21 = happyMonadReduce 7# 7# happyReduction_21
happyReduction_21 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	case happyOut47 happy_x_2 of { happy_var_2 -> 
	case happyOut52 happy_x_3 of { happy_var_3 -> 
	case happyOut51 happy_x_4 of { happy_var_4 -> 
	case happyOut13 happy_x_6 of { happy_var_6 -> 
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
	) (\r -> happyReturn (happyIn11 r))

happyReduce_22 = happyMonadReduce 14# 8# happyReduction_22
happyReduction_22 (happy_x_14 `HappyStk`
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
		   do let prof = profilingInfo happy_var_11 happy_var_13
                          rep  = mkRTSRep (fromIntegral happy_var_9) $
                                   mkHeapRep False (fromIntegral happy_var_5)
                                                   (fromIntegral happy_var_7) Thunk
                              -- not really Thunk, but that makes the info table
                              -- we want.
                      return (mkCmmEntryLabel pkg happy_var_3,
			      CmmInfoTable { cit_lbl = mkCmmInfoLabel pkg happy_var_3
				           , cit_rep = rep
               				   , cit_prof = prof, cit_srt = NoC_SRT },
			      []))}}}}}}
	) (\r -> happyReturn (happyIn12 r))

happyReduce_23 = happyMonadReduce 16# 8# happyReduction_23
happyReduction_23 (happy_x_16 `HappyStk`
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
		   do let prof = profilingInfo happy_var_11 happy_var_13
                          ty   = Fun 0 (ArgSpec (fromIntegral happy_var_15))
                                -- Arity zero, arg_type happy_var_15
                          rep = mkRTSRep (fromIntegral happy_var_9) $
                                    mkHeapRep False (fromIntegral happy_var_5)
                                                    (fromIntegral happy_var_7) ty
                      return (mkCmmEntryLabel pkg happy_var_3,
			      CmmInfoTable { cit_lbl = mkCmmInfoLabel pkg happy_var_3
				           , cit_rep = rep
               				   , cit_prof = prof, cit_srt = NoC_SRT },
			      []))}}}}}}}
	) (\r -> happyReturn (happyIn12 r))

happyReduce_24 = happyMonadReduce 16# 8# happyReduction_24
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
	case happyOutTok happy_x_11 of { (L _ (CmmT_Int		happy_var_11)) -> 
	case happyOutTok happy_x_13 of { (L _ (CmmT_String	happy_var_13)) -> 
	case happyOutTok happy_x_15 of { (L _ (CmmT_String	happy_var_15)) -> 
	( withThisPackage $ \pkg ->
		   do let prof = profilingInfo happy_var_13 happy_var_15
                          ty  = Constr (fromIntegral happy_var_9)  -- Tag
	                           	(stringToWord8s happy_var_13)
                          rep = mkRTSRep (fromIntegral happy_var_11) $
                                  mkHeapRep False (fromIntegral happy_var_5)
                                                  (fromIntegral happy_var_7) ty
                      return (mkCmmEntryLabel pkg happy_var_3,
			      CmmInfoTable { cit_lbl = mkCmmInfoLabel pkg happy_var_3
				           , cit_rep = rep
               				   , cit_prof = prof, cit_srt = NoC_SRT },
			      []))}}}}}}}
	) (\r -> happyReturn (happyIn12 r))

happyReduce_25 = happyMonadReduce 12# 8# happyReduction_25
happyReduction_25 (happy_x_12 `HappyStk`
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
		   do let prof = profilingInfo happy_var_9 happy_var_11
                          ty  = ThunkSelector (fromIntegral happy_var_5)
                          rep = mkRTSRep (fromIntegral happy_var_7) $
                                   mkHeapRep False 0 0 ty
                      return (mkCmmEntryLabel pkg happy_var_3,
			      CmmInfoTable { cit_lbl = mkCmmInfoLabel pkg happy_var_3
				           , cit_rep = rep
               				   , cit_prof = prof, cit_srt = NoC_SRT },
			      []))}}}}}
	) (\r -> happyReturn (happyIn12 r))

happyReduce_26 = happyMonadReduce 6# 8# happyReduction_26
happyReduction_26 (happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOutTok happy_x_5 of { (L _ (CmmT_Int		happy_var_5)) -> 
	( withThisPackage $ \pkg ->
		   do let prof = NoProfilingInfo
                          rep  = mkRTSRep (fromIntegral happy_var_5) $ mkStackRep []
                      return (mkCmmRetLabel pkg happy_var_3,
			      CmmInfoTable { cit_lbl = mkCmmInfoLabel pkg happy_var_3
				           , cit_rep = rep
               				   , cit_prof = prof, cit_srt = NoC_SRT },
			      []))}}
	) (\r -> happyReturn (happyIn12 r))

happyReduce_27 = happyMonadReduce 8# 8# happyReduction_27
happyReduction_27 (happy_x_8 `HappyStk`
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
	case happyOut48 happy_x_7 of { happy_var_7 -> 
	( withThisPackage $ \pkg ->
		   do live <- sequence (map (liftM Just) happy_var_7)
		      let prof = NoProfilingInfo
                          bitmap = mkLiveness live
                          rep  = mkRTSRep (fromIntegral happy_var_5) $ mkStackRep bitmap
                      return (mkCmmRetLabel pkg happy_var_3,
			      CmmInfoTable { cit_lbl = mkCmmInfoLabel pkg happy_var_3
				           , cit_rep = rep
               				   , cit_prof = prof, cit_srt = NoC_SRT },
			      []))}}}
	) (\r -> happyReturn (happyIn12 r))

happyReduce_28 = happySpecReduce_0  9# happyReduction_28
happyReduction_28  =  happyIn13
		 (return ()
	)

happyReduce_29 = happySpecReduce_2  9# happyReduction_29
happyReduction_29 happy_x_2
	happy_x_1
	 =  case happyOut14 happy_x_1 of { happy_var_1 -> 
	case happyOut13 happy_x_2 of { happy_var_2 -> 
	happyIn13
		 (do happy_var_1; happy_var_2
	)}}

happyReduce_30 = happySpecReduce_2  9# happyReduction_30
happyReduction_30 happy_x_2
	happy_x_1
	 =  case happyOut18 happy_x_1 of { happy_var_1 -> 
	case happyOut13 happy_x_2 of { happy_var_2 -> 
	happyIn13
		 (do happy_var_1; happy_var_2
	)}}

happyReduce_31 = happySpecReduce_3  10# happyReduction_31
happyReduction_31 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut53 happy_x_1 of { happy_var_1 -> 
	case happyOut17 happy_x_2 of { happy_var_2 -> 
	happyIn14
		 (mapM_ (newLocal happy_var_1) happy_var_2
	)}}

happyReduce_32 = happySpecReduce_3  10# happyReduction_32
happyReduction_32 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut15 happy_x_2 of { happy_var_2 -> 
	happyIn14
		 (mapM_ newImport happy_var_2
	)}

happyReduce_33 = happySpecReduce_3  10# happyReduction_33
happyReduction_33 happy_x_3
	happy_x_2
	happy_x_1
	 =  happyIn14
		 (return ()
	)

happyReduce_34 = happySpecReduce_1  11# happyReduction_34
happyReduction_34 happy_x_1
	 =  case happyOut16 happy_x_1 of { happy_var_1 -> 
	happyIn15
		 ([happy_var_1]
	)}

happyReduce_35 = happySpecReduce_3  11# happyReduction_35
happyReduction_35 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut16 happy_x_1 of { happy_var_1 -> 
	case happyOut15 happy_x_3 of { happy_var_3 -> 
	happyIn15
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_36 = happySpecReduce_1  12# happyReduction_36
happyReduction_36 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn16
		 ((happy_var_1, mkForeignLabel happy_var_1 Nothing ForeignLabelInExternalPackage IsFunction)
	)}

happyReduce_37 = happySpecReduce_2  12# happyReduction_37
happyReduction_37 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_String	happy_var_1)) -> 
	case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn16
		 ((happy_var_2, mkCmmCodeLabel (fsToPackageId (mkFastString happy_var_1)) happy_var_2)
	)}}

happyReduce_38 = happySpecReduce_1  13# happyReduction_38
happyReduction_38 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn17
		 ([happy_var_1]
	)}

happyReduce_39 = happySpecReduce_3  13# happyReduction_39
happyReduction_39 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	case happyOut17 happy_x_3 of { happy_var_3 -> 
	happyIn17
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_40 = happySpecReduce_1  14# happyReduction_40
happyReduction_40 happy_x_1
	 =  happyIn18
		 (nopEC
	)

happyReduce_41 = happySpecReduce_2  14# happyReduction_41
happyReduction_41 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn18
		 (do l <- newLabel happy_var_1; code (labelC l)
	)}

happyReduce_42 = happyReduce 4# 14# happyReduction_42
happyReduction_42 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut46 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn18
		 (do reg <- happy_var_1; e <- happy_var_3; stmtEC (CmmAssign reg e)
	) `HappyStk` happyRest}}

happyReduce_43 = happyReduce 7# 14# happyReduction_43
happyReduction_43 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut53 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	case happyOut32 happy_x_6 of { happy_var_6 -> 
	happyIn18
		 (doStore happy_var_1 happy_var_3 happy_var_6
	) `HappyStk` happyRest}}}

happyReduce_44 = happyMonadReduce 11# 14# happyReduction_44
happyReduction_44 (happy_x_11 `HappyStk`
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
	 = happyThen (case happyOut42 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_3 of { (L _ (CmmT_String	happy_var_3)) -> 
	case happyOut32 happy_x_4 of { happy_var_4 -> 
	case happyOut36 happy_x_6 of { happy_var_6 -> 
	case happyOut22 happy_x_8 of { happy_var_8 -> 
	case happyOut23 happy_x_9 of { happy_var_9 -> 
	case happyOut19 happy_x_10 of { happy_var_10 -> 
	( foreignCall happy_var_3 happy_var_1 happy_var_4 happy_var_6 happy_var_9 happy_var_8 happy_var_10)}}}}}}}
	) (\r -> happyReturn (happyIn18 r))

happyReduce_45 = happyMonadReduce 10# 14# happyReduction_45
happyReduction_45 (happy_x_10 `HappyStk`
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
	 = happyThen (case happyOut42 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_4 of { (L _ (CmmT_Name	happy_var_4)) -> 
	case happyOut36 happy_x_6 of { happy_var_6 -> 
	case happyOut22 happy_x_8 of { happy_var_8 -> 
	case happyOut23 happy_x_9 of { happy_var_9 -> 
	( primCall happy_var_1 happy_var_4 happy_var_6 happy_var_9 happy_var_8)}}}}}
	) (\r -> happyReturn (happyIn18 r))

happyReduce_46 = happyMonadReduce 5# 14# happyReduction_46
happyReduction_46 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	case happyOut39 happy_x_3 of { happy_var_3 -> 
	( stmtMacro happy_var_1 happy_var_3)}}
	) (\r -> happyReturn (happyIn18 r))

happyReduce_47 = happyReduce 7# 14# happyReduction_47
happyReduction_47 (happy_x_7 `HappyStk`
	happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut25 happy_x_2 of { happy_var_2 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	case happyOut26 happy_x_5 of { happy_var_5 -> 
	case happyOut30 happy_x_6 of { happy_var_6 -> 
	happyIn18
		 (do as <- sequence happy_var_5; doSwitch happy_var_2 happy_var_3 as happy_var_6
	) `HappyStk` happyRest}}}}

happyReduce_48 = happySpecReduce_3  14# happyReduction_48
happyReduction_48 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn18
		 (do l <- lookupLabel happy_var_2; stmtEC (CmmBranch l)
	)}

happyReduce_49 = happyReduce 4# 14# happyReduction_49
happyReduction_49 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut32 happy_x_2 of { happy_var_2 -> 
	case happyOut35 happy_x_3 of { happy_var_3 -> 
	happyIn18
		 (do e1 <- happy_var_2; e2 <- sequence happy_var_3; stmtEC (CmmJump e1 e2)
	) `HappyStk` happyRest}}

happyReduce_50 = happySpecReduce_3  14# happyReduction_50
happyReduction_50 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut35 happy_x_2 of { happy_var_2 -> 
	happyIn18
		 (do e <- sequence happy_var_2; stmtEC (CmmReturn e)
	)}

happyReduce_51 = happyReduce 4# 14# happyReduction_51
happyReduction_51 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut20 happy_x_2 of { happy_var_2 -> 
	case happyOutTok happy_x_4 of { (L _ (CmmT_Name	happy_var_4)) -> 
	happyIn18
		 (do l <- lookupLabel happy_var_4; cmmRawIf happy_var_2 l
	) `HappyStk` happyRest}}

happyReduce_52 = happyReduce 6# 14# happyReduction_52
happyReduction_52 (happy_x_6 `HappyStk`
	happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut20 happy_x_2 of { happy_var_2 -> 
	case happyOut13 happy_x_4 of { happy_var_4 -> 
	case happyOut31 happy_x_6 of { happy_var_6 -> 
	happyIn18
		 (cmmIfThenElse happy_var_2 happy_var_4 happy_var_6
	) `HappyStk` happyRest}}}

happyReduce_53 = happySpecReduce_0  15# happyReduction_53
happyReduction_53  =  happyIn19
		 (CmmMayReturn
	)

happyReduce_54 = happySpecReduce_2  15# happyReduction_54
happyReduction_54 happy_x_2
	happy_x_1
	 =  happyIn19
		 (CmmNeverReturns
	)

happyReduce_55 = happySpecReduce_1  16# happyReduction_55
happyReduction_55 happy_x_1
	 =  case happyOut21 happy_x_1 of { happy_var_1 -> 
	happyIn20
		 (happy_var_1
	)}

happyReduce_56 = happySpecReduce_1  16# happyReduction_56
happyReduction_56 happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	happyIn20
		 (do e <- happy_var_1; return (BoolTest e)
	)}

happyReduce_57 = happySpecReduce_3  17# happyReduction_57
happyReduction_57 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut20 happy_x_1 of { happy_var_1 -> 
	case happyOut20 happy_x_3 of { happy_var_3 -> 
	happyIn21
		 (do e1 <- happy_var_1; e2 <- happy_var_3; 
					  return (BoolAnd e1 e2)
	)}}

happyReduce_58 = happySpecReduce_3  17# happyReduction_58
happyReduction_58 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut20 happy_x_1 of { happy_var_1 -> 
	case happyOut20 happy_x_3 of { happy_var_3 -> 
	happyIn21
		 (do e1 <- happy_var_1; e2 <- happy_var_3; 
					  return (BoolOr e1 e2)
	)}}

happyReduce_59 = happySpecReduce_2  17# happyReduction_59
happyReduction_59 happy_x_2
	happy_x_1
	 =  case happyOut20 happy_x_2 of { happy_var_2 -> 
	happyIn21
		 (do e <- happy_var_2; return (BoolNot e)
	)}

happyReduce_60 = happySpecReduce_3  17# happyReduction_60
happyReduction_60 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut21 happy_x_2 of { happy_var_2 -> 
	happyIn21
		 (happy_var_2
	)}

happyReduce_61 = happySpecReduce_0  18# happyReduction_61
happyReduction_61  =  happyIn22
		 (CmmUnsafe
	)

happyReduce_62 = happyMonadReduce 1# 18# happyReduction_62
happyReduction_62 (happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_String	happy_var_1)) -> 
	( parseSafety happy_var_1)}
	) (\r -> happyReturn (happyIn22 r))

happyReduce_63 = happySpecReduce_0  19# happyReduction_63
happyReduction_63  =  happyIn23
		 (Nothing
	)

happyReduce_64 = happySpecReduce_2  19# happyReduction_64
happyReduction_64 happy_x_2
	happy_x_1
	 =  happyIn23
		 (Just []
	)

happyReduce_65 = happySpecReduce_3  19# happyReduction_65
happyReduction_65 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut24 happy_x_2 of { happy_var_2 -> 
	happyIn23
		 (Just happy_var_2
	)}

happyReduce_66 = happySpecReduce_1  20# happyReduction_66
happyReduction_66 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_GlobalReg   happy_var_1)) -> 
	happyIn24
		 ([happy_var_1]
	)}

happyReduce_67 = happySpecReduce_3  20# happyReduction_67
happyReduction_67 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_GlobalReg   happy_var_1)) -> 
	case happyOut24 happy_x_3 of { happy_var_3 -> 
	happyIn24
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_68 = happyReduce 5# 21# happyReduction_68
happyReduction_68 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOutTok happy_x_2 of { (L _ (CmmT_Int		happy_var_2)) -> 
	case happyOutTok happy_x_4 of { (L _ (CmmT_Int		happy_var_4)) -> 
	happyIn25
		 (Just (fromIntegral happy_var_2, fromIntegral happy_var_4)
	) `HappyStk` happyRest}}

happyReduce_69 = happySpecReduce_0  21# happyReduction_69
happyReduction_69  =  happyIn25
		 (Nothing
	)

happyReduce_70 = happySpecReduce_0  22# happyReduction_70
happyReduction_70  =  happyIn26
		 ([]
	)

happyReduce_71 = happySpecReduce_2  22# happyReduction_71
happyReduction_71 happy_x_2
	happy_x_1
	 =  case happyOut27 happy_x_1 of { happy_var_1 -> 
	case happyOut26 happy_x_2 of { happy_var_2 -> 
	happyIn26
		 (happy_var_1 : happy_var_2
	)}}

happyReduce_72 = happyReduce 4# 23# happyReduction_72
happyReduction_72 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut29 happy_x_2 of { happy_var_2 -> 
	case happyOut28 happy_x_4 of { happy_var_4 -> 
	happyIn27
		 (do b <- happy_var_4; return (happy_var_2, b)
	) `HappyStk` happyRest}}

happyReduce_73 = happySpecReduce_3  24# happyReduction_73
happyReduction_73 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut13 happy_x_2 of { happy_var_2 -> 
	happyIn28
		 (return (Right happy_var_2)
	)}

happyReduce_74 = happySpecReduce_3  24# happyReduction_74
happyReduction_74 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn28
		 (do l <- lookupLabel happy_var_2; return (Left l)
	)}

happyReduce_75 = happySpecReduce_1  25# happyReduction_75
happyReduction_75 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Int		happy_var_1)) -> 
	happyIn29
		 ([ fromIntegral happy_var_1 ]
	)}

happyReduce_76 = happySpecReduce_3  25# happyReduction_76
happyReduction_76 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Int		happy_var_1)) -> 
	case happyOut29 happy_x_3 of { happy_var_3 -> 
	happyIn29
		 (fromIntegral happy_var_1 : happy_var_3
	)}}

happyReduce_77 = happyReduce 5# 26# happyReduction_77
happyReduction_77 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut13 happy_x_4 of { happy_var_4 -> 
	happyIn30
		 (Just happy_var_4
	) `HappyStk` happyRest}

happyReduce_78 = happySpecReduce_0  26# happyReduction_78
happyReduction_78  =  happyIn30
		 (Nothing
	)

happyReduce_79 = happySpecReduce_0  27# happyReduction_79
happyReduction_79  =  happyIn31
		 (nopEC
	)

happyReduce_80 = happyReduce 4# 27# happyReduction_80
happyReduction_80 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut13 happy_x_3 of { happy_var_3 -> 
	happyIn31
		 (happy_var_3
	) `HappyStk` happyRest}

happyReduce_81 = happySpecReduce_3  28# happyReduction_81
happyReduction_81 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_U_Quot [happy_var_1,happy_var_3]
	)}}

happyReduce_82 = happySpecReduce_3  28# happyReduction_82
happyReduction_82 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_Mul [happy_var_1,happy_var_3]
	)}}

happyReduce_83 = happySpecReduce_3  28# happyReduction_83
happyReduction_83 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_U_Rem [happy_var_1,happy_var_3]
	)}}

happyReduce_84 = happySpecReduce_3  28# happyReduction_84
happyReduction_84 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_Sub [happy_var_1,happy_var_3]
	)}}

happyReduce_85 = happySpecReduce_3  28# happyReduction_85
happyReduction_85 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_Add [happy_var_1,happy_var_3]
	)}}

happyReduce_86 = happySpecReduce_3  28# happyReduction_86
happyReduction_86 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_U_Shr [happy_var_1,happy_var_3]
	)}}

happyReduce_87 = happySpecReduce_3  28# happyReduction_87
happyReduction_87 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_Shl [happy_var_1,happy_var_3]
	)}}

happyReduce_88 = happySpecReduce_3  28# happyReduction_88
happyReduction_88 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_And [happy_var_1,happy_var_3]
	)}}

happyReduce_89 = happySpecReduce_3  28# happyReduction_89
happyReduction_89 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_Xor [happy_var_1,happy_var_3]
	)}}

happyReduce_90 = happySpecReduce_3  28# happyReduction_90
happyReduction_90 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_Or [happy_var_1,happy_var_3]
	)}}

happyReduce_91 = happySpecReduce_3  28# happyReduction_91
happyReduction_91 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_U_Ge [happy_var_1,happy_var_3]
	)}}

happyReduce_92 = happySpecReduce_3  28# happyReduction_92
happyReduction_92 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_U_Gt [happy_var_1,happy_var_3]
	)}}

happyReduce_93 = happySpecReduce_3  28# happyReduction_93
happyReduction_93 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_U_Le [happy_var_1,happy_var_3]
	)}}

happyReduce_94 = happySpecReduce_3  28# happyReduction_94
happyReduction_94 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_U_Lt [happy_var_1,happy_var_3]
	)}}

happyReduce_95 = happySpecReduce_3  28# happyReduction_95
happyReduction_95 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_Ne [happy_var_1,happy_var_3]
	)}}

happyReduce_96 = happySpecReduce_3  28# happyReduction_96
happyReduction_96 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn32
		 (mkMachOp MO_Eq [happy_var_1,happy_var_3]
	)}}

happyReduce_97 = happySpecReduce_2  28# happyReduction_97
happyReduction_97 happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_2 of { happy_var_2 -> 
	happyIn32
		 (mkMachOp MO_Not [happy_var_2]
	)}

happyReduce_98 = happySpecReduce_2  28# happyReduction_98
happyReduction_98 happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_2 of { happy_var_2 -> 
	happyIn32
		 (mkMachOp MO_S_Neg [happy_var_2]
	)}

happyReduce_99 = happyMonadReduce 5# 28# happyReduction_99
happyReduction_99 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOut33 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_3 of { (L _ (CmmT_Name	happy_var_3)) -> 
	case happyOut33 happy_x_5 of { happy_var_5 -> 
	( do { mo <- nameToMachOp happy_var_3 ;
					        return (mkMachOp mo [happy_var_1,happy_var_5]) })}}}
	) (\r -> happyReturn (happyIn32 r))

happyReduce_100 = happySpecReduce_1  28# happyReduction_100
happyReduction_100 happy_x_1
	 =  case happyOut33 happy_x_1 of { happy_var_1 -> 
	happyIn32
		 (happy_var_1
	)}

happyReduce_101 = happySpecReduce_2  29# happyReduction_101
happyReduction_101 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Int		happy_var_1)) -> 
	case happyOut34 happy_x_2 of { happy_var_2 -> 
	happyIn33
		 (return (CmmLit (CmmInt happy_var_1 (typeWidth happy_var_2)))
	)}}

happyReduce_102 = happySpecReduce_2  29# happyReduction_102
happyReduction_102 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Float	happy_var_1)) -> 
	case happyOut34 happy_x_2 of { happy_var_2 -> 
	happyIn33
		 (return (CmmLit (CmmFloat happy_var_1 (typeWidth happy_var_2)))
	)}}

happyReduce_103 = happySpecReduce_1  29# happyReduction_103
happyReduction_103 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_String	happy_var_1)) -> 
	happyIn33
		 (do s <- code (newStringCLit happy_var_1); 
				      return (CmmLit s)
	)}

happyReduce_104 = happySpecReduce_1  29# happyReduction_104
happyReduction_104 happy_x_1
	 =  case happyOut41 happy_x_1 of { happy_var_1 -> 
	happyIn33
		 (happy_var_1
	)}

happyReduce_105 = happyReduce 4# 29# happyReduction_105
happyReduction_105 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut53 happy_x_1 of { happy_var_1 -> 
	case happyOut32 happy_x_3 of { happy_var_3 -> 
	happyIn33
		 (do e <- happy_var_3; return (CmmLoad e happy_var_1)
	) `HappyStk` happyRest}}

happyReduce_106 = happyMonadReduce 5# 29# happyReduction_106
happyReduction_106 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	case happyOut39 happy_x_4 of { happy_var_4 -> 
	( exprOp happy_var_2 happy_var_4)}}
	) (\r -> happyReturn (happyIn33 r))

happyReduce_107 = happySpecReduce_3  29# happyReduction_107
happyReduction_107 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_2 of { happy_var_2 -> 
	happyIn33
		 (happy_var_2
	)}

happyReduce_108 = happySpecReduce_0  30# happyReduction_108
happyReduction_108  =  happyIn34
		 (bWord
	)

happyReduce_109 = happySpecReduce_2  30# happyReduction_109
happyReduction_109 happy_x_2
	happy_x_1
	 =  case happyOut53 happy_x_2 of { happy_var_2 -> 
	happyIn34
		 (happy_var_2
	)}

happyReduce_110 = happySpecReduce_0  31# happyReduction_110
happyReduction_110  =  happyIn35
		 ([]
	)

happyReduce_111 = happySpecReduce_3  31# happyReduction_111
happyReduction_111 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut36 happy_x_2 of { happy_var_2 -> 
	happyIn35
		 (happy_var_2
	)}

happyReduce_112 = happySpecReduce_0  32# happyReduction_112
happyReduction_112  =  happyIn36
		 ([]
	)

happyReduce_113 = happySpecReduce_1  32# happyReduction_113
happyReduction_113 happy_x_1
	 =  case happyOut37 happy_x_1 of { happy_var_1 -> 
	happyIn36
		 (happy_var_1
	)}

happyReduce_114 = happySpecReduce_1  33# happyReduction_114
happyReduction_114 happy_x_1
	 =  case happyOut38 happy_x_1 of { happy_var_1 -> 
	happyIn37
		 ([happy_var_1]
	)}

happyReduce_115 = happySpecReduce_3  33# happyReduction_115
happyReduction_115 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut38 happy_x_1 of { happy_var_1 -> 
	case happyOut37 happy_x_3 of { happy_var_3 -> 
	happyIn37
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_116 = happySpecReduce_1  34# happyReduction_116
happyReduction_116 happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	happyIn38
		 (do e <- happy_var_1; return (CmmHinted e (inferCmmHint e))
	)}

happyReduce_117 = happyMonadReduce 2# 34# happyReduction_117
happyReduction_117 (happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_2 of { (L _ (CmmT_String	happy_var_2)) -> 
	( do h <- parseCmmHint happy_var_2;
					      return $ do
						e <- happy_var_1; return (CmmHinted e h))}}
	) (\r -> happyReturn (happyIn38 r))

happyReduce_118 = happySpecReduce_0  35# happyReduction_118
happyReduction_118  =  happyIn39
		 ([]
	)

happyReduce_119 = happySpecReduce_1  35# happyReduction_119
happyReduction_119 happy_x_1
	 =  case happyOut40 happy_x_1 of { happy_var_1 -> 
	happyIn39
		 (happy_var_1
	)}

happyReduce_120 = happySpecReduce_1  36# happyReduction_120
happyReduction_120 happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	happyIn40
		 ([ happy_var_1 ]
	)}

happyReduce_121 = happySpecReduce_3  36# happyReduction_121
happyReduction_121 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut32 happy_x_1 of { happy_var_1 -> 
	case happyOut40 happy_x_3 of { happy_var_3 -> 
	happyIn40
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_122 = happySpecReduce_1  37# happyReduction_122
happyReduction_122 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn41
		 (lookupName happy_var_1
	)}

happyReduce_123 = happySpecReduce_1  37# happyReduction_123
happyReduction_123 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_GlobalReg   happy_var_1)) -> 
	happyIn41
		 (return (CmmReg (CmmGlobal happy_var_1))
	)}

happyReduce_124 = happySpecReduce_0  38# happyReduction_124
happyReduction_124  =  happyIn42
		 ([]
	)

happyReduce_125 = happyReduce 4# 38# happyReduction_125
happyReduction_125 (happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut43 happy_x_2 of { happy_var_2 -> 
	happyIn42
		 (happy_var_2
	) `HappyStk` happyRest}

happyReduce_126 = happySpecReduce_1  39# happyReduction_126
happyReduction_126 happy_x_1
	 =  case happyOut44 happy_x_1 of { happy_var_1 -> 
	happyIn43
		 ([happy_var_1]
	)}

happyReduce_127 = happySpecReduce_2  39# happyReduction_127
happyReduction_127 happy_x_2
	happy_x_1
	 =  case happyOut44 happy_x_1 of { happy_var_1 -> 
	happyIn43
		 ([happy_var_1]
	)}

happyReduce_128 = happySpecReduce_3  39# happyReduction_128
happyReduction_128 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut44 happy_x_1 of { happy_var_1 -> 
	case happyOut43 happy_x_3 of { happy_var_3 -> 
	happyIn43
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_129 = happySpecReduce_1  40# happyReduction_129
happyReduction_129 happy_x_1
	 =  case happyOut45 happy_x_1 of { happy_var_1 -> 
	happyIn44
		 (do e <- happy_var_1; return (CmmHinted e (inferCmmHint (CmmReg (CmmLocal e))))
	)}

happyReduce_130 = happyMonadReduce 2# 40# happyReduction_130
happyReduction_130 (happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest) tk
	 = happyThen (case happyOutTok happy_x_1 of { (L _ (CmmT_String	happy_var_1)) -> 
	case happyOut45 happy_x_2 of { happy_var_2 -> 
	( do h <- parseCmmHint happy_var_1;
					      return $ do
						e <- happy_var_2; return (CmmHinted e h))}}
	) (\r -> happyReturn (happyIn44 r))

happyReduce_131 = happySpecReduce_1  41# happyReduction_131
happyReduction_131 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn45
		 (do e <- lookupName happy_var_1;
				     return $
				       case e of 
					CmmReg (CmmLocal r) -> r
					other -> pprPanic "CmmParse:" (ftext happy_var_1 <> text " not a local register")
	)}

happyReduce_132 = happySpecReduce_1  42# happyReduction_132
happyReduction_132 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_Name	happy_var_1)) -> 
	happyIn46
		 (do e <- lookupName happy_var_1;
				     return $
				       case e of 
					CmmReg r -> r
					other -> pprPanic "CmmParse:" (ftext happy_var_1 <> text " not a register")
	)}

happyReduce_133 = happySpecReduce_1  42# happyReduction_133
happyReduction_133 happy_x_1
	 =  case happyOutTok happy_x_1 of { (L _ (CmmT_GlobalReg   happy_var_1)) -> 
	happyIn46
		 (return (CmmGlobal happy_var_1)
	)}

happyReduce_134 = happySpecReduce_0  43# happyReduction_134
happyReduction_134  =  happyIn47
		 ([]
	)

happyReduce_135 = happySpecReduce_3  43# happyReduction_135
happyReduction_135 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut48 happy_x_2 of { happy_var_2 -> 
	happyIn47
		 (happy_var_2
	)}

happyReduce_136 = happySpecReduce_0  44# happyReduction_136
happyReduction_136  =  happyIn48
		 ([]
	)

happyReduce_137 = happySpecReduce_1  44# happyReduction_137
happyReduction_137 happy_x_1
	 =  case happyOut49 happy_x_1 of { happy_var_1 -> 
	happyIn48
		 (happy_var_1
	)}

happyReduce_138 = happySpecReduce_2  45# happyReduction_138
happyReduction_138 happy_x_2
	happy_x_1
	 =  case happyOut50 happy_x_1 of { happy_var_1 -> 
	happyIn49
		 ([happy_var_1]
	)}

happyReduce_139 = happySpecReduce_1  45# happyReduction_139
happyReduction_139 happy_x_1
	 =  case happyOut50 happy_x_1 of { happy_var_1 -> 
	happyIn49
		 ([happy_var_1]
	)}

happyReduce_140 = happySpecReduce_3  45# happyReduction_140
happyReduction_140 happy_x_3
	happy_x_2
	happy_x_1
	 =  case happyOut50 happy_x_1 of { happy_var_1 -> 
	case happyOut49 happy_x_3 of { happy_var_3 -> 
	happyIn49
		 (happy_var_1 : happy_var_3
	)}}

happyReduce_141 = happySpecReduce_2  46# happyReduction_141
happyReduction_141 happy_x_2
	happy_x_1
	 =  case happyOut53 happy_x_1 of { happy_var_1 -> 
	case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn50
		 (newLocal happy_var_1 happy_var_2
	)}}

happyReduce_142 = happySpecReduce_0  47# happyReduction_142
happyReduction_142  =  happyIn51
		 (return Nothing
	)

happyReduce_143 = happyReduce 5# 47# happyReduction_143
happyReduction_143 (happy_x_5 `HappyStk`
	happy_x_4 `HappyStk`
	happy_x_3 `HappyStk`
	happy_x_2 `HappyStk`
	happy_x_1 `HappyStk`
	happyRest)
	 = case happyOut32 happy_x_2 of { happy_var_2 -> 
	case happyOut39 happy_x_4 of { happy_var_4 -> 
	happyIn51
		 (do { target <- happy_var_2;
					       args <- sequence happy_var_4;
					       return $ Just (UpdateFrame target args) }
	) `HappyStk` happyRest}}

happyReduce_144 = happySpecReduce_0  48# happyReduction_144
happyReduction_144  =  happyIn52
		 (return Nothing
	)

happyReduce_145 = happySpecReduce_2  48# happyReduction_145
happyReduction_145 happy_x_2
	happy_x_1
	 =  case happyOutTok happy_x_2 of { (L _ (CmmT_Name	happy_var_2)) -> 
	happyIn52
		 (do l <- lookupLabel happy_var_2; return (Just l)
	)}

happyReduce_146 = happySpecReduce_1  49# happyReduction_146
happyReduction_146 happy_x_1
	 =  happyIn53
		 (b8
	)

happyReduce_147 = happySpecReduce_1  49# happyReduction_147
happyReduction_147 happy_x_1
	 =  case happyOut54 happy_x_1 of { happy_var_1 -> 
	happyIn53
		 (happy_var_1
	)}

happyReduce_148 = happySpecReduce_1  50# happyReduction_148
happyReduction_148 happy_x_1
	 =  happyIn54
		 (b16
	)

happyReduce_149 = happySpecReduce_1  50# happyReduction_149
happyReduction_149 happy_x_1
	 =  happyIn54
		 (b32
	)

happyReduce_150 = happySpecReduce_1  50# happyReduction_150
happyReduction_150 happy_x_1
	 =  happyIn54
		 (b64
	)

happyReduce_151 = happySpecReduce_1  50# happyReduction_151
happyReduction_151 happy_x_1
	 =  happyIn54
		 (f32
	)

happyReduce_152 = happySpecReduce_1  50# happyReduction_152
happyReduction_152 happy_x_1
	 =  happyIn54
		 (f64
	)

happyReduce_153 = happySpecReduce_1  50# happyReduction_153
happyReduction_153 happy_x_1
	 =  happyIn54
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

        ( "and",        MO_And ),
	( "or",		MO_Or ),
	( "xor",	MO_Xor ),
	( "com",	MO_Not ),
	( "shl",	MO_Shl ),
	( "shrl",	MO_U_Shr ),
	( "shra",	MO_S_Shr ),

        ( "fadd",       MO_F_Add ),
        ( "fsub",       MO_F_Sub ),
        ( "fneg",       MO_F_Neg ),
        ( "fmul",       MO_F_Mul ),
        ( "fquot",      MO_F_Quot ),

        ( "feq",        MO_F_Eq ),
        ( "fne",        MO_F_Ne ),
        ( "fge",        MO_F_Ge ),
        ( "fle",        MO_F_Le ),
        ( "fgt",        MO_F_Gt ),
        ( "flt",        MO_F_Lt ),

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
        ( "write_barrier", MO_WriteBarrier ),
        ( "memcpy", MO_Memcpy ),
        ( "memset", MO_Memset ),
        ( "memmove", MO_Memmove )
        -- ToDo: the rest, maybe
    ]

parseSafety :: String -> P CmmSafety
parseSafety "safe"   = return (CmmSafe NoC_SRT)
parseSafety "unsafe" = return CmmUnsafe
parseSafety "interruptible" = return CmmInterruptible
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
isPtrGlobalReg CCCS                  = True
isPtrGlobalReg CurrentTSO            = True
isPtrGlobalReg CurrentNursery        = True
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


profilingInfo desc_str ty_str 
  | not opt_SccProfilingOn = NoProfilingInfo
  | otherwise              = ProfilingInfo (stringToWord8s desc_str)
                                           (stringToWord8s ty_str)

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
          case convention of
            -- Temporary hack so at least some functions are CmmSafe
            CmmCallConv -> code (stmtC (CmmCall (CmmCallee expr convention) results args ret))
            _ ->
              let expr' = adjCallTarget convention expr args in
              case safety of
	      CmmUnsafe ->
                code (emitForeignCall' PlayRisky results 
                   (CmmCallee expr' convention) args vols NoC_SRT ret)
              CmmSafe srt ->
                code (emitForeignCall' PlaySafe results 
                   (CmmCallee expr' convention) args vols NoC_SRT ret) where
              CmmInterruptible ->
                code (emitForeignCall' PlayInterruptible results 
                   (CmmCallee expr' convention) args vols NoC_SRT ret)

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
		    code (emitForeignCall' PlaySafe results 
		      (CmmPrim p) args vols NoC_SRT CmmMayReturn) where
		  CmmInterruptible ->
		    code (emitForeignCall' PlayInterruptible results 
		      (CmmPrim p) args vols NoC_SRT CmmMayReturn)

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

cmmRawIf cond then_id = do
    c <- cond
    emitCond c then_id

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

doSwitch :: Maybe (Int,Int) -> ExtFCode CmmExpr -> [([Int],Either BlockId ExtCode)]
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
	emitArm :: ([Int],Either BlockId ExtCode) -> ExtFCode [(Int,BlockId)]
	emitArm (ints,Left blockid) = return [ (i,blockid) | i <- ints ]
	emitArm (ints,Right code) = do
	   blockid <- forkLabelledCodeEC code
	   return [ (i,blockid) | i <- ints ]

-- -----------------------------------------------------------------------------
-- Putting it all together

-- The initial environment: we define some constants that the compiler
-- knows about here.
initEnv :: Env
initEnv = listToUFM [
  ( fsLit "SIZEOF_StgHeader", 
    VarN (CmmLit (CmmInt (fromIntegral (fixedHdrSize * wORD_SIZE)) wordWidth) )),
  ( fsLit "SIZEOF_StgInfoTable",
    VarN (CmmLit (CmmInt (fromIntegral stdInfoTableSizeB) wordWidth) ))
  ]

parseCmmFile :: DynFlags -> FilePath -> IO (Messages, Maybe CmmGroup)
parseCmmFile dflags filename = do
  showPass dflags "ParseCmm"
  buf <- hGetStringBuffer filename
  let
	init_loc = mkRealSrcLoc (mkFastString filename) 1 1
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
           dumpIfSet_dyn dflags Opt_D_dump_cmm "Cmm" (pprPlatform (targetPlatform dflags) cmm)
           return (ms, Just cmm)
  where
	no_module = panic "parseCmmFile: no module"
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
