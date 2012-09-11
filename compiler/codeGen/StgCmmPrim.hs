-----------------------------------------------------------------------------
--
-- Stg to C--: primitive operations
--
-- (c) The University of Glasgow 2004-2006
--
-----------------------------------------------------------------------------

module StgCmmPrim (
   cgOpApp
 ) where

#include "HsVersions.h"

import StgCmmLayout
import StgCmmForeign
import StgCmmEnv
import StgCmmMonad
import StgCmmUtils

import MkZipCfgCmm
import StgSyn
import Cmm
import Type	( Type, tyConAppTyCon )
import TyCon
import CLabel
import CmmUtils
import PrimOp
import SMRep
import Constants
import Module
import FastString
import Outputable

------------------------------------------------------------------------
--	Primitive operations and foreign calls
------------------------------------------------------------------------

{- Note [Foreign call results]
   ~~~~~~~~~~~~~~~~~~~~~~~~~~~
A foreign call always returns an unboxed tuple of results, one
of which is the state token.  This seems to happen even for pure
calls. 

Even if we returned a single result for pure calls, it'd still be
right to wrap it in a singleton unboxed tuple, because the result
might be a Haskell closure pointer, we don't want to evaluate it. -}

----------------------------------
cgOpApp :: StgOp	-- The op
	-> [StgArg]	-- Arguments
	-> Type		-- Result type (always an unboxed tuple)
	-> FCode ()

-- Foreign calls 
cgOpApp (StgFCallOp fcall _) stg_args res_ty 
  = do	{ (res_regs, res_hints) <- newUnboxedTupleRegs res_ty
	 	-- Choose result regs r1, r2
		-- Note [Foreign call results]
	; cgForeignCall res_regs res_hints fcall stg_args
		-- r1, r2 = foo( x, y )
	; emitReturn (map (CmmReg . CmmLocal) res_regs) }
		-- return (r1, r2) 
      
-- tagToEnum# is special: we need to pull the constructor 
-- out of the table, and perform an appropriate return.

cgOpApp (StgPrimOp TagToEnumOp) [arg] res_ty 
  = ASSERT(isEnumerationTyCon tycon)
    do	{ args' <- getNonVoidArgAmodes [arg]
        ; let amode = case args' of [amode] -> amode
                                    _ -> panic "TagToEnumOp had void arg"
	; emitReturn [tagToClosure tycon amode] }
   where
	  -- If you're reading this code in the attempt to figure
	  -- out why the compiler panic'ed here, it is probably because
	  -- you used tagToEnum# in a non-monomorphic setting, e.g., 
	  --         intToTg :: Enum a => Int -> a ; intToTg (I# x#) = tagToEnum# x#
	  -- That won't work.
	tycon = tyConAppTyCon res_ty

cgOpApp (StgPrimOp primop) args res_ty
  | primOpOutOfLine primop
  = do	{ cmm_args <- getNonVoidArgAmodes args
        ; let fun = CmmLit (CmmLabel (mkRtsPrimOpLabel primop))
        ; emitCall (PrimOpCall, PrimOpReturn) fun cmm_args }

  | ReturnsPrim VoidRep <- result_info
  = do cgPrimOp [] primop args 
       emitReturn []

  | ReturnsPrim rep <- result_info
  = do res <- newTemp (primRepCmmType rep)
       cgPrimOp [res] primop args 
       emitReturn [CmmReg (CmmLocal res)]

  | ReturnsAlg tycon <- result_info, isUnboxedTupleTyCon tycon
  = do (regs, _hints) <- newUnboxedTupleRegs res_ty
       cgPrimOp regs primop args
       emitReturn (map (CmmReg . CmmLocal) regs)

  | ReturnsAlg tycon <- result_info
  , isEnumerationTyCon tycon
	-- c.f. cgExpr (...TagToEnumOp...)
  = do	tag_reg <- newTemp bWord
	cgPrimOp [tag_reg] primop args
   	emitReturn [tagToClosure tycon
	                (CmmReg (CmmLocal tag_reg))]

  | otherwise = panic "cgPrimop"
  where
     result_info = getPrimOpResultInfo primop

cgOpApp (StgPrimCallOp primcall) args _res_ty
  = do	{ cmm_args <- getNonVoidArgAmodes args
        ; let fun = CmmLit (CmmLabel (mkPrimCallLabel primcall))
        ; emitCall (PrimOpCall, PrimOpReturn) fun cmm_args }

---------------------------------------------------
cgPrimOp   :: [LocalReg]	-- where to put the results
	   -> PrimOp		-- the op
	   -> [StgArg]		-- arguments
	   -> FCode ()

cgPrimOp results op args
  = do arg_exprs <- getNonVoidArgAmodes args
       emitPrimOp results op arg_exprs


------------------------------------------------------------------------
--	Emitting code for a primop
------------------------------------------------------------------------

emitPrimOp :: [LocalReg]	-- where to put the results
	   -> PrimOp		-- the op
	   -> [CmmExpr]		-- arguments
	   -> FCode ()

-- First we handle various awkward cases specially.  The remaining
-- easy cases are then handled by translateOp, defined below.

emitPrimOp [res_r,res_c] IntAddCOp [aa,bb]
{- 
   With some bit-twiddling, we can define int{Add,Sub}Czh portably in
   C, and without needing any comparisons.  This may not be the
   fastest way to do it - if you have better code, please send it! --SDM
  
   Return : r = a + b,  c = 0 if no overflow, 1 on overflow.
  
   We currently don't make use of the r value if c is != 0 (i.e. 
   overflow), we just convert to big integers and try again.  This
   could be improved by making r and c the correct values for
   plugging into a new J#.  
   
   { r = ((I_)(a)) + ((I_)(b));					\
     c = ((StgWord)(~(((I_)(a))^((I_)(b))) & (((I_)(a))^r)))	\
         >> (BITS_IN (I_) - 1);					\
   } 
   Wading through the mass of bracketry, it seems to reduce to:
   c = ( (~(a^b)) & (a^r) ) >>unsigned (BITS_IN(I_)-1)

-}
   = emit $ catAGraphs [
        mkAssign (CmmLocal res_r) (CmmMachOp mo_wordAdd [aa,bb]),
        mkAssign (CmmLocal res_c) $
	  CmmMachOp mo_wordUShr [
		CmmMachOp mo_wordAnd [
		    CmmMachOp mo_wordNot [CmmMachOp mo_wordXor [aa,bb]],
		    CmmMachOp mo_wordXor [aa, CmmReg (CmmLocal res_r)]
		], 
	        CmmLit (mkIntCLit (wORD_SIZE_IN_BITS - 1))
	  ]
     ]


emitPrimOp [res_r,res_c] IntSubCOp [aa,bb]
{- Similarly:
   #define subIntCzh(r,c,a,b)					\
   { r = ((I_)(a)) - ((I_)(b));					\
     c = ((StgWord)((((I_)(a))^((I_)(b))) & (((I_)(a))^r)))	\
         >> (BITS_IN (I_) - 1);					\
   }

   c =  ((a^b) & (a^r)) >>unsigned (BITS_IN(I_)-1)
-}
   = emit $ catAGraphs [
        mkAssign (CmmLocal res_r) (CmmMachOp mo_wordSub [aa,bb]),
        mkAssign (CmmLocal res_c) $
	  CmmMachOp mo_wordUShr [
		CmmMachOp mo_wordAnd [
		    CmmMachOp mo_wordXor [aa,bb],
		    CmmMachOp mo_wordXor [aa, CmmReg (CmmLocal res_r)]
		], 
	        CmmLit (mkIntCLit (wORD_SIZE_IN_BITS - 1))
	  ]
     ]


emitPrimOp [res] ParOp [arg]
  = 
	-- for now, just implement this in a C function
	-- later, we might want to inline it.
    emitCCall
	[(res,NoHint)]
    	(CmmLit (CmmLabel (mkCmmCodeLabel rtsPackageId (fsLit "newSpark"))))
	[(CmmReg (CmmGlobal BaseReg), AddrHint), (arg,AddrHint)] 

emitPrimOp [res] ReadMutVarOp [mutv]
   = emit (mkAssign (CmmLocal res) (cmmLoadIndexW mutv fixedHdrSize gcWord))

emitPrimOp [] WriteMutVarOp [mutv,var]
   = do
	emit (mkStore (cmmOffsetW mutv fixedHdrSize) var)
	emitCCall
		[{-no results-}]
		(CmmLit (CmmLabel mkDirty_MUT_VAR_Label))
		[(CmmReg (CmmGlobal BaseReg), AddrHint), (mutv,AddrHint)]

--  #define sizzeofByteArrayzh(r,a) \
--     r = ((StgArrWords *)(a))->bytes
emitPrimOp [res] SizeofByteArrayOp [arg]
   = emit $
	mkAssign (CmmLocal res) (cmmLoadIndexW arg fixedHdrSize bWord)

--  #define sizzeofMutableByteArrayzh(r,a) \
--      r = ((StgArrWords *)(a))->bytes
emitPrimOp [res] SizeofMutableByteArrayOp [arg]
   = emitPrimOp [res] SizeofByteArrayOp [arg]


--  #define touchzh(o)                  /* nothing */
emitPrimOp res@[] TouchOp args@[_arg]
   = do emitPrimCall res MO_Touch args

--  #define byteArrayContentszh(r,a) r = BYTE_ARR_CTS(a)
emitPrimOp [res] ByteArrayContents_Char [arg]
   = emit (mkAssign (CmmLocal res) (cmmOffsetB arg arrWordsHdrSize))

--  #define stableNameToIntzh(r,s)   (r = ((StgStableName *)s)->sn)
emitPrimOp [res] StableNameToIntOp [arg]
   = emit (mkAssign (CmmLocal res) (cmmLoadIndexW arg fixedHdrSize bWord))

--  #define eqStableNamezh(r,sn1,sn2)					\
--    (r = (((StgStableName *)sn1)->sn == ((StgStableName *)sn2)->sn))
emitPrimOp [res] EqStableNameOp [arg1,arg2]
   = emit (mkAssign (CmmLocal res) (CmmMachOp mo_wordEq [
				cmmLoadIndexW arg1 fixedHdrSize bWord,
				cmmLoadIndexW arg2 fixedHdrSize bWord
			 ]))


emitPrimOp [res] ReallyUnsafePtrEqualityOp [arg1,arg2]
   = emit (mkAssign (CmmLocal res) (CmmMachOp mo_wordEq [arg1,arg2]))

--  #define addrToHValuezh(r,a) r=(P_)a
emitPrimOp [res] AddrToHValueOp [arg]
   = emit (mkAssign (CmmLocal res) arg)

--  #define dataToTagzh(r,a)  r=(GET_TAG(((StgClosure *)a)->header.info))
--  Note: argument may be tagged!
emitPrimOp [res] DataToTagOp [arg]
   = emit (mkAssign (CmmLocal res) (getConstrTag (cmmUntag arg)))

{- Freezing arrays-of-ptrs requires changing an info table, for the
   benefit of the generational collector.  It needs to scavenge mutable
   objects, even if they are in old space.  When they become immutable,
   they can be removed from this scavenge list.	 -}

--  #define unsafeFreezzeArrayzh(r,a)
--	{
--        SET_INFO((StgClosure *)a,&stg_MUT_ARR_PTRS_FROZEN0_info);
--	  r = a;
--	}
emitPrimOp [res] UnsafeFreezeArrayOp [arg]
   = emit $ catAGraphs
	 [ setInfo arg (CmmLit (CmmLabel mkMAP_FROZEN_infoLabel)),
	   mkAssign (CmmLocal res) arg ]

--  #define unsafeFreezzeByteArrayzh(r,a)	r=(a)
emitPrimOp [res] UnsafeFreezeByteArrayOp [arg]
   = emit (mkAssign (CmmLocal res) arg)

-- Reading/writing pointer arrays

emitPrimOp [r] ReadArrayOp  [obj,ix]    = doReadPtrArrayOp r obj ix
emitPrimOp [r] IndexArrayOp [obj,ix]    = doReadPtrArrayOp r obj ix
emitPrimOp []  WriteArrayOp [obj,ix,v]  = doWritePtrArrayOp obj ix v

-- IndexXXXoffAddr

emitPrimOp res IndexOffAddrOp_Char      args = doIndexOffAddrOp (Just mo_u_8ToWord) b8 res args
emitPrimOp res IndexOffAddrOp_WideChar  args = doIndexOffAddrOp (Just mo_u_32ToWord) b32 res args
emitPrimOp res IndexOffAddrOp_Int       args = doIndexOffAddrOp Nothing bWord res args
emitPrimOp res IndexOffAddrOp_Word      args = doIndexOffAddrOp Nothing bWord res args
emitPrimOp res IndexOffAddrOp_Addr      args = doIndexOffAddrOp Nothing bWord res args
emitPrimOp res IndexOffAddrOp_Float     args = doIndexOffAddrOp Nothing f32 res args
emitPrimOp res IndexOffAddrOp_Double    args = doIndexOffAddrOp Nothing f64 res args
emitPrimOp res IndexOffAddrOp_StablePtr args = doIndexOffAddrOp Nothing bWord res args
emitPrimOp res IndexOffAddrOp_Int8      args = doIndexOffAddrOp (Just mo_s_8ToWord) b8  res args
emitPrimOp res IndexOffAddrOp_Int16     args = doIndexOffAddrOp (Just mo_s_16ToWord) b16 res args
emitPrimOp res IndexOffAddrOp_Int32     args = doIndexOffAddrOp (Just mo_s_32ToWord) b32 res args
emitPrimOp res IndexOffAddrOp_Int64     args = doIndexOffAddrOp Nothing b64 res args
emitPrimOp res IndexOffAddrOp_Word8     args = doIndexOffAddrOp (Just mo_u_8ToWord) b8  res args
emitPrimOp res IndexOffAddrOp_Word16    args = doIndexOffAddrOp (Just mo_u_16ToWord) b16 res args
emitPrimOp res IndexOffAddrOp_Word32    args = doIndexOffAddrOp (Just mo_u_32ToWord) b32 res args
emitPrimOp res IndexOffAddrOp_Word64    args = doIndexOffAddrOp Nothing b64 res args

-- ReadXXXoffAddr, which are identical, for our purposes, to IndexXXXoffAddr.

emitPrimOp res ReadOffAddrOp_Char      args = doIndexOffAddrOp (Just mo_u_8ToWord) b8 res args
emitPrimOp res ReadOffAddrOp_WideChar  args = doIndexOffAddrOp (Just mo_u_32ToWord) b32 res args
emitPrimOp res ReadOffAddrOp_Int       args = doIndexOffAddrOp Nothing bWord res args
emitPrimOp res ReadOffAddrOp_Word      args = doIndexOffAddrOp Nothing bWord res args
emitPrimOp res ReadOffAddrOp_Addr      args = doIndexOffAddrOp Nothing bWord res args
emitPrimOp res ReadOffAddrOp_Float     args = doIndexOffAddrOp Nothing f32 res args
emitPrimOp res ReadOffAddrOp_Double    args = doIndexOffAddrOp Nothing f64 res args
emitPrimOp res ReadOffAddrOp_StablePtr args = doIndexOffAddrOp Nothing bWord res args
emitPrimOp res ReadOffAddrOp_Int8      args = doIndexOffAddrOp (Just mo_s_8ToWord) b8  res args
emitPrimOp res ReadOffAddrOp_Int16     args = doIndexOffAddrOp (Just mo_s_16ToWord) b16 res args
emitPrimOp res ReadOffAddrOp_Int32     args = doIndexOffAddrOp (Just mo_s_32ToWord) b32 res args
emitPrimOp res ReadOffAddrOp_Int64     args = doIndexOffAddrOp Nothing b64 res args
emitPrimOp res ReadOffAddrOp_Word8     args = doIndexOffAddrOp (Just mo_u_8ToWord) b8  res args
emitPrimOp res ReadOffAddrOp_Word16    args = doIndexOffAddrOp (Just mo_u_16ToWord) b16 res args
emitPrimOp res ReadOffAddrOp_Word32    args = doIndexOffAddrOp (Just mo_u_32ToWord) b32 res args
emitPrimOp res ReadOffAddrOp_Word64    args = doIndexOffAddrOp Nothing b64 res args

-- IndexXXXArray

emitPrimOp res IndexByteArrayOp_Char      args = doIndexByteArrayOp (Just mo_u_8ToWord) b8 res args
emitPrimOp res IndexByteArrayOp_WideChar  args = doIndexByteArrayOp (Just mo_u_32ToWord) b32 res args
emitPrimOp res IndexByteArrayOp_Int       args = doIndexByteArrayOp Nothing bWord res args
emitPrimOp res IndexByteArrayOp_Word      args = doIndexByteArrayOp Nothing bWord res args
emitPrimOp res IndexByteArrayOp_Addr      args = doIndexByteArrayOp Nothing bWord res args
emitPrimOp res IndexByteArrayOp_Float     args = doIndexByteArrayOp Nothing f32 res args
emitPrimOp res IndexByteArrayOp_Double    args = doIndexByteArrayOp Nothing f64 res args
emitPrimOp res IndexByteArrayOp_StablePtr args = doIndexByteArrayOp Nothing bWord res args
emitPrimOp res IndexByteArrayOp_Int8      args = doIndexByteArrayOp (Just mo_s_8ToWord) b8  res args
emitPrimOp res IndexByteArrayOp_Int16     args = doIndexByteArrayOp (Just mo_s_16ToWord) b16  res args
emitPrimOp res IndexByteArrayOp_Int32     args = doIndexByteArrayOp (Just mo_s_32ToWord) b32  res args
emitPrimOp res IndexByteArrayOp_Int64     args = doIndexByteArrayOp Nothing b64  res args
emitPrimOp res IndexByteArrayOp_Word8     args = doIndexByteArrayOp (Just mo_u_8ToWord) b8  res args
emitPrimOp res IndexByteArrayOp_Word16    args = doIndexByteArrayOp (Just mo_u_16ToWord) b16  res args
emitPrimOp res IndexByteArrayOp_Word32    args = doIndexByteArrayOp (Just mo_u_32ToWord) b32  res args
emitPrimOp res IndexByteArrayOp_Word64    args = doIndexByteArrayOp Nothing b64  res args

-- ReadXXXArray, identical to IndexXXXArray.

emitPrimOp res ReadByteArrayOp_Char       args = doIndexByteArrayOp (Just mo_u_8ToWord) b8 res args
emitPrimOp res ReadByteArrayOp_WideChar   args = doIndexByteArrayOp (Just mo_u_32ToWord) b32 res args
emitPrimOp res ReadByteArrayOp_Int        args = doIndexByteArrayOp Nothing bWord res args
emitPrimOp res ReadByteArrayOp_Word       args = doIndexByteArrayOp Nothing bWord res args
emitPrimOp res ReadByteArrayOp_Addr       args = doIndexByteArrayOp Nothing bWord res args
emitPrimOp res ReadByteArrayOp_Float      args = doIndexByteArrayOp Nothing f32 res args
emitPrimOp res ReadByteArrayOp_Double     args = doIndexByteArrayOp Nothing f64 res args
emitPrimOp res ReadByteArrayOp_StablePtr  args = doIndexByteArrayOp Nothing bWord res args
emitPrimOp res ReadByteArrayOp_Int8       args = doIndexByteArrayOp (Just mo_s_8ToWord) b8  res args
emitPrimOp res ReadByteArrayOp_Int16      args = doIndexByteArrayOp (Just mo_s_16ToWord) b16  res args
emitPrimOp res ReadByteArrayOp_Int32      args = doIndexByteArrayOp (Just mo_s_32ToWord) b32  res args
emitPrimOp res ReadByteArrayOp_Int64      args = doIndexByteArrayOp Nothing b64  res args
emitPrimOp res ReadByteArrayOp_Word8      args = doIndexByteArrayOp (Just mo_u_8ToWord) b8  res args
emitPrimOp res ReadByteArrayOp_Word16     args = doIndexByteArrayOp (Just mo_u_16ToWord) b16  res args
emitPrimOp res ReadByteArrayOp_Word32     args = doIndexByteArrayOp (Just mo_u_32ToWord) b32  res args
emitPrimOp res ReadByteArrayOp_Word64     args = doIndexByteArrayOp Nothing b64  res args

-- WriteXXXoffAddr

emitPrimOp res WriteOffAddrOp_Char       args = doWriteOffAddrOp (Just mo_WordTo8)  res args
emitPrimOp res WriteOffAddrOp_WideChar   args = doWriteOffAddrOp (Just mo_WordTo32) res args
emitPrimOp res WriteOffAddrOp_Int        args = doWriteOffAddrOp Nothing res args
emitPrimOp res WriteOffAddrOp_Word       args = doWriteOffAddrOp Nothing res args
emitPrimOp res WriteOffAddrOp_Addr       args = doWriteOffAddrOp Nothing res args
emitPrimOp res WriteOffAddrOp_Float      args = doWriteOffAddrOp Nothing res args
emitPrimOp res WriteOffAddrOp_Double     args = doWriteOffAddrOp Nothing res args
emitPrimOp res WriteOffAddrOp_StablePtr  args = doWriteOffAddrOp Nothing res args
emitPrimOp res WriteOffAddrOp_Int8       args = doWriteOffAddrOp (Just mo_WordTo8)  res args
emitPrimOp res WriteOffAddrOp_Int16      args = doWriteOffAddrOp (Just mo_WordTo16) res args
emitPrimOp res WriteOffAddrOp_Int32      args = doWriteOffAddrOp (Just mo_WordTo32) res args
emitPrimOp res WriteOffAddrOp_Int64      args = doWriteOffAddrOp Nothing res args
emitPrimOp res WriteOffAddrOp_Word8      args = doWriteOffAddrOp (Just mo_WordTo8)  res args
emitPrimOp res WriteOffAddrOp_Word16     args = doWriteOffAddrOp (Just mo_WordTo16) res args
emitPrimOp res WriteOffAddrOp_Word32     args = doWriteOffAddrOp (Just mo_WordTo32) res args
emitPrimOp res WriteOffAddrOp_Word64     args = doWriteOffAddrOp Nothing res args

-- WriteXXXArray

emitPrimOp res WriteByteArrayOp_Char      args = doWriteByteArrayOp (Just mo_WordTo8)  res args
emitPrimOp res WriteByteArrayOp_WideChar  args = doWriteByteArrayOp (Just mo_WordTo32) res args
emitPrimOp res WriteByteArrayOp_Int       args = doWriteByteArrayOp Nothing res args
emitPrimOp res WriteByteArrayOp_Word      args = doWriteByteArrayOp Nothing res args
emitPrimOp res WriteByteArrayOp_Addr      args = doWriteByteArrayOp Nothing res args
emitPrimOp res WriteByteArrayOp_Float     args = doWriteByteArrayOp Nothing res args
emitPrimOp res WriteByteArrayOp_Double    args = doWriteByteArrayOp Nothing res args
emitPrimOp res WriteByteArrayOp_StablePtr args = doWriteByteArrayOp Nothing res args
emitPrimOp res WriteByteArrayOp_Int8      args = doWriteByteArrayOp (Just mo_WordTo8)  res args
emitPrimOp res WriteByteArrayOp_Int16     args = doWriteByteArrayOp (Just mo_WordTo16) res args
emitPrimOp res WriteByteArrayOp_Int32     args = doWriteByteArrayOp (Just mo_WordTo32) res args
emitPrimOp res WriteByteArrayOp_Int64     args = doWriteByteArrayOp Nothing  res args
emitPrimOp res WriteByteArrayOp_Word8     args = doWriteByteArrayOp (Just mo_WordTo8)  res args
emitPrimOp res WriteByteArrayOp_Word16    args = doWriteByteArrayOp (Just mo_WordTo16) res args
emitPrimOp res WriteByteArrayOp_Word32    args = doWriteByteArrayOp (Just mo_WordTo32) res args
emitPrimOp res WriteByteArrayOp_Word64    args = doWriteByteArrayOp Nothing res args


-- The rest just translate straightforwardly
emitPrimOp [res] op [arg]
   | nopOp op
   = emit (mkAssign (CmmLocal res) arg)

   | Just (mop,rep) <- narrowOp op
   = emit (mkAssign (CmmLocal res) $
	   CmmMachOp (mop rep wordWidth) [CmmMachOp (mop wordWidth rep) [arg]])

emitPrimOp r@[res] op args
   | Just prim <- callishOp op
   = do emitPrimCall r prim args

   | Just mop <- translateOp op
   = let stmt = mkAssign (CmmLocal res) (CmmMachOp mop args) in
     emit stmt

emitPrimOp _ op _
 = pprPanic "emitPrimOp: can't translate PrimOp" (ppr op)


-- These PrimOps are NOPs in Cmm

nopOp :: PrimOp -> Bool
nopOp Int2WordOp     = True
nopOp Word2IntOp     = True
nopOp Int2AddrOp     = True
nopOp Addr2IntOp     = True
nopOp ChrOp	     = True  -- Int# and Char# are rep'd the same
nopOp OrdOp	     = True
nopOp _		     = False

-- These PrimOps turn into double casts

narrowOp :: PrimOp -> Maybe (Width -> Width -> MachOp, Width)
narrowOp Narrow8IntOp   = Just (MO_SS_Conv, W8)
narrowOp Narrow16IntOp  = Just (MO_SS_Conv, W16)
narrowOp Narrow32IntOp  = Just (MO_SS_Conv, W32)
narrowOp Narrow8WordOp  = Just (MO_UU_Conv, W8)
narrowOp Narrow16WordOp = Just (MO_UU_Conv, W16)
narrowOp Narrow32WordOp = Just (MO_UU_Conv, W32)
narrowOp _ 		= Nothing

-- Native word signless ops

translateOp :: PrimOp -> Maybe MachOp
translateOp IntAddOp       = Just mo_wordAdd
translateOp IntSubOp       = Just mo_wordSub
translateOp WordAddOp      = Just mo_wordAdd
translateOp WordSubOp      = Just mo_wordSub
translateOp AddrAddOp      = Just mo_wordAdd
translateOp AddrSubOp      = Just mo_wordSub

translateOp IntEqOp        = Just mo_wordEq
translateOp IntNeOp        = Just mo_wordNe
translateOp WordEqOp       = Just mo_wordEq
translateOp WordNeOp       = Just mo_wordNe
translateOp AddrEqOp       = Just mo_wordEq
translateOp AddrNeOp       = Just mo_wordNe

translateOp AndOp          = Just mo_wordAnd
translateOp OrOp           = Just mo_wordOr
translateOp XorOp          = Just mo_wordXor
translateOp NotOp          = Just mo_wordNot
translateOp SllOp	   = Just mo_wordShl
translateOp SrlOp	   = Just mo_wordUShr

translateOp AddrRemOp	   = Just mo_wordURem

-- Native word signed ops

translateOp IntMulOp        = Just mo_wordMul
translateOp IntMulMayOfloOp = Just (MO_S_MulMayOflo wordWidth)
translateOp IntQuotOp       = Just mo_wordSQuot
translateOp IntRemOp        = Just mo_wordSRem
translateOp IntNegOp        = Just mo_wordSNeg


translateOp IntGeOp        = Just mo_wordSGe
translateOp IntLeOp        = Just mo_wordSLe
translateOp IntGtOp        = Just mo_wordSGt
translateOp IntLtOp        = Just mo_wordSLt

translateOp ISllOp	   = Just mo_wordShl
translateOp ISraOp	   = Just mo_wordSShr
translateOp ISrlOp	   = Just mo_wordUShr

-- Native word unsigned ops

translateOp WordGeOp       = Just mo_wordUGe
translateOp WordLeOp       = Just mo_wordULe
translateOp WordGtOp       = Just mo_wordUGt
translateOp WordLtOp       = Just mo_wordULt

translateOp WordMulOp      = Just mo_wordMul
translateOp WordQuotOp     = Just mo_wordUQuot
translateOp WordRemOp      = Just mo_wordURem

translateOp AddrGeOp       = Just mo_wordUGe
translateOp AddrLeOp       = Just mo_wordULe
translateOp AddrGtOp       = Just mo_wordUGt
translateOp AddrLtOp       = Just mo_wordULt

-- Char# ops

translateOp CharEqOp       = Just (MO_Eq wordWidth)
translateOp CharNeOp       = Just (MO_Ne wordWidth)
translateOp CharGeOp       = Just (MO_U_Ge wordWidth)
translateOp CharLeOp       = Just (MO_U_Le wordWidth)
translateOp CharGtOp       = Just (MO_U_Gt wordWidth)
translateOp CharLtOp       = Just (MO_U_Lt wordWidth)

-- Double ops

translateOp DoubleEqOp     = Just (MO_F_Eq W64)
translateOp DoubleNeOp     = Just (MO_F_Ne W64)
translateOp DoubleGeOp     = Just (MO_F_Ge W64)
translateOp DoubleLeOp     = Just (MO_F_Le W64)
translateOp DoubleGtOp     = Just (MO_F_Gt W64)
translateOp DoubleLtOp     = Just (MO_F_Lt W64)

translateOp DoubleAddOp    = Just (MO_F_Add W64)
translateOp DoubleSubOp    = Just (MO_F_Sub W64)
translateOp DoubleMulOp    = Just (MO_F_Mul W64)
translateOp DoubleDivOp    = Just (MO_F_Quot W64)
translateOp DoubleNegOp    = Just (MO_F_Neg W64)

-- Float ops

translateOp FloatEqOp     = Just (MO_F_Eq W32)
translateOp FloatNeOp     = Just (MO_F_Ne W32)
translateOp FloatGeOp     = Just (MO_F_Ge W32)
translateOp FloatLeOp     = Just (MO_F_Le W32)
translateOp FloatGtOp     = Just (MO_F_Gt W32)
translateOp FloatLtOp     = Just (MO_F_Lt W32)

translateOp FloatAddOp    = Just (MO_F_Add  W32)
translateOp FloatSubOp    = Just (MO_F_Sub  W32)
translateOp FloatMulOp    = Just (MO_F_Mul  W32)
translateOp FloatDivOp    = Just (MO_F_Quot W32)
translateOp FloatNegOp    = Just (MO_F_Neg  W32)

-- Conversions

translateOp Int2DoubleOp   = Just (MO_SF_Conv wordWidth W64)
translateOp Double2IntOp   = Just (MO_FS_Conv W64 wordWidth)

translateOp Int2FloatOp    = Just (MO_SF_Conv wordWidth W32)
translateOp Float2IntOp    = Just (MO_FS_Conv W32 wordWidth)

translateOp Float2DoubleOp = Just (MO_FF_Conv W32 W64)
translateOp Double2FloatOp = Just (MO_FF_Conv W64 W32)

-- Word comparisons masquerading as more exotic things.

translateOp SameMutVarOp           = Just mo_wordEq
translateOp SameMVarOp             = Just mo_wordEq
translateOp SameMutableArrayOp     = Just mo_wordEq
translateOp SameMutableByteArrayOp = Just mo_wordEq
translateOp SameTVarOp             = Just mo_wordEq
translateOp EqStablePtrOp          = Just mo_wordEq

translateOp _ = Nothing

-- These primops are implemented by CallishMachOps, because they sometimes
-- turn into foreign calls depending on the backend.

callishOp :: PrimOp -> Maybe CallishMachOp
callishOp DoublePowerOp  = Just MO_F64_Pwr
callishOp DoubleSinOp    = Just MO_F64_Sin
callishOp DoubleCosOp    = Just MO_F64_Cos
callishOp DoubleTanOp    = Just MO_F64_Tan
callishOp DoubleSinhOp   = Just MO_F64_Sinh
callishOp DoubleCoshOp   = Just MO_F64_Cosh
callishOp DoubleTanhOp   = Just MO_F64_Tanh
callishOp DoubleAsinOp   = Just MO_F64_Asin
callishOp DoubleAcosOp   = Just MO_F64_Acos
callishOp DoubleAtanOp   = Just MO_F64_Atan
callishOp DoubleLogOp    = Just MO_F64_Log
callishOp DoubleExpOp    = Just MO_F64_Exp
callishOp DoubleSqrtOp   = Just MO_F64_Sqrt

callishOp FloatPowerOp  = Just MO_F32_Pwr
callishOp FloatSinOp    = Just MO_F32_Sin
callishOp FloatCosOp    = Just MO_F32_Cos
callishOp FloatTanOp    = Just MO_F32_Tan
callishOp FloatSinhOp   = Just MO_F32_Sinh
callishOp FloatCoshOp   = Just MO_F32_Cosh
callishOp FloatTanhOp   = Just MO_F32_Tanh
callishOp FloatAsinOp   = Just MO_F32_Asin
callishOp FloatAcosOp   = Just MO_F32_Acos
callishOp FloatAtanOp   = Just MO_F32_Atan
callishOp FloatLogOp    = Just MO_F32_Log
callishOp FloatExpOp    = Just MO_F32_Exp
callishOp FloatSqrtOp   = Just MO_F32_Sqrt

callishOp _ = Nothing

------------------------------------------------------------------------------
-- Helpers for translating various minor variants of array indexing.

doIndexOffAddrOp :: Maybe MachOp -> CmmType -> [LocalReg] -> [CmmExpr] -> FCode ()
doIndexOffAddrOp maybe_post_read_cast rep [res] [addr,idx]
   = mkBasicIndexedRead 0 maybe_post_read_cast rep res addr idx
doIndexOffAddrOp _ _ _ _
   = panic "CgPrimOp: doIndexOffAddrOp"

doIndexByteArrayOp :: Maybe MachOp -> CmmType -> [LocalReg] -> [CmmExpr] -> FCode ()
doIndexByteArrayOp maybe_post_read_cast rep [res] [addr,idx]
   = mkBasicIndexedRead arrWordsHdrSize maybe_post_read_cast rep res addr idx
doIndexByteArrayOp _ _ _ _ 
   = panic "CgPrimOp: doIndexByteArrayOp"

doReadPtrArrayOp ::  LocalReg -> CmmExpr -> CmmExpr -> FCode ()
doReadPtrArrayOp res addr idx
   = mkBasicIndexedRead arrPtrsHdrSize Nothing gcWord res addr idx


doWriteOffAddrOp :: Maybe MachOp -> [LocalReg] -> [CmmExpr] -> FCode ()
doWriteOffAddrOp maybe_pre_write_cast [] [addr,idx,val]
   = mkBasicIndexedWrite 0 maybe_pre_write_cast addr idx val
doWriteOffAddrOp _ _ _
   = panic "CgPrimOp: doWriteOffAddrOp"

doWriteByteArrayOp :: Maybe MachOp -> [LocalReg] -> [CmmExpr] -> FCode ()
doWriteByteArrayOp maybe_pre_write_cast [] [addr,idx,val]
   = mkBasicIndexedWrite arrWordsHdrSize maybe_pre_write_cast addr idx val
doWriteByteArrayOp _ _ _ 
   = panic "CgPrimOp: doWriteByteArrayOp"

doWritePtrArrayOp :: CmmExpr -> CmmExpr -> CmmExpr -> FCode ()
doWritePtrArrayOp addr idx val
  = do mkBasicIndexedWrite arrPtrsHdrSize Nothing addr idx val
       emit (setInfo addr (CmmLit (CmmLabel mkMAP_DIRTY_infoLabel)))
  -- the write barrier.  We must write a byte into the mark table:
  -- bits8[a + header_size + StgMutArrPtrs_size(a) + x >> N]
       emit $ mkStore (
         cmmOffsetExpr
          (cmmOffsetExprW (cmmOffsetB addr arrPtrsHdrSize)
                         (loadArrPtrsSize addr))
          (CmmMachOp mo_wordUShr [idx,
                                  CmmLit (mkIntCLit mUT_ARR_PTRS_CARD_BITS)])
         ) (CmmLit (CmmInt 1 W8))
       
loadArrPtrsSize :: CmmExpr -> CmmExpr
loadArrPtrsSize addr = CmmLoad (cmmOffsetB addr off) bWord
 where off = fixedHdrSize*wORD_SIZE + oFFSET_StgMutArrPtrs_ptrs

mkBasicIndexedRead :: ByteOff -> Maybe MachOp -> CmmType
		   -> LocalReg -> CmmExpr -> CmmExpr -> FCode ()
mkBasicIndexedRead off Nothing read_rep res base idx
   = emit (mkAssign (CmmLocal res) (cmmLoadIndexOffExpr off read_rep base idx))
mkBasicIndexedRead off (Just cast) read_rep res base idx
   = emit (mkAssign (CmmLocal res) (CmmMachOp cast [
				cmmLoadIndexOffExpr off read_rep base idx]))

mkBasicIndexedWrite :: ByteOff -> Maybe MachOp
		   -> CmmExpr -> CmmExpr -> CmmExpr -> FCode ()
mkBasicIndexedWrite off Nothing base idx val
   = emit (mkStore (cmmIndexOffExpr off (typeWidth (cmmExprType val)) base idx) val)
mkBasicIndexedWrite off (Just cast) base idx val
   = mkBasicIndexedWrite off Nothing base idx (CmmMachOp cast [val])

-- ----------------------------------------------------------------------------
-- Misc utils

cmmIndexOffExpr :: ByteOff -> Width -> CmmExpr -> CmmExpr -> CmmExpr
cmmIndexOffExpr off width base idx
   = cmmIndexExpr width (cmmOffsetB base off) idx

cmmLoadIndexOffExpr :: ByteOff -> CmmType -> CmmExpr -> CmmExpr -> CmmExpr
cmmLoadIndexOffExpr off ty base idx
   = CmmLoad (cmmIndexOffExpr off (typeWidth ty) base idx) ty

setInfo :: CmmExpr -> CmmExpr -> CmmAGraph
setInfo closure_ptr info_ptr = mkStore closure_ptr info_ptr

