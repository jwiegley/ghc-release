-----------------------------------------------------------------------------
--
-- Cmm data types
--
-- (c) The University of Glasgow 2004-2006
--
-----------------------------------------------------------------------------

module Cmm ( 
	GenCmm(..), Cmm, RawCmm,
	GenCmmTop(..), CmmTop, RawCmmTop,
	ListGraph(..),
        cmmMapGraph, cmmTopMapGraph,
        cmmMapGraphM, cmmTopMapGraphM,
	CmmInfo(..), UpdateFrame(..),
        CmmInfoTable(..), ClosureTypeInfo(..), ProfilingInfo(..), ClosureTypeTag,
        GenBasicBlock(..), CmmBasicBlock, blockId, blockStmts, mapBlockStmts,
        CmmReturnInfo(..),
	CmmStmt(..), CmmActual, CmmActuals, CmmFormal, CmmFormals, CmmKind,
        CmmFormalsWithoutKinds, CmmFormalWithoutKind,
        CmmKinded(..),
        CmmSafety(..),
	CmmCallTarget(..),
	CmmStatic(..), Section(..),
        module CmmExpr,
  ) where

#include "HsVersions.h"

import BlockId
import CmmExpr
import MachOp
import CLabel
import ForeignCall
import SMRep
import ClosureInfo
import Outputable
import FastString

import Data.Word


-- A [[BlockId]] is a local label.
-- Local labels must be unique within an entire compilation unit, not
-- just a single top-level item, because local labels map one-to-one
-- with assembly-language labels.

-----------------------------------------------------------------------------
--		Cmm, CmmTop, CmmBasicBlock
-----------------------------------------------------------------------------

-- A file is a list of top-level chunks.  These may be arbitrarily
-- re-orderd during code generation.

-- GenCmm is abstracted over
--   d, the type of static data elements in CmmData
--   h, the static info preceding the code of a CmmProc
--   g, the control-flow graph of a CmmProc
--
-- We expect there to be two main instances of this type:
--   (a) C--, i.e. populated with various C-- constructs
--		(Cmm and RawCmm below)
--   (b) Native code, populated with data/instructions
--
-- A second family of instances based on ZipCfg is work in progress.
--
newtype GenCmm d h g = Cmm [GenCmmTop d h g]

-- | A top-level chunk, abstracted over the type of the contents of
-- the basic blocks (Cmm or instructions are the likely instantiations).
data GenCmmTop d h g
  = CmmProc	-- A procedure
     h	               -- Extra header such as the info table
     CLabel            -- Used to generate both info & entry labels
     CmmFormalsWithoutKinds -- Argument locals live on entry (C-- procedure params)
                       -- XXX Odd that there are no kinds, but there you are ---NR
     g                 -- Control-flow graph for the procedure's code

  | CmmData 	-- Static data
	Section 
	[d]

-- | A control-flow graph represented as a list of extended basic blocks.
newtype ListGraph i = ListGraph [GenBasicBlock i] 
   -- ^ Code, may be empty.  The first block is the entry point.  The
   -- order is otherwise initially unimportant, but at some point the
   -- code gen will fix the order.

   -- BlockIds must be unique across an entire compilation unit, since
   -- they are translated to assembly-language labels, which scope
   -- across a whole compilation unit.

-- | Cmm with the info table as a data type
type Cmm    = GenCmm    CmmStatic CmmInfo (ListGraph CmmStmt)
type CmmTop = GenCmmTop CmmStatic CmmInfo (ListGraph CmmStmt)

-- | Cmm with the info tables converted to a list of 'CmmStatic'
type RawCmm    = GenCmm    CmmStatic [CmmStatic] (ListGraph CmmStmt)
type RawCmmTop = GenCmmTop CmmStatic [CmmStatic] (ListGraph CmmStmt)


-- A basic block containing a single label, at the beginning.
-- The list of basic blocks in a top-level code block may be re-ordered.
-- Fall-through is not allowed: there must be an explicit jump at the
-- end of each basic block, but the code generator might rearrange basic
-- blocks in order to turn some jumps into fallthroughs.

data GenBasicBlock i = BasicBlock BlockId [i]
type CmmBasicBlock   = GenBasicBlock CmmStmt

instance UserOfLocalRegs i => UserOfLocalRegs (GenBasicBlock i) where
    foldRegsUsed f set (BasicBlock _ l) = foldRegsUsed f set l

blockId :: GenBasicBlock i -> BlockId
-- The branch block id is that of the first block in 
-- the branch, which is that branch's entry point
blockId (BasicBlock blk_id _ ) = blk_id

blockStmts :: GenBasicBlock i -> [i]
blockStmts (BasicBlock _ stmts) = stmts


mapBlockStmts :: (i -> i') -> GenBasicBlock i -> GenBasicBlock i'
mapBlockStmts f (BasicBlock id bs) = BasicBlock id (map f bs)
----------------------------------------------------------------
--   graph maps
----------------------------------------------------------------

cmmMapGraph    :: (g -> g') -> GenCmm    d h g -> GenCmm    d h g'
cmmTopMapGraph :: (g -> g') -> GenCmmTop d h g -> GenCmmTop d h g'

cmmMapGraphM    :: Monad m => (String -> g -> m g') -> GenCmm    d h g -> m (GenCmm    d h g')
cmmTopMapGraphM :: Monad m => (String -> g -> m g') -> GenCmmTop d h g -> m (GenCmmTop d h g')

cmmMapGraph f (Cmm tops) = Cmm $ map (cmmTopMapGraph f) tops
cmmTopMapGraph f (CmmProc h l args g) = CmmProc h l args (f g)
cmmTopMapGraph _ (CmmData s ds)       = CmmData s ds

cmmMapGraphM f (Cmm tops) = mapM (cmmTopMapGraphM f) tops >>= return . Cmm
cmmTopMapGraphM f (CmmProc h l args g) = f (showSDoc $ ppr l) g >>= return . CmmProc h l args
cmmTopMapGraphM _ (CmmData s ds)       = return $ CmmData s ds

-----------------------------------------------------------------------------
--     Info Tables
-----------------------------------------------------------------------------

data CmmInfo
  = CmmInfo
      (Maybe BlockId)     -- GC target. Nothing <=> CPS won't do stack check
      (Maybe UpdateFrame) -- Update frame
      CmmInfoTable        -- Info table

-- Info table as a haskell data type
data CmmInfoTable
  = CmmInfoTable
      ProfilingInfo
      ClosureTypeTag -- Int
      ClosureTypeInfo
  | CmmNonInfoTable   -- Procedure doesn't need an info table

-- TODO: The GC target shouldn't really be part of CmmInfo
-- as it doesn't appear in the resulting info table.
-- It should be factored out.

data ClosureTypeInfo
  = ConstrInfo ClosureLayout ConstrTag ConstrDescription
  | FunInfo ClosureLayout C_SRT FunType FunArity ArgDescr SlowEntry
  | ThunkInfo ClosureLayout C_SRT
  | ThunkSelectorInfo SelectorOffset C_SRT
  | ContInfo
      [Maybe LocalReg]  -- Forced stack parameters
      C_SRT

data CmmReturnInfo = CmmMayReturn
                   | CmmNeverReturns

-- TODO: These types may need refinement
data ProfilingInfo = ProfilingInfo CmmLit CmmLit -- closure_type, closure_desc
type ClosureTypeTag = StgHalfWord
type ClosureLayout = (StgHalfWord, StgHalfWord) -- ptrs, nptrs
type ConstrTag = StgHalfWord
type ConstrDescription = CmmLit
type FunType = StgHalfWord
type FunArity = StgHalfWord
type SlowEntry = CmmLit
  -- We would like this to be a CLabel but
  -- for now the parser sets this to zero on an INFO_TABLE_FUN.
type SelectorOffset = StgWord

-- | A frame that is to be pushed before entry to the function.
-- Used to handle 'update' frames.
data UpdateFrame =
    UpdateFrame
      CmmExpr    -- Frame header.  Behaves like the target of a 'jump'.
      [CmmExpr]  -- Frame remainder.  Behaves like the arguments of a 'jump'.

-----------------------------------------------------------------------------
--		CmmStmt
-- A "statement".  Note that all branches are explicit: there are no
-- control transfers to computed addresses, except when transfering
-- control to a new function.
-----------------------------------------------------------------------------

data CmmStmt
  = CmmNop
  | CmmComment FastString

  | CmmAssign CmmReg CmmExpr	 -- Assign to register

  | CmmStore CmmExpr CmmExpr     -- Assign to memory location.  Size is
                                 -- given by cmmExprRep of the rhs.

  | CmmCall	 		 -- A call (forign, native or primitive), with 
     CmmCallTarget
     CmmFormals		 -- zero or more results
     CmmActuals			 -- zero or more arguments
     CmmSafety			 -- whether to build a continuation
     CmmReturnInfo

  | CmmBranch BlockId             -- branch to another BB in this fn

  | CmmCondBranch CmmExpr BlockId -- conditional branch

  | CmmSwitch CmmExpr [Maybe BlockId]   -- Table branch
	-- The scrutinee is zero-based; 
	--	zero -> first block
	--	one  -> second block etc
	-- Undefined outside range, and when there's a Nothing

  | CmmJump CmmExpr      -- Jump to another C-- function,
      CmmActuals         -- with these parameters.

  | CmmReturn            -- Return from a native C-- function,
      CmmActuals         -- with these return values.

type CmmKind   = MachHint
data CmmKinded a = CmmKinded { kindlessCmm :: a, cmmKind :: CmmKind }
                         deriving (Eq)
type CmmActual = CmmKinded CmmExpr
type CmmFormal = CmmKinded LocalReg
type CmmActuals = [CmmActual]
type CmmFormals = [CmmFormal]
type CmmFormalWithoutKind   = LocalReg
type CmmFormalsWithoutKinds = [CmmFormalWithoutKind]

data CmmSafety      = CmmUnsafe | CmmSafe C_SRT

-- | enable us to fold used registers over 'CmmActuals' and 'CmmFormals'
instance UserOfLocalRegs a => UserOfLocalRegs (CmmKinded a) where
  foldRegsUsed f set (CmmKinded a _) = foldRegsUsed f set a

instance UserOfLocalRegs CmmStmt where
  foldRegsUsed f set s = stmt s set
    where stmt (CmmNop)                  = id
          stmt (CmmComment {})           = id
          stmt (CmmAssign _ e)           = gen e
          stmt (CmmStore e1 e2)          = gen e1 . gen e2
          stmt (CmmCall target _ es _ _) = gen target . gen es
          stmt (CmmBranch _)             = id
          stmt (CmmCondBranch e _)       = gen e
          stmt (CmmSwitch e _)           = gen e
          stmt (CmmJump e es)            = gen e . gen es
          stmt (CmmReturn es)            = gen es
          gen a set = foldRegsUsed f set a

instance UserOfLocalRegs CmmCallTarget where
    foldRegsUsed f set (CmmCallee e _) = foldRegsUsed f set e
    foldRegsUsed _ set (CmmPrim {})    = set

instance DefinerOfLocalRegs a => DefinerOfLocalRegs (CmmKinded a) where
  foldRegsDefd f z (CmmKinded x _) = foldRegsDefd f z x

--just look like a tuple, since it was a tuple before
-- ... is that a good idea? --Isaac Dupree
instance (Outputable a) => Outputable (CmmKinded a) where
  ppr (CmmKinded a k) = ppr (a, k)

{-
Discussion
~~~~~~~~~~

One possible problem with the above type is that the only way to do a
non-local conditional jump is to encode it as a branch to a block that
contains a single jump.  This leads to inefficient code in the back end.

[N.B. This problem will go away when we make the transition to the
'zipper' form of control-flow graph, in which both targets of a
conditional jump are explicit. ---NR]

One possible way to fix this would be:

data CmmStat = 
  ...
  | CmmJump CmmBranchDest
  | CmmCondJump CmmExpr CmmBranchDest
  ...

data CmmBranchDest
  = Local BlockId
  | NonLocal CmmExpr [LocalReg]

In favour:

+ one fewer constructors in CmmStmt
+ allows both cond branch and switch to jump to non-local destinations

Against:

- not strictly necessary: can already encode as branch+jump
- not always possible to implement any better in the back end
- could do the optimisation in the back end (but then plat-specific?)
- C-- doesn't have it
- back-end optimisation might be more general (jump shortcutting)

So we'll stick with the way it is, and add the optimisation to the NCG.
-}

-----------------------------------------------------------------------------
--		CmmCallTarget
--
-- The target of a CmmCall.
-----------------------------------------------------------------------------

data CmmCallTarget
  = CmmCallee		-- Call a function (foreign or native)
	CmmExpr 		-- literal label <=> static call
				-- other expression <=> dynamic call
	CCallConv		-- The calling convention

  | CmmPrim		-- Call a "primitive" (eg. sin, cos)
	CallishMachOp		-- These might be implemented as inline
				-- code by the backend.
  deriving Eq

-----------------------------------------------------------------------------
--		Static Data
-----------------------------------------------------------------------------

data Section
  = Text
  | Data
  | ReadOnlyData
  | RelocatableReadOnlyData
  | UninitialisedData
  | ReadOnlyData16	-- .rodata.cst16 on x86_64, 16-byte aligned
  | OtherSection String

data CmmStatic
  = CmmStaticLit CmmLit	
	-- a literal value, size given by cmmLitRep of the literal.
  | CmmUninitialised Int
	-- uninitialised data, N bytes long
  | CmmAlign Int
	-- align to next N-byte boundary (N must be a power of 2).
  | CmmDataLabel CLabel
	-- label the current position in this section.
  | CmmString [Word8]
	-- string of 8-bit values only, not zero terminated.

