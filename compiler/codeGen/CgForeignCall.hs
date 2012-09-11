-----------------------------------------------------------------------------
--
-- Code generation for foreign calls.
--
-- (c) The University of Glasgow 2004-2006
--
-----------------------------------------------------------------------------

module CgForeignCall (
  cgForeignCall,
  emitForeignCall,
  emitForeignCall',
  shimForeignCallArg,
  emitSaveThreadState, -- will be needed by the Cmm parser
  emitLoadThreadState, -- ditto
  emitCloseNursery,
  emitOpenNursery,
 ) where

import StgSyn
import CgProf
import CgBindery
import CgMonad
import CgUtils
import Type
import TysPrim
import CLabel
import Cmm
import CmmUtils
import SMRep
import ForeignCall
import ClosureInfo
import Constants
import StaticFlags
import Outputable
import FastString
import BasicTypes

import Control.Monad

-- -----------------------------------------------------------------------------
-- Code generation for Foreign Calls

cgForeignCall
	:: HintedCmmFormals	-- where to put the results
	-> ForeignCall		-- the op
	-> [StgArg]		-- arguments
	-> StgLiveVars	-- live vars, in case we need to save them
	-> Code
cgForeignCall results fcall stg_args live
  = do 
  reps_n_amodes <- getArgAmodes stg_args
  let
	-- Get the *non-void* args, and jiggle them with shimForeignCall
	arg_exprs = [ shimForeignCallArg stg_arg expr 
	  	    | (stg_arg, (rep,expr)) <- stg_args `zip` reps_n_amodes, 
	               nonVoidArg rep]

	arg_hints = zipWith CmmHinted
                      arg_exprs (map (typeForeignHint.stgArgType) stg_args)
  -- in
  emitForeignCall results fcall arg_hints live


emitForeignCall
	:: HintedCmmFormals	-- where to put the results
	-> ForeignCall		-- the op
	-> [CmmHinted CmmExpr] -- arguments
	-> StgLiveVars	-- live vars, in case we need to save them
	-> Code

emitForeignCall results (CCall (CCallSpec target cconv safety)) args live
  = do vols <- getVolatileRegs live
       srt <- getSRTInfo
       emitForeignCall' safety results
         (CmmCallee cmm_target cconv) call_args (Just vols) srt CmmMayReturn
  where
      (call_args, cmm_target)
	= case target of
	   StaticTarget lbl -> (args, CmmLit (CmmLabel 
					(mkForeignLabel lbl call_size False IsFunction)))
	   DynamicTarget    ->  case args of
	                        (CmmHinted fn _):rest -> (rest, fn)
	                        [] -> panic "emitForeignCall: DynamicTarget []"

	-- in the stdcall calling convention, the symbol needs @size appended
	-- to it, where size is the total number of bytes of arguments.  We
	-- attach this info to the CLabel here, and the CLabel pretty printer
	-- will generate the suffix when the label is printed.
      call_size
	| StdCallConv <- cconv = Just (sum (map (arg_size.cmmExprType.hintlessCmm) args))
	| otherwise            = Nothing

	-- ToDo: this might not be correct for 64-bit API
      arg_size rep = max (widthInBytes (typeWidth rep)) wORD_SIZE


-- alternative entry point, used by CmmParse
emitForeignCall'
	:: Safety
	-> HintedCmmFormals	-- where to put the results
	-> CmmCallTarget	-- the op
	-> [CmmHinted CmmExpr] -- arguments
	-> Maybe [GlobalReg]	-- live vars, in case we need to save them
        -> C_SRT                -- the SRT of the calls continuation
        -> CmmReturnInfo
	-> Code
emitForeignCall' safety results target args vols _srt ret
  | not (playSafe safety) = do
    temp_args <- load_args_into_temps args
    let (caller_save, caller_load) = callerSaveVolatileRegs vols
    stmtsC caller_save
    stmtC (CmmCall target results temp_args CmmUnsafe ret)
    stmtsC caller_load

  | otherwise = do
    -- Both 'id' and 'new_base' are GCKindNonPtr because they're
    -- RTS only objects and are not subject to garbage collection
    id <- newTemp bWord
    new_base <- newTemp (cmmRegType (CmmGlobal BaseReg))
    temp_args <- load_args_into_temps args
    temp_target <- load_target_into_temp target
    let (caller_save, caller_load) = callerSaveVolatileRegs vols
    emitSaveThreadState
    stmtsC caller_save
    -- The CmmUnsafe arguments are only correct because this part
    -- of the code hasn't been moved into the CPS pass yet.
    -- Once that happens, this function will just emit a (CmmSafe srt) call,
    -- and the CPS will be the one to convert that
    -- to this sequence of three CmmUnsafe calls.
    stmtC (CmmCall (CmmCallee suspendThread CCallConv) 
			[ CmmHinted id AddrHint ]
			[ CmmHinted (CmmReg (CmmGlobal BaseReg)) AddrHint ] 
			CmmUnsafe ret)
    stmtC (CmmCall temp_target results temp_args CmmUnsafe ret)
    stmtC (CmmCall (CmmCallee resumeThread CCallConv) 
			[ CmmHinted new_base AddrHint ]
			[ CmmHinted (CmmReg (CmmLocal id)) AddrHint ]
			CmmUnsafe ret)
    -- Assign the result to BaseReg: we
    -- might now have a different Capability!
    stmtC (CmmAssign (CmmGlobal BaseReg) (CmmReg (CmmLocal new_base)))
    stmtsC caller_load
    emitLoadThreadState

suspendThread, resumeThread :: CmmExpr
suspendThread = CmmLit (CmmLabel (mkRtsCodeLabel (sLit "suspendThread")))
resumeThread  = CmmLit (CmmLabel (mkRtsCodeLabel (sLit "resumeThread")))


-- we might need to load arguments into temporaries before
-- making the call, because certain global registers might
-- overlap with registers that the C calling convention uses
-- for passing arguments.
--
-- This is a HACK; really it should be done in the back end, but
-- it's easier to generate the temporaries here.
load_args_into_temps :: [CmmHinted CmmExpr] -> FCode [CmmHinted CmmExpr]
load_args_into_temps = mapM arg_assign_temp
  where arg_assign_temp (CmmHinted e hint) = do
	   tmp <- maybe_assign_temp e
	   return (CmmHinted tmp hint)
	
load_target_into_temp :: CmmCallTarget -> FCode CmmCallTarget
load_target_into_temp (CmmCallee expr conv) = do 
  tmp <- maybe_assign_temp expr
  return (CmmCallee tmp conv)
load_target_into_temp other_target =
  return other_target

maybe_assign_temp :: CmmExpr -> FCode CmmExpr
maybe_assign_temp e
  | hasNoGlobalRegs e = return e
  | otherwise          = do 
	-- don't use assignTemp, it uses its own notion of "trivial"
	-- expressions, which are wrong here.
        -- this is a NonPtr because it only duplicates an existing
	reg <- newTemp (cmmExprType e) --TODO FIXME NOW
	stmtC (CmmAssign (CmmLocal reg) e)
	return (CmmReg (CmmLocal reg))

-- -----------------------------------------------------------------------------
-- Save/restore the thread state in the TSO

-- This stuff can't be done in suspendThread/resumeThread, because it
-- refers to global registers which aren't available in the C world.

emitSaveThreadState :: Code
emitSaveThreadState = do
  -- CurrentTSO->sp = Sp;
  stmtC $ CmmStore (cmmOffset stgCurrentTSO tso_SP) stgSp
  emitCloseNursery
  -- and save the current cost centre stack in the TSO when profiling:
  when opt_SccProfilingOn $
	stmtC (CmmStore (cmmOffset stgCurrentTSO tso_CCCS) curCCS)

   -- CurrentNursery->free = Hp+1;
emitCloseNursery :: Code
emitCloseNursery = stmtC $ CmmStore nursery_bdescr_free (cmmOffsetW stgHp 1)

emitLoadThreadState :: Code
emitLoadThreadState = do
  tso <- newTemp bWord -- TODO FIXME NOW
  stmtsC [
	-- tso = CurrentTSO;
  	CmmAssign (CmmLocal tso) stgCurrentTSO,
	-- Sp = tso->sp;
	CmmAssign sp (CmmLoad (cmmOffset (CmmReg (CmmLocal tso)) tso_SP)
	                      bWord),
	-- SpLim = tso->stack + RESERVED_STACK_WORDS;
	CmmAssign spLim (cmmOffsetW (cmmOffset (CmmReg (CmmLocal tso)) tso_STACK)
			            rESERVED_STACK_WORDS),
        -- HpAlloc = 0;
        --   HpAlloc is assumed to be set to non-zero only by a failed
        --   a heap check, see HeapStackCheck.cmm:GC_GENERIC
        CmmAssign hpAlloc (CmmLit zeroCLit)
    ]
  emitOpenNursery
  -- and load the current cost centre stack from the TSO when profiling:
  when opt_SccProfilingOn $
	stmtC (CmmStore curCCSAddr 
		(CmmLoad (cmmOffset (CmmReg (CmmLocal tso)) tso_CCCS) bWord))

emitOpenNursery :: Code
emitOpenNursery = stmtsC [
        -- Hp = CurrentNursery->free - 1;
	CmmAssign hp (cmmOffsetW (CmmLoad nursery_bdescr_free gcWord) (-1)),

        -- HpLim = CurrentNursery->start + 
	--		CurrentNursery->blocks*BLOCK_SIZE_W - 1;
	CmmAssign hpLim
	    (cmmOffsetExpr
		(CmmLoad nursery_bdescr_start bWord)
		(cmmOffset
		  (CmmMachOp mo_wordMul [
		    CmmMachOp (MO_SS_Conv W32 wordWidth)
		      [CmmLoad nursery_bdescr_blocks b32],
		    CmmLit (mkIntCLit bLOCK_SIZE)
		   ])
		  (-1)
		)
	    )
   ]

nursery_bdescr_free, nursery_bdescr_start, nursery_bdescr_blocks :: CmmExpr
nursery_bdescr_free   = cmmOffset stgCurrentNursery oFFSET_bdescr_free
nursery_bdescr_start  = cmmOffset stgCurrentNursery oFFSET_bdescr_start
nursery_bdescr_blocks = cmmOffset stgCurrentNursery oFFSET_bdescr_blocks

tso_SP, tso_STACK, tso_CCCS :: ByteOff
tso_SP    = tsoFieldB     oFFSET_StgTSO_sp
tso_STACK = tsoFieldB     oFFSET_StgTSO_stack
tso_CCCS  = tsoProfFieldB oFFSET_StgTSO_CCCS

-- The TSO struct has a variable header, and an optional StgTSOProfInfo in
-- the middle.  The fields we're interested in are after the StgTSOProfInfo.
tsoFieldB :: ByteOff -> ByteOff
tsoFieldB off
  | opt_SccProfilingOn = off + sIZEOF_StgTSOProfInfo + fixedHdrSize * wORD_SIZE
  | otherwise          = off + fixedHdrSize * wORD_SIZE

tsoProfFieldB :: ByteOff -> ByteOff
tsoProfFieldB off = off + fixedHdrSize * wORD_SIZE

stgSp, stgHp, stgCurrentTSO, stgCurrentNursery :: CmmExpr
stgSp		  = CmmReg sp
stgHp		  = CmmReg hp
stgCurrentTSO	  = CmmReg currentTSO
stgCurrentNursery = CmmReg currentNursery

sp, spLim, hp, hpLim, currentTSO, currentNursery, hpAlloc :: CmmReg
sp		  = CmmGlobal Sp
spLim		  = CmmGlobal SpLim
hp		  = CmmGlobal Hp
hpLim		  = CmmGlobal HpLim
currentTSO	  = CmmGlobal CurrentTSO
currentNursery 	  = CmmGlobal CurrentNursery
hpAlloc 	  = CmmGlobal HpAlloc

-- -----------------------------------------------------------------------------
-- For certain types passed to foreign calls, we adjust the actual
-- value passed to the call.  For ByteArray#/Array# we pass the
-- address of the actual array, not the address of the heap object.

shimForeignCallArg :: StgArg -> CmmExpr -> CmmExpr
shimForeignCallArg arg expr
  | tycon == arrayPrimTyCon || tycon == mutableArrayPrimTyCon
	= cmmOffsetB expr arrPtrsHdrSize

  | tycon == byteArrayPrimTyCon || tycon == mutableByteArrayPrimTyCon
	= cmmOffsetB expr arrWordsHdrSize

  | otherwise = expr
  where	
	-- should be a tycon app, since this is a foreign call
	tycon = tyConAppTyCon (repType (stgArgType arg))
