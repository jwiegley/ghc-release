%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

Utility functions on @Core@ syntax

\begin{code}
{-# OPTIONS -fno-warn-incomplete-patterns #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

-- | Commonly useful utilites for manipulating the Core language
module CoreUtils (
	-- * Constructing expressions
	mkInlineMe, mkSCC, mkCoerce, mkCoerceI,
	bindNonRec, needsCaseBinding,
	mkIfThenElse, mkAltExpr, mkPiType, mkPiTypes,

	-- * Taking expressions apart
	findDefault, findAlt, isDefaultAlt, mergeAlts, trimConArgs,

	-- * Properties of expressions
	exprType, coreAltType, coreAltsType,
	exprIsDupable, exprIsTrivial, exprIsCheap, 
	exprIsHNF,exprOkForSpeculation, exprIsBig, 
	exprIsConApp_maybe, exprIsBottom,
	rhsIsStatic,

	-- * Arity and eta expansion
	manifestArity, exprArity, 
	exprEtaExpandArity, etaExpand, 

	-- * Expression and bindings size
	coreBindsSize, exprSize,

	-- * Hashing
	hashExpr,

	-- * Equality
	cheapEqExpr, tcEqExpr, tcEqExprX,

	-- * Manipulating data constructors and types
	applyTypeToArgs, applyTypeToArg,
        dataConOrigInstPat, dataConRepInstPat, dataConRepFSInstPat
    ) where

#include "HsVersions.h"

import CoreSyn
import CoreFVs
import PprCore
import Var
import SrcLoc
import VarSet
import VarEnv
import Name
import Module
#if mingw32_TARGET_OS
import Packages
#endif
import Literal
import DataCon
import PrimOp
import Id
import IdInfo
import NewDemand
import Type
import Coercion
import TyCon
import TysWiredIn
import CostCentre
import BasicTypes
import Unique
import Outputable
import DynFlags
import TysPrim
import FastString
import Maybes
import Util
import Data.Word
import Data.Bits

import GHC.Exts		-- For `xori` 
\end{code}


%************************************************************************
%*									*
\subsection{Find the type of a Core atom/expression}
%*									*
%************************************************************************

\begin{code}
exprType :: CoreExpr -> Type
-- ^ Recover the type of a well-typed Core expression. Fails when
-- applied to the actual 'CoreSyn.Type' expression as it cannot
-- really be said to have a type
exprType (Var var)	     = idType var
exprType (Lit lit)	     = literalType lit
exprType (Let _ body)	     = exprType body
exprType (Case _ _ ty _)     = ty
exprType (Cast _ co)         = snd (coercionKind co)
exprType (Note _ e)          = exprType e
exprType (Lam binder expr)   = mkPiType binder (exprType expr)
exprType e@(App _ _)
  = case collectArgs e of
	(fun, args) -> applyTypeToArgs e (exprType fun) args

exprType other = pprTrace "exprType" (pprCoreExpr other) alphaTy

coreAltType :: CoreAlt -> Type
-- ^ Returns the type of the alternatives right hand side
coreAltType (_,_,rhs) = exprType rhs

coreAltsType :: [CoreAlt] -> Type
-- ^ Returns the type of the first alternative, which should be the same as for all alternatives
coreAltsType (alt:_) = coreAltType alt
coreAltsType []	     = panic "corAltsType"
\end{code}

\begin{code}
mkPiType  :: Var   -> Type -> Type
-- ^ Makes a @(->)@ type or a forall type, depending
-- on whether it is given a type variable or a term variable.
mkPiTypes :: [Var] -> Type -> Type
-- ^ 'mkPiType' for multiple type or value arguments

mkPiType v ty
   | isId v    = mkFunTy (idType v) ty
   | otherwise = mkForAllTy v ty

mkPiTypes vs ty = foldr mkPiType ty vs
\end{code}

\begin{code}
applyTypeToArg :: Type -> CoreExpr -> Type
-- ^ Determines the type resulting from applying an expression to a function with the given type
applyTypeToArg fun_ty (Type arg_ty) = applyTy fun_ty arg_ty
applyTypeToArg fun_ty _             = funResultTy fun_ty

applyTypeToArgs :: CoreExpr -> Type -> [CoreExpr] -> Type
-- ^ A more efficient version of 'applyTypeToArg' when we have several arguments.
-- The first argument is just for debugging, and gives some context
applyTypeToArgs _ op_ty [] = op_ty

applyTypeToArgs e op_ty (Type ty : args)
  =	-- Accumulate type arguments so we can instantiate all at once
    go [ty] args
  where
    go rev_tys (Type ty : args) = go (ty:rev_tys) args
    go rev_tys rest_args        = applyTypeToArgs e op_ty' rest_args
			 	where
				  op_ty' = applyTysD msg op_ty (reverse rev_tys)
				  msg = ptext (sLit "applyTypeToArgs") <+> 
		    			panic_msg e op_ty

applyTypeToArgs e op_ty (_ : args)
  = case (splitFunTy_maybe op_ty) of
	Just (_, res_ty) -> applyTypeToArgs e res_ty args
	Nothing -> pprPanic "applyTypeToArgs" (panic_msg e op_ty)

panic_msg :: CoreExpr -> Type -> SDoc
panic_msg e op_ty = pprCoreExpr e $$ ppr op_ty
\end{code}

%************************************************************************
%*									*
\subsection{Attaching notes}
%*									*
%************************************************************************

mkNote removes redundant coercions, and SCCs where possible

\begin{code}
#ifdef UNUSED
mkNote :: Note -> CoreExpr -> CoreExpr
mkNote (SCC cc)	expr		   = mkSCC cc expr
mkNote InlineMe expr		   = mkInlineMe expr
mkNote note     expr		   = Note note expr
#endif
\end{code}

Drop trivial InlineMe's.  This is somewhat important, because if we have an unfolding
that looks like	(Note InlineMe (Var v)), the InlineMe doesn't go away because it may
not be *applied* to anything.

We don't use exprIsTrivial here, though, because we sometimes generate worker/wrapper
bindings like
	fw = ...
	f  = inline_me (coerce t fw)
As usual, the inline_me prevents the worker from getting inlined back into the wrapper.
We want the split, so that the coerces can cancel at the call site.  

However, we can get left with tiresome type applications.  Notably, consider
	f = /\ a -> let t = e in (t, w)
Then lifting the let out of the big lambda gives
	t' = /\a -> e
	f = /\ a -> let t = inline_me (t' a) in (t, w)
The inline_me is to stop the simplifier inlining t' right back
into t's RHS.  In the next phase we'll substitute for t (since
its rhs is trivial) and *then* we could get rid of the inline_me.
But it hardly seems worth it, so I don't bother.

\begin{code}
-- | Wraps the given expression in an inlining hint unless the expression
-- is trivial in some sense, so that doing so would usually hurt us
mkInlineMe :: CoreExpr -> CoreExpr
mkInlineMe (Var v) = Var v
mkInlineMe e	   = Note InlineMe e
\end{code}

\begin{code}
-- | Wrap the given expression in the coercion, dropping identity coercions and coalescing nested coercions
mkCoerceI :: CoercionI -> CoreExpr -> CoreExpr
mkCoerceI IdCo e = e
mkCoerceI (ACo co) e = mkCoerce co e

-- | Wrap the given expression in the coercion safely, coalescing nested coercions
mkCoerce :: Coercion -> CoreExpr -> CoreExpr
mkCoerce co (Cast expr co2)
  = ASSERT(let { (from_ty, _to_ty) = coercionKind co; 
                 (_from_ty2, to_ty2) = coercionKind co2} in
           from_ty `coreEqType` to_ty2 )
    mkCoerce (mkTransCoercion co2 co) expr

mkCoerce co expr 
  = let (from_ty, _to_ty) = coercionKind co in
--    if to_ty `coreEqType` from_ty
--    then expr
--    else 
        ASSERT2(from_ty `coreEqType` (exprType expr), text "Trying to coerce" <+> text "(" <> ppr expr $$ text "::" <+> ppr (exprType expr) <> text ")" $$ ppr co $$ ppr (coercionKindPredTy co))
         (Cast expr co)
\end{code}

\begin{code}
-- | Wraps the given expression in the cost centre unless
-- in a way that maximises their utility to the user
mkSCC :: CostCentre -> Expr b -> Expr b
	-- Note: Nested SCC's *are* preserved for the benefit of
	--       cost centre stack profiling
mkSCC _  (Lit lit)          = Lit lit
mkSCC cc (Lam x e)  	    = Lam x (mkSCC cc e)  -- Move _scc_ inside lambda
mkSCC cc (Note (SCC cc') e) = Note (SCC cc) (Note (SCC cc') e)
mkSCC cc (Note n e) 	    = Note n (mkSCC cc e) -- Move _scc_ inside notes
mkSCC cc (Cast e co)        = Cast (mkSCC cc e) co -- Move _scc_ inside cast
mkSCC cc expr	    	    = Note (SCC cc) expr
\end{code}


%************************************************************************
%*									*
\subsection{Other expression construction}
%*									*
%************************************************************************

\begin{code}
bindNonRec :: Id -> CoreExpr -> CoreExpr -> CoreExpr
-- ^ @bindNonRec x r b@ produces either:
--
-- > let x = r in b
--
-- or:
--
-- > case r of x { _DEFAULT_ -> b }
--
-- depending on whether we have to use a @case@ or @let@
-- binding for the expression (see 'needsCaseBinding').
-- It's used by the desugarer to avoid building bindings
-- that give Core Lint a heart attack, although actually
-- the simplifier deals with them perfectly well. See
-- also 'MkCore.mkCoreLet'
bindNonRec bndr rhs body 
  | needsCaseBinding (idType bndr) rhs = Case rhs bndr (exprType body) [(DEFAULT, [], body)]
  | otherwise			       = Let (NonRec bndr rhs) body

-- | Tests whether we have to use a @case@ rather than @let@ binding for this expression
-- as per the invariants of 'CoreExpr': see "CoreSyn#let_app_invariant"
needsCaseBinding :: Type -> CoreExpr -> Bool
needsCaseBinding ty rhs = isUnLiftedType ty && not (exprOkForSpeculation rhs)
	-- Make a case expression instead of a let
	-- These can arise either from the desugarer,
	-- or from beta reductions: (\x.e) (x +# y)
\end{code}

\begin{code}
mkAltExpr :: AltCon     -- ^ Case alternative constructor
          -> [CoreBndr] -- ^ Things bound by the pattern match
          -> [Type]     -- ^ The type arguments to the case alternative
          -> CoreExpr
-- ^ This guy constructs the value that the scrutinee must have
-- given that you are in one particular branch of a case
mkAltExpr (DataAlt con) args inst_tys
  = mkConApp con (map Type inst_tys ++ varsToCoreExprs args)
mkAltExpr (LitAlt lit) [] []
  = Lit lit
mkAltExpr (LitAlt _) _ _ = panic "mkAltExpr LitAlt"
mkAltExpr DEFAULT _ _ = panic "mkAltExpr DEFAULT"

mkIfThenElse :: CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
mkIfThenElse guard then_expr else_expr
-- Not going to be refining, so okay to take the type of the "then" clause
  = Case guard (mkWildId boolTy) (exprType then_expr) 
	 [ (DataAlt falseDataCon, [], else_expr),	-- Increasing order of tag!
    	   (DataAlt trueDataCon,  [], then_expr) ]
\end{code}


%************************************************************************
%*									*
\subsection{Taking expressions apart}
%*									*
%************************************************************************

The default alternative must be first, if it exists at all.
This makes it easy to find, though it makes matching marginally harder.

\begin{code}
-- | Extract the default case alternative
findDefault :: [CoreAlt] -> ([CoreAlt], Maybe CoreExpr)
findDefault ((DEFAULT,args,rhs) : alts) = ASSERT( null args ) (alts, Just rhs)
findDefault alts			= 		      (alts, Nothing)

-- | Find the case alternative corresponding to a particular 
-- constructor: panics if no such constructor exists
findAlt :: AltCon -> [CoreAlt] -> CoreAlt
findAlt con alts
  = case alts of
	(deflt@(DEFAULT,_,_):alts) -> go alts deflt
        _                          -> go alts panic_deflt
  where
    panic_deflt = pprPanic "Missing alternative" (ppr con $$ vcat (map ppr alts))

    go []	 	       deflt = deflt
    go (alt@(con1,_,_) : alts) deflt
      =	case con `cmpAltCon` con1 of
	  LT -> deflt	-- Missed it already; the alts are in increasing order
	  EQ -> alt
	  GT -> ASSERT( not (con1 == DEFAULT) ) go alts deflt

isDefaultAlt :: CoreAlt -> Bool
isDefaultAlt (DEFAULT, _, _) = True
isDefaultAlt _               = False

---------------------------------
mergeAlts :: [CoreAlt] -> [CoreAlt] -> [CoreAlt]
-- ^ Merge alternatives preserving order; alternatives in
-- the first argument shadow ones in the second
mergeAlts [] as2 = as2
mergeAlts as1 [] = as1
mergeAlts (a1:as1) (a2:as2)
  = case a1 `cmpAlt` a2 of
	LT -> a1 : mergeAlts as1      (a2:as2)
	EQ -> a1 : mergeAlts as1      as2	-- Discard a2
	GT -> a2 : mergeAlts (a1:as1) as2


---------------------------------
trimConArgs :: AltCon -> [CoreArg] -> [CoreArg]
-- ^ Given:
--
-- > case (C a b x y) of
-- >        C b x y -> ...
--
-- We want to drop the leading type argument of the scrutinee
-- leaving the arguments to match agains the pattern

trimConArgs DEFAULT      args = ASSERT( null args ) []
trimConArgs (LitAlt _)   args = ASSERT( null args ) []
trimConArgs (DataAlt dc) args = dropList (dataConUnivTyVars dc) args
\end{code}


%************************************************************************
%*									*
\subsection{Figuring out things about expressions}
%*									*
%************************************************************************

@exprIsTrivial@ is true of expressions we are unconditionally happy to
		duplicate; simple variables and constants, and type
		applications.  Note that primop Ids aren't considered
		trivial unless 

There used to be a gruesome test for (hasNoBinding v) in the
Var case:
	exprIsTrivial (Var v) | hasNoBinding v = idArity v == 0
The idea here is that a constructor worker, like \$wJust, is
really short for (\x -> \$wJust x), becuase \$wJust has no binding.
So it should be treated like a lambda.  Ditto unsaturated primops.
But now constructor workers are not "have-no-binding" Ids.  And
completely un-applied primops and foreign-call Ids are sufficiently
rare that I plan to allow them to be duplicated and put up with
saturating them.

SCC notes.  We do not treat (_scc_ "foo" x) as trivial, because 
  a) it really generates code, (and a heap object when it's 
     a function arg) to capture the cost centre
  b) see the note [SCC-and-exprIsTrivial] in Simplify.simplLazyBind

\begin{code}
exprIsTrivial :: CoreExpr -> Bool
exprIsTrivial (Var _)          = True        -- See notes above
exprIsTrivial (Type _)         = True
exprIsTrivial (Lit lit)        = litIsTrivial lit
exprIsTrivial (App e arg)      = not (isRuntimeArg arg) && exprIsTrivial e
exprIsTrivial (Note (SCC _) _) = False       -- See notes above
exprIsTrivial (Note _       e) = exprIsTrivial e
exprIsTrivial (Cast e _)       = exprIsTrivial e
exprIsTrivial (Lam b body)     = not (isRuntimeVar b) && exprIsTrivial body
exprIsTrivial _                = False
\end{code}


@exprIsDupable@	is true of expressions that can be duplicated at a modest
		cost in code size.  This will only happen in different case
		branches, so there's no issue about duplicating work.

		That is, exprIsDupable returns True of (f x) even if
		f is very very expensive to call.

		Its only purpose is to avoid fruitless let-binding
		and then inlining of case join points


\begin{code}
exprIsDupable :: CoreExpr -> Bool
exprIsDupable (Type _)          = True
exprIsDupable (Var _)           = True
exprIsDupable (Lit lit)         = litIsDupable lit
exprIsDupable (Note InlineMe _) = True
exprIsDupable (Note _ e)        = exprIsDupable e
exprIsDupable (Cast e _)        = exprIsDupable e
exprIsDupable expr
  = go expr 0
  where
    go (Var _)   _      = True
    go (App f a) n_args =  n_args < dupAppSize
			&& exprIsDupable a
			&& go f (n_args+1)
    go _         _      = False

dupAppSize :: Int
dupAppSize = 4		-- Size of application we are prepared to duplicate
\end{code}

@exprIsCheap@ looks at a Core expression and returns \tr{True} if
it is obviously in weak head normal form, or is cheap to get to WHNF.
[Note that that's not the same as exprIsDupable; an expression might be
big, and hence not dupable, but still cheap.]

By ``cheap'' we mean a computation we're willing to:
	push inside a lambda, or
	inline at more than one place
That might mean it gets evaluated more than once, instead of being
shared.  The main examples of things which aren't WHNF but are
``cheap'' are:

  * 	case e of
	  pi -> ei
	(where e, and all the ei are cheap)

  *	let x = e in b
	(where e and b are cheap)

  *	op x1 ... xn
	(where op is a cheap primitive operator)

  *	error "foo"
	(because we are happy to substitute it inside a lambda)

Notice that a variable is considered 'cheap': we can push it inside a lambda,
because sharing will make sure it is only evaluated once.

\begin{code}
exprIsCheap :: CoreExpr -> Bool
exprIsCheap (Lit _)           = True
exprIsCheap (Type _)          = True
exprIsCheap (Var _)           = True
exprIsCheap (Note InlineMe _) = True
exprIsCheap (Note _ e)        = exprIsCheap e
exprIsCheap (Cast e _)        = exprIsCheap e
exprIsCheap (Lam x e)         = isRuntimeVar x || exprIsCheap e
exprIsCheap (Case e _ _ alts) = exprIsCheap e && 
				and [exprIsCheap rhs | (_,_,rhs) <- alts]
	-- Experimentally, treat (case x of ...) as cheap
	-- (and case __coerce x etc.)
	-- This improves arities of overloaded functions where
	-- there is only dictionary selection (no construction) involved
exprIsCheap (Let (NonRec x _) e)  
      | isUnLiftedType (idType x) = exprIsCheap e
      | otherwise		  = False
	-- strict lets always have cheap right hand sides,
	-- and do no allocation.

exprIsCheap other_expr 	-- Applications and variables
  = go other_expr []
  where
	-- Accumulate value arguments, then decide
    go (App f a) val_args | isRuntimeArg a = go f (a:val_args)
			  | otherwise      = go f val_args

    go (Var _) [] = True	-- Just a type application of a variable
				-- (f t1 t2 t3) counts as WHNF
    go (Var f) args
 	= case globalIdDetails f of
		RecordSelId {} -> go_sel args
		ClassOpId _    -> go_sel args
		PrimOpId op    -> go_primop op args

		DataConWorkId _ -> go_pap args
		_ | length args < idArity f -> go_pap args

	        _ -> isBottomingId f
			-- Application of a function which
			-- always gives bottom; we treat this as cheap
			-- because it certainly doesn't need to be shared!
	
    go _ _ = False
 
    --------------
    go_pap args = all exprIsTrivial args
 	-- For constructor applications and primops, check that all
 	-- the args are trivial.  We don't want to treat as cheap, say,
 	-- 	(1:2:3:4:5:[])
 	-- We'll put up with one constructor application, but not dozens
 	
    --------------
    go_primop op args = primOpIsCheap op && all exprIsCheap args
 	-- In principle we should worry about primops
 	-- that return a type variable, since the result
 	-- might be applied to something, but I'm not going
 	-- to bother to check the number of args
 
    --------------
    go_sel [arg] = exprIsCheap arg	-- I'm experimenting with making record selection
    go_sel _     = False		-- look cheap, so we will substitute it inside a
 					-- lambda.  Particularly for dictionary field selection.
  		-- BUT: Take care with (sel d x)!  The (sel d) might be cheap, but
  		--	there's no guarantee that (sel d x) will be too.  Hence (n_val_args == 1)
\end{code}

\begin{code}
-- | 'exprOkForSpeculation' returns True of an expression that is:
--
--  * Safe to evaluate even if normal order eval might not 
--    evaluate the expression at all, or
--
--  * Safe /not/ to evaluate even if normal order would do so
--
-- Precisely, it returns @True@ iff:
--
--  * The expression guarantees to terminate, 
--
--  * soon, 
--
--  * without raising an exception,
--
--  * without causing a side effect (e.g. writing a mutable variable)
--
-- Note that if @exprIsHNF e@, then @exprOkForSpecuation e@.
-- As an example of the considerations in this test, consider:
--
-- > let x = case y# +# 1# of { r# -> I# r# }
-- > in E
--
-- being translated to:
--
-- > case y# +# 1# of { r# -> 
-- >    let x = I# r#
-- >    in E 
-- > }
-- 
-- We can only do this if the @y + 1@ is ok for speculation: it has no
-- side effects, and can't diverge or raise an exception.
exprOkForSpeculation :: CoreExpr -> Bool
exprOkForSpeculation (Lit _)     = True
exprOkForSpeculation (Type _)    = True
    -- Tick boxes are *not* suitable for speculation
exprOkForSpeculation (Var v)     = isUnLiftedType (idType v)
				 && not (isTickBoxOp v)
exprOkForSpeculation (Note _ e)  = exprOkForSpeculation e
exprOkForSpeculation (Cast e _)  = exprOkForSpeculation e
exprOkForSpeculation other_expr
  = case collectArgs other_expr of
	(Var f, args) -> spec_ok (globalIdDetails f) args
        _             -> False
 
  where
    spec_ok (DataConWorkId _) _
      = True	-- The strictness of the constructor has already
		-- been expressed by its "wrapper", so we don't need
		-- to take the arguments into account

    spec_ok (PrimOpId op) args
      | isDivOp op,		-- Special case for dividing operations that fail
	[arg1, Lit lit] <- args	-- only if the divisor is zero
      = not (isZeroLit lit) && exprOkForSpeculation arg1
		-- Often there is a literal divisor, and this 
		-- can get rid of a thunk in an inner looop

      | otherwise
      = primOpOkForSpeculation op && 
	all exprOkForSpeculation args
				-- A bit conservative: we don't really need
				-- to care about lazy arguments, but this is easy

    spec_ok _ _ = False

-- | True of dyadic operators that can fail only if the second arg is zero!
isDivOp :: PrimOp -> Bool
-- This function probably belongs in PrimOp, or even in 
-- an automagically generated file.. but it's such a 
-- special case I thought I'd leave it here for now.
isDivOp IntQuotOp	 = True
isDivOp IntRemOp	 = True
isDivOp WordQuotOp	 = True
isDivOp WordRemOp	 = True
isDivOp IntegerQuotRemOp = True
isDivOp IntegerDivModOp  = True
isDivOp FloatDivOp       = True
isDivOp DoubleDivOp      = True
isDivOp _                = False
\end{code}

\begin{code}
-- | True of expressions that are guaranteed to diverge upon execution
exprIsBottom :: CoreExpr -> Bool
exprIsBottom e = go 0 e
               where
                -- n is the number of args
                 go n (Note _ e)     = go n e
                 go n (Cast e _)     = go n e
                 go n (Let _ e)      = go n e
                 go _ (Case e _ _ _) = go 0 e   -- Just check the scrut
                 go n (App e _)      = go (n+1) e
                 go n (Var v)        = idAppIsBottom v n
                 go _ (Lit _)        = False
                 go _ (Lam _ _)      = False
                 go _ (Type _)       = False

idAppIsBottom :: Id -> Int -> Bool
idAppIsBottom id n_val_args = appIsBottom (idNewStrictness id) n_val_args
\end{code}

\begin{code}

-- | This returns true for expressions that are certainly /already/ 
-- evaluated to /head/ normal form.  This is used to decide whether it's ok 
-- to change:
--
-- > case x of _ -> e
--
-- into:
--
-- > e
--
-- and to decide whether it's safe to discard a 'seq'.
-- So, it does /not/ treat variables as evaluated, unless they say they are.
-- However, it /does/ treat partial applications and constructor applications
-- as values, even if their arguments are non-trivial, provided the argument
-- type is lifted. For example, both of these are values:
--
-- > (:) (f x) (map f xs)
-- > map (...redex...)
--
-- Because 'seq' on such things completes immediately.
--
-- For unlifted argument types, we have to be careful:
--
-- > C (f x :: Int#)
--
-- Suppose @f x@ diverges; then @C (f x)@ is not a value. However this can't 
-- happen: see "CoreSyn#let_app_invariant". This invariant states that arguments of
-- unboxed type must be ok-for-speculation (or trivial).
exprIsHNF :: CoreExpr -> Bool		-- True => Value-lambda, constructor, PAP
exprIsHNF (Var v) 	-- NB: There are no value args at this point
  =  isDataConWorkId v 	-- Catches nullary constructors, 
			--	so that [] and () are values, for example
  || idArity v > 0 	-- Catches (e.g.) primops that don't have unfoldings
  || isEvaldUnfolding (idUnfolding v)
	-- Check the thing's unfolding; it might be bound to a value
	-- A worry: what if an Id's unfolding is just itself: 
	-- then we could get an infinite loop...

exprIsHNF (Lit _)          = True
exprIsHNF (Type _)         = True       -- Types are honorary Values;
                                        -- we don't mind copying them
exprIsHNF (Lam b e)        = isRuntimeVar b || exprIsHNF e
exprIsHNF (Note _ e)       = exprIsHNF e
exprIsHNF (Cast e _)       = exprIsHNF e
exprIsHNF (App e (Type _)) = exprIsHNF e
exprIsHNF (App e a)        = app_is_value e [a]
exprIsHNF _                = False

-- There is at least one value argument
app_is_value :: CoreExpr -> [CoreArg] -> Bool
app_is_value (Var fun) args
  = idArity fun > valArgCount args	-- Under-applied function
    ||  isDataConWorkId fun 		--  or data constructor
app_is_value (Note _ f) as = app_is_value f as
app_is_value (Cast f _) as = app_is_value f as
app_is_value (App f a)  as = app_is_value f (a:as)
app_is_value _          _  = False
\end{code}

These InstPat functions go here to avoid circularity between DataCon and Id

\begin{code}
dataConRepInstPat, dataConOrigInstPat :: [Unique] -> DataCon -> [Type] -> ([TyVar], [CoVar], [Id])
dataConRepFSInstPat :: [FastString] -> [Unique] -> DataCon -> [Type] -> ([TyVar], [CoVar], [Id])

dataConRepInstPat   = dataConInstPat dataConRepArgTys (repeat ((fsLit "ipv")))
dataConRepFSInstPat = dataConInstPat dataConRepArgTys
dataConOrigInstPat  = dataConInstPat dc_arg_tys       (repeat ((fsLit "ipv")))
  where 
    dc_arg_tys dc = map mkPredTy (dataConEqTheta dc) ++ map mkPredTy (dataConDictTheta dc) ++ dataConOrigArgTys dc
	-- Remember to include the existential dictionaries

dataConInstPat :: (DataCon -> [Type])      -- function used to find arg tys
                  -> [FastString]          -- A long enough list of FSs to use for names
                  -> [Unique]              -- An equally long list of uniques, at least one for each binder
                  -> DataCon
	          -> [Type]                -- Types to instantiate the universally quantified tyvars
	       -> ([TyVar], [CoVar], [Id]) -- Return instantiated variables
-- dataConInstPat arg_fun fss us con inst_tys returns a triple 
-- (ex_tvs, co_tvs, arg_ids),
--
--   ex_tvs are intended to be used as binders for existential type args
--
--   co_tvs are intended to be used as binders for coercion args and the kinds
--     of these vars have been instantiated by the inst_tys and the ex_tys
--     The co_tvs include both GADT equalities (dcEqSpec) and 
--     programmer-specified equalities (dcEqTheta)
--
--   arg_ids are indended to be used as binders for value arguments, 
--     and their types have been instantiated with inst_tys and ex_tys
--     The arg_ids include both dicts (dcDictTheta) and
--     programmer-specified arguments (after rep-ing) (deRepArgTys)
--
-- Example.
--  The following constructor T1
--
--  data T a where
--    T1 :: forall b. Int -> b -> T(a,b)
--    ...
--
--  has representation type 
--   forall a. forall a1. forall b. (a ~ (a1,b)) => 
--     Int -> b -> T a
--
--  dataConInstPat fss us T1 (a1',b') will return
--
--  ([a1'', b''], [c :: (a1', b')~(a1'', b'')], [x :: Int, y :: b''])
--
--  where the double-primed variables are created with the FastStrings and
--  Uniques given as fss and us
dataConInstPat arg_fun fss uniqs con inst_tys 
  = (ex_bndrs, co_bndrs, arg_ids)
  where 
    univ_tvs = dataConUnivTyVars con
    ex_tvs   = dataConExTyVars con
    arg_tys  = arg_fun con
    eq_spec  = dataConEqSpec con
    eq_theta = dataConEqTheta con
    eq_preds = eqSpecPreds eq_spec ++ eq_theta

    n_ex = length ex_tvs
    n_co = length eq_preds

      -- split the Uniques and FastStrings
    (ex_uniqs, uniqs')   = splitAt n_ex uniqs
    (co_uniqs, id_uniqs) = splitAt n_co uniqs'

    (ex_fss, fss')     = splitAt n_ex fss
    (co_fss, id_fss)   = splitAt n_co fss'

      -- Make existential type variables
    ex_bndrs = zipWith3 mk_ex_var ex_uniqs ex_fss ex_tvs
    mk_ex_var uniq fs var = mkTyVar new_name kind
      where
        new_name = mkSysTvName uniq fs
        kind     = tyVarKind var

      -- Make the instantiating substitution
    subst = zipOpenTvSubst (univ_tvs ++ ex_tvs) (inst_tys ++ map mkTyVarTy ex_bndrs)

      -- Make new coercion vars, instantiating kind
    co_bndrs = zipWith3 mk_co_var co_uniqs co_fss eq_preds
    mk_co_var uniq fs eq_pred = mkCoVar new_name co_kind
       where
         new_name = mkSysTvName uniq fs
         co_kind  = substTy subst (mkPredTy eq_pred)

      -- make value vars, instantiating types
    mk_id_var uniq fs ty = mkUserLocal (mkVarOccFS fs) uniq (substTy subst ty) noSrcSpan
    arg_ids = zipWith3 mk_id_var id_uniqs id_fss arg_tys

-- | Returns @Just (dc, [x1..xn])@ if the argument expression is 
-- a constructor application of the form @dc x1 .. xn@
exprIsConApp_maybe :: CoreExpr -> Maybe (DataCon, [CoreExpr])
exprIsConApp_maybe (Cast expr co)
  =     -- Here we do the KPush reduction rule as described in the FC paper
    case exprIsConApp_maybe expr of {
	Nothing 	   -> Nothing ;
	Just (dc, dc_args) -> 

	-- The transformation applies iff we have
	--	(C e1 ... en) `cast` co
	-- where co :: (T t1 .. tn) ~ (T s1 ..sn)
	-- That is, with a T at the top of both sides
	-- The left-hand one must be a T, because exprIsConApp returned True
	-- but the right-hand one might not be.  (Though it usually will.)

    let (from_ty, to_ty)	   = coercionKind co
	(from_tc, from_tc_arg_tys) = splitTyConApp from_ty
  		-- The inner one must be a TyConApp
    in
    case splitTyConApp_maybe to_ty of {
	Nothing -> Nothing ;
	Just (to_tc, to_tc_arg_tys) 
		| from_tc /= to_tc -> Nothing
		-- These two Nothing cases are possible; we might see 
		--	(C x y) `cast` (g :: T a ~ S [a]),
		-- where S is a type function.  In fact, exprIsConApp
		-- will probably not be called in such circumstances,
		-- but there't nothing wrong with it 

	 	| otherwise  ->
    let
	tc_arity = tyConArity from_tc

        (univ_args, rest1)        = splitAt tc_arity dc_args
        (ex_args, rest2)          = splitAt n_ex_tvs rest1
	(co_args_spec, rest3)     = splitAt n_cos_spec rest2
	(co_args_theta, val_args) = splitAt n_cos_theta rest3

        arg_tys 	    = dataConRepArgTys dc
	dc_univ_tyvars	    = dataConUnivTyVars dc
        dc_ex_tyvars        = dataConExTyVars dc
	dc_eq_spec	    = dataConEqSpec dc
        dc_eq_theta         = dataConEqTheta dc
        dc_tyvars           = dc_univ_tyvars ++ dc_ex_tyvars
        n_ex_tvs            = length dc_ex_tyvars
	n_cos_spec	    = length dc_eq_spec
	n_cos_theta	    = length dc_eq_theta

	-- Make the "theta" from Fig 3 of the paper
        gammas              = decomposeCo tc_arity co
        new_tys             = gammas ++ map (\ (Type t) -> t) ex_args
        theta               = zipOpenTvSubst dc_tyvars new_tys

          -- First we cast the existential coercion arguments
        cast_co_spec (tv, ty) co 
          = cast_co_theta (mkEqPred (mkTyVarTy tv, ty)) co
        cast_co_theta eqPred (Type co) 
          | (ty1, ty2) <- getEqPredTys eqPred
          = Type $ mkSymCoercion (substTy theta ty1)
		   `mkTransCoercion` co
		   `mkTransCoercion` (substTy theta ty2)
        new_co_args = zipWith cast_co_spec  dc_eq_spec  co_args_spec ++
                      zipWith cast_co_theta dc_eq_theta co_args_theta
  
          -- ...and now value arguments
	new_val_args = zipWith cast_arg arg_tys val_args
	cast_arg arg_ty arg = mkCoerce (substTy theta arg_ty) arg

    in
    ASSERT( length univ_args == tc_arity )
    ASSERT( from_tc == dataConTyCon dc )
    ASSERT( and (zipWith coreEqType [t | Type t <- univ_args] from_tc_arg_tys) )
    ASSERT( all isTypeArg (univ_args ++ ex_args) )
    ASSERT2( equalLength val_args arg_tys, ppr dc $$ ppr dc_tyvars $$ ppr dc_ex_tyvars $$ ppr arg_tys $$ ppr dc_args $$ ppr univ_args $$ ppr ex_args $$ ppr val_args $$ ppr arg_tys  )

    Just (dc, map Type to_tc_arg_tys ++ ex_args ++ new_co_args ++ new_val_args)
    }}

{-
-- We do not want to tell the world that we have a
-- Cons, to *stop* Case of Known Cons, which removes
-- the TickBox.
exprIsConApp_maybe (Note (TickBox {}) expr)
  = Nothing
exprIsConApp_maybe (Note (BinaryTickBox {}) expr)
  = Nothing
-}

exprIsConApp_maybe (Note _ expr)
  = exprIsConApp_maybe expr
    -- We ignore InlineMe notes in case we have
    --	x = __inline_me__ (a,b)
    -- All part of making sure that INLINE pragmas never hurt
    -- Marcin tripped on this one when making dictionaries more inlinable
    --
    -- In fact, we ignore all notes.  For example,
    --  	case _scc_ "foo" (C a b) of
    --			C a b -> e
    -- should be optimised away, but it will be only if we look
    -- through the SCC note.

exprIsConApp_maybe expr = analyse (collectArgs expr)
  where
    analyse (Var fun, args)
	| Just con <- isDataConWorkId_maybe fun,
	  args `lengthAtLeast` dataConRepArity con
		-- Might be > because the arity excludes type args
	= Just (con,args)

	-- Look through unfoldings, but only cheap ones, because
	-- we are effectively duplicating the unfolding
    analyse (Var fun, [])
	| let unf = idUnfolding fun,
	  isCheapUnfolding unf
	= exprIsConApp_maybe (unfoldingTemplate unf)

    analyse _ = Nothing
\end{code}



%************************************************************************
%*									*
\subsection{Eta reduction and expansion}
%*									*
%************************************************************************

\begin{code}
-- ^ The Arity returned is the number of value args the 
-- expression can be applied to without doing much work
exprEtaExpandArity :: DynFlags -> CoreExpr -> Arity
{- 
exprEtaExpandArity is used when eta expanding
	e  ==>  \xy -> e x y

It returns 1 (or more) to:
	case x of p -> \s -> ...
because for I/O ish things we really want to get that \s to the top.
We are prepared to evaluate x each time round the loop in order to get that

It's all a bit more subtle than it looks:

1.  One-shot lambdas

Consider one-shot lambdas
		let x = expensive in \y z -> E
We want this to have arity 2 if the \y-abstraction is a 1-shot lambda
Hence the ArityType returned by arityType

2.  The state-transformer hack

The one-shot lambda special cause is particularly important/useful for
IO state transformers, where we often get
	let x = E in \ s -> ...

and the \s is a real-world state token abstraction.  Such abstractions
are almost invariably 1-shot, so we want to pull the \s out, past the
let x=E, even if E is expensive.  So we treat state-token lambdas as 
one-shot even if they aren't really.  The hack is in Id.isOneShotBndr.

3.  Dealing with bottom

Consider also 
	f = \x -> error "foo"
Here, arity 1 is fine.  But if it is
	f = \x -> case x of 
			True  -> error "foo"
			False -> \y -> x+y
then we want to get arity 2.  Tecnically, this isn't quite right, because
	(f True) `seq` 1
should diverge, but it'll converge if we eta-expand f.  Nevertheless, we
do so; it improves some programs significantly, and increasing convergence
isn't a bad thing.  Hence the ABot/ATop in ArityType.

Actually, the situation is worse.  Consider
	f = \x -> case x of
			True  -> \y -> x+y
			False -> \y -> x-y
Can we eta-expand here?  At first the answer looks like "yes of course", but
consider
	(f bot) `seq` 1
This should diverge!  But if we eta-expand, it won't.   Again, we ignore this
"problem", because being scrupulous would lose an important transformation for
many programs.


4. Newtypes

Non-recursive newtypes are transparent, and should not get in the way.
We do (currently) eta-expand recursive newtypes too.  So if we have, say

	newtype T = MkT ([T] -> Int)

Suppose we have
	e = coerce T f
where f has arity 1.  Then: etaExpandArity e = 1; 
that is, etaExpandArity looks through the coerce.

When we eta-expand e to arity 1: eta_expand 1 e T
we want to get: 		 coerce T (\x::[T] -> (coerce ([T]->Int) e) x)

HOWEVER, note that if you use coerce bogusly you can ge
	coerce Int negate
And since negate has arity 2, you might try to eta expand.  But you can't
decopose Int to a function type.   Hence the final case in eta_expand.
-}


exprEtaExpandArity dflags e = arityDepth (arityType dflags e)

-- A limited sort of function type
data ArityType = AFun Bool ArityType	-- True <=> one-shot
	       | ATop			-- Know nothing
	       | ABot			-- Diverges

arityDepth :: ArityType -> Arity
arityDepth (AFun _ ty) = 1 + arityDepth ty
arityDepth _           = 0

andArityType :: ArityType -> ArityType -> ArityType
andArityType ABot           at2           = at2
andArityType ATop           _             = ATop
andArityType (AFun t1 at1)  (AFun t2 at2) = AFun (t1 && t2) (andArityType at1 at2)
andArityType at1            at2           = andArityType at2 at1

arityType :: DynFlags -> CoreExpr -> ArityType
	-- (go1 e) = [b1,..,bn]
	-- means expression can be rewritten \x_b1 -> ... \x_bn -> body
	-- where bi is True <=> the lambda is one-shot

arityType dflags (Note _ e) = arityType dflags e
--	Not needed any more: etaExpand is cleverer
-- removed: | ok_note n = arityType dflags e
-- removed: | otherwise = ATop

arityType dflags (Cast e _) = arityType dflags e

arityType _ (Var v)
  = mk (idArity v) (arg_tys (idType v))
  where
    mk :: Arity -> [Type] -> ArityType
	-- The argument types are only to steer the "state hack"
	-- Consider case x of
	--		True  -> foo
	--		False -> \(s:RealWorld) -> e
	-- where foo has arity 1.  Then we want the state hack to
	-- apply to foo too, so we can eta expand the case.
    mk 0 tys | isBottomingId v                   = ABot
             | (ty:_) <- tys, isStateHackType ty = AFun True ATop
             | otherwise                         = ATop
    mk n (ty:tys) = AFun (isStateHackType ty) (mk (n-1) tys)
    mk n []       = AFun False		      (mk (n-1) [])

    arg_tys :: Type -> [Type]	-- Ignore for-alls
    arg_tys ty 
	| Just (_, ty')  <- splitForAllTy_maybe ty = arg_tys ty'
	| Just (arg,res) <- splitFunTy_maybe ty    = arg : arg_tys res
	| otherwise				   = []

	-- Lambdas; increase arity
arityType dflags (Lam x e)
  | isId x    = AFun (isOneShotBndr x) (arityType dflags e)
  | otherwise = arityType dflags e

	-- Applications; decrease arity
arityType dflags (App f (Type _)) = arityType dflags f
arityType dflags (App f a)
   = case arityType dflags f of
	ABot -> ABot	-- If function diverges, ignore argument
	ATop -> ATop	-- No no info about function
	AFun _ xs
		| exprIsCheap a -> xs
		| otherwise	-> ATop
							   
	-- Case/Let; keep arity if either the expression is cheap
	-- or it's a 1-shot lambda
	-- The former is not really right for Haskell
	--	f x = case x of { (a,b) -> \y. e }
	--  ===>
	--	f x y = case x of { (a,b) -> e }
	-- The difference is observable using 'seq'
arityType dflags (Case scrut _ _ alts)
  = case foldr1 andArityType [arityType dflags rhs | (_,_,rhs) <- alts] of
        xs | exprIsCheap scrut     -> xs
        AFun one_shot _ | one_shot -> AFun True ATop
        _                          -> ATop

arityType dflags (Let b e) 
  = case arityType dflags e of
        xs              | cheap_bind b -> xs
        AFun one_shot _ | one_shot     -> AFun True ATop
        _                              -> ATop
  where
    cheap_bind (NonRec b e) = is_cheap (b,e)
    cheap_bind (Rec prs)    = all is_cheap prs
    is_cheap (b,e) = (dopt Opt_DictsCheap dflags && isDictId b)
		   || exprIsCheap e
	-- If the experimental -fdicts-cheap flag is on, we eta-expand through
	-- dictionary bindings.  This improves arities. Thereby, it also
	-- means that full laziness is less prone to floating out the
	-- application of a function to its dictionary arguments, which
	-- can thereby lose opportunities for fusion.  Example:
	-- 	foo :: Ord a => a -> ...
	--	foo = /\a \(d:Ord a). let d' = ...d... in \(x:a). ....
	--		-- So foo has arity 1
	--
	--	f = \x. foo dInt $ bar x
	--
	-- The (foo DInt) is floated out, and makes ineffective a RULE 
	--	foo (bar x) = ...
	--
	-- One could go further and make exprIsCheap reply True to any
	-- dictionary-typed expression, but that's more work.

arityType _ _ = ATop

{- NOT NEEDED ANY MORE: etaExpand is cleverer
ok_note InlineMe = False
ok_note other    = True
    -- Notice that we do not look through __inline_me__
    -- This may seem surprising, but consider
    --		f = _inline_me (\x -> e)
    -- We DO NOT want to eta expand this to
    --		f = \x -> (_inline_me (\x -> e)) x
    -- because the _inline_me gets dropped now it is applied, 
    -- giving just
    --		f = \x -> e
    -- A Bad Idea
-}
\end{code}


\begin{code}
-- | @etaExpand n us e ty@ returns an expression with
-- the same meaning as @e@, but with arity @n@.
--
-- Given:
--
-- > e' = etaExpand n us e ty
--
-- We should have that:
--
-- > ty = exprType e = exprType e'
etaExpand :: Arity	  	-- ^ Result should have this number of value args
	  -> [Unique]           -- ^ Uniques to assign to the new binders
	  -> CoreExpr	        -- ^ Expression to expand
	  -> Type               -- ^ Type of expression to expand
	  -> CoreExpr
-- Note that SCCs are not treated specially.  If we have
--	etaExpand 2 (\x -> scc "foo" e)
--	= (\xy -> (scc "foo" e) y)
-- So the costs of evaluating 'e' (not 'e y') are attributed to "foo"

etaExpand n us expr ty
  | manifestArity expr >= n = expr		-- The no-op case
  | otherwise 		    
  = eta_expand n us expr ty

-- manifestArity sees how many leading value lambdas there are
manifestArity :: CoreExpr -> Arity
manifestArity (Lam v e) | isId v    = 1 + manifestArity e
			| otherwise = manifestArity e
manifestArity (Note _ e)	    = manifestArity e
manifestArity (Cast e _)            = manifestArity e
manifestArity _                     = 0

-- etaExpand deals with for-alls. For example:
--		etaExpand 1 E
-- where  E :: forall a. a -> a
-- would return
--	(/\b. \y::a -> E b y)
--
-- It deals with coerces too, though they are now rare
-- so perhaps the extra code isn't worth it
eta_expand :: Int -> [Unique] -> CoreExpr -> Type -> CoreExpr

eta_expand n _ expr ty
  | n == 0 && 
    -- The ILX code generator requires eta expansion for type arguments
    -- too, but alas the 'n' doesn't tell us how many of them there 
    -- may be.  So we eagerly eta expand any big lambdas, and just
    -- cross our fingers about possible loss of sharing in the ILX case. 
    -- The Right Thing is probably to make 'arity' include
    -- type variables throughout the compiler.  (ToDo.)
    not (isForAllTy ty)	
    -- Saturated, so nothing to do
  = expr

	-- Short cut for the case where there already
	-- is a lambda; no point in gratuitously adding more
eta_expand n us (Lam v body) ty
  | isTyVar v
  = Lam v (eta_expand n us body (applyTy ty (mkTyVarTy v)))

  | otherwise
  = Lam v (eta_expand (n-1) us body (funResultTy ty))

-- We used to have a special case that stepped inside Coerces here,
-- thus:  eta_expand n us (Note note@(Coerce _ ty) e) _  
--		= Note note (eta_expand n us e ty)
-- BUT this led to an infinite loop
-- Example: 	newtype T = MkT (Int -> Int)
--	eta_expand 1 (coerce (Int->Int) e)
--	--> coerce (Int->Int) (eta_expand 1 T e)
--		by the bogus eqn
--	--> coerce (Int->Int) (coerce T 
--		(\x::Int -> eta_expand 1 (coerce (Int->Int) e)))
--		by the splitNewType_maybe case below
--	and round we go

eta_expand n us expr ty
  = ASSERT2 (exprType expr `coreEqType` ty, ppr (exprType expr) $$ ppr ty)
    case splitForAllTy_maybe ty of { 
 	  Just (tv,ty') -> 

              Lam lam_tv (eta_expand n us2 (App expr (Type (mkTyVarTy lam_tv))) (substTyWith [tv] [mkTyVarTy lam_tv] ty'))
                  where 
                    lam_tv = setVarName tv (mkSysTvName uniq (fsLit "etaT"))
			-- Using tv as a base retains its tyvar/covar-ness
                    (uniq:us2) = us 
 	; Nothing ->
  
    	case splitFunTy_maybe ty of {
 	  Just (arg_ty, res_ty) -> Lam arg1 (eta_expand (n-1) us2 (App expr (Var arg1)) res_ty)
				where
				   arg1	      = mkSysLocal (fsLit "eta") uniq arg_ty
 				   (uniq:us2) = us
				   
	; Nothing ->

		-- Given this:
		-- 	newtype T = MkT ([T] -> Int)
		-- Consider eta-expanding this
		--  	eta_expand 1 e T
		-- We want to get
		--	coerce T (\x::[T] -> (coerce ([T]->Int) e) x)

    	case splitNewTypeRepCo_maybe ty of {
 	  Just(ty1,co) -> mkCoerce (mkSymCoercion co) 
				   (eta_expand n us (mkCoerce co expr) ty1) ;
 	  Nothing  -> 

	-- We have an expression of arity > 0, but its type isn't a function
	-- This *can* legitmately happen: e.g. 	coerce Int (\x. x)
	-- Essentially the programmer is playing fast and loose with types
	-- (Happy does this a lot).  So we simply decline to eta-expand.
	-- Otherwise we'd end up with an explicit lambda having a non-function type
	expr
    	}}}
\end{code}

exprArity is a cheap-and-cheerful version of exprEtaExpandArity.
It tells how many things the expression can be applied to before doing
any work.  It doesn't look inside cases, lets, etc.  The idea is that
exprEtaExpandArity will do the hard work, leaving something that's easy
for exprArity to grapple with.  In particular, Simplify uses exprArity to
compute the ArityInfo for the Id. 

Originally I thought that it was enough just to look for top-level lambdas, but
it isn't.  I've seen this

	foo = PrelBase.timesInt

We want foo to get arity 2 even though the eta-expander will leave it
unchanged, in the expectation that it'll be inlined.  But occasionally it
isn't, because foo is blacklisted (used in a rule).  

Similarly, see the ok_note check in exprEtaExpandArity.  So 
	f = __inline_me (\x -> e)
won't be eta-expanded.

And in any case it seems more robust to have exprArity be a bit more intelligent.
But note that 	(\x y z -> f x y z)
should have arity 3, regardless of f's arity.

Note [exprArity invariant]
~~~~~~~~~~~~~~~~~~~~~~~~~~
exprArity has the following invariant:
	(exprArity e) = n, then manifestArity (etaExpand e n) = n

That is, if exprArity says "the arity is n" then etaExpand really can get
"n" manifest lambdas to the top.

Why is this important?  Because 
  - In TidyPgm we use exprArity to fix the *final arity* of 
    each top-level Id, and in
  - In CorePrep we use etaExpand on each rhs, so that the visible lambdas
    actually match that arity, which in turn means
    that the StgRhs has the right number of lambdas

An alternative would be to do the eta-expansion in TidyPgm, at least
for top-level bindings, in which case we would not need the trim_arity
in exprArity.  That is a less local change, so I'm going to leave it for today!


\begin{code}
-- | An approximate, fast, version of 'exprEtaExpandArity'
exprArity :: CoreExpr -> Arity
exprArity e = go e
  where
    go (Var v) 	       	         = idArity v
    go (Lam x e) | isId x    	 = go e + 1
    		 | otherwise 	 = go e
    go (Note _ e)                = go e
    go (Cast e co)               = trim_arity (go e) 0 (snd (coercionKind co))
    go (App e (Type _))          = go e
    go (App f a) | exprIsCheap a = (go f - 1) `max` 0
    	-- NB: exprIsCheap a!  
    	--	f (fac x) does not have arity 2, 
    	-- 	even if f has arity 3!
    	-- NB: `max 0`!  (\x y -> f x) has arity 2, even if f is
    	--		 unknown, hence arity 0
    go _		       	   = 0

	-- Note [exprArity invariant]
    trim_arity n a ty
	| n==a					      = a
	| Just (_, ty') <- splitForAllTy_maybe ty     = trim_arity n a     ty'
	| Just (_, ty') <- splitFunTy_maybe ty        = trim_arity n (a+1) ty'
	| Just (ty',_)  <- splitNewTypeRepCo_maybe ty = trim_arity n a     ty'
	| otherwise				      = a
\end{code}

%************************************************************************
%*									*
\subsection{Equality}
%*									*
%************************************************************************

\begin{code}
-- | A cheap equality test which bales out fast!
--      If it returns @True@ the arguments are definitely equal,
--      otherwise, they may or may not be equal.
--
-- See also 'exprIsBig'
cheapEqExpr :: Expr b -> Expr b -> Bool

cheapEqExpr (Var v1)   (Var v2)   = v1==v2
cheapEqExpr (Lit lit1) (Lit lit2) = lit1 == lit2
cheapEqExpr (Type t1)  (Type t2)  = t1 `coreEqType` t2

cheapEqExpr (App f1 a1) (App f2 a2)
  = f1 `cheapEqExpr` f2 && a1 `cheapEqExpr` a2

cheapEqExpr (Cast e1 t1) (Cast e2 t2)
  = e1 `cheapEqExpr` e2 && t1 `coreEqCoercion` t2

cheapEqExpr _ _ = False

exprIsBig :: Expr b -> Bool
-- ^ Returns @True@ of expressions that are too big to be compared by 'cheapEqExpr'
exprIsBig (Lit _)      = False
exprIsBig (Var _)      = False
exprIsBig (Type _)     = False
exprIsBig (App f a)    = exprIsBig f || exprIsBig a
exprIsBig (Cast e _)   = exprIsBig e	-- Hopefully coercions are not too big!
exprIsBig _            = True
\end{code}


\begin{code}
tcEqExpr :: CoreExpr -> CoreExpr -> Bool
-- ^ A kind of shallow equality used in rule matching, so does 
-- /not/ look through newtypes or predicate types

tcEqExpr e1 e2 = tcEqExprX rn_env e1 e2
  where
    rn_env = mkRnEnv2 (mkInScopeSet (exprFreeVars e1 `unionVarSet` exprFreeVars e2))

tcEqExprX :: RnEnv2 -> CoreExpr -> CoreExpr -> Bool
tcEqExprX env (Var v1)	   (Var v2)	= rnOccL env v1 == rnOccR env v2
tcEqExprX _   (Lit lit1)   (Lit lit2)   = lit1 == lit2
tcEqExprX env (App f1 a1)  (App f2 a2)  = tcEqExprX env f1 f2 && tcEqExprX env a1 a2
tcEqExprX env (Lam v1 e1)  (Lam v2 e2)  = tcEqExprX (rnBndr2 env v1 v2) e1 e2
tcEqExprX env (Let (NonRec v1 r1) e1)
	      (Let (NonRec v2 r2) e2)   = tcEqExprX env r1 r2 
				       && tcEqExprX (rnBndr2 env v1 v2) e1 e2
tcEqExprX env (Let (Rec ps1) e1)
	      (Let (Rec ps2) e2)        =  equalLength ps1 ps2
				        && and (zipWith eq_rhs ps1 ps2)
				        && tcEqExprX env' e1 e2
				     where
				       env' = foldl2 rn_bndr2 env ps2 ps2
				       rn_bndr2 env (b1,_) (b2,_) = rnBndr2 env b1 b2
				       eq_rhs       (_,r1) (_,r2) = tcEqExprX env' r1 r2
tcEqExprX env (Case e1 v1 t1 a1)
	      (Case e2 v2 t2 a2)     =  tcEqExprX env e1 e2
                                     && tcEqTypeX env t1 t2                      
				     && equalLength a1 a2
				     && and (zipWith (eq_alt env') a1 a2)
				     where
				       env' = rnBndr2 env v1 v2

tcEqExprX env (Note n1 e1)  (Note n2 e2)  = eq_note env n1 n2 && tcEqExprX env e1 e2
tcEqExprX env (Cast e1 co1) (Cast e2 co2) = tcEqTypeX env co1 co2 && tcEqExprX env e1 e2
tcEqExprX env (Type t1)     (Type t2)     = tcEqTypeX env t1 t2
tcEqExprX _   _             _             = False

eq_alt :: RnEnv2 -> CoreAlt -> CoreAlt -> Bool
eq_alt env (c1,vs1,r1) (c2,vs2,r2) = c1==c2 && tcEqExprX (rnBndrs2 env vs1  vs2) r1 r2

eq_note :: RnEnv2 -> Note -> Note -> Bool
eq_note _ (SCC cc1)     (SCC cc2)      = cc1 == cc2
eq_note _ (CoreNote s1) (CoreNote s2)  = s1 == s2
eq_note _ _             _              = False
\end{code}


%************************************************************************
%*									*
\subsection{The size of an expression}
%*									*
%************************************************************************

\begin{code}
coreBindsSize :: [CoreBind] -> Int
coreBindsSize bs = foldr ((+) . bindSize) 0 bs

exprSize :: CoreExpr -> Int
-- ^ A measure of the size of the expressions, strictly greater than 0
-- It also forces the expression pretty drastically as a side effect
exprSize (Var v)         = v `seq` 1
exprSize (Lit lit)       = lit `seq` 1
exprSize (App f a)       = exprSize f + exprSize a
exprSize (Lam b e)       = varSize b + exprSize e
exprSize (Let b e)       = bindSize b + exprSize e
exprSize (Case e b t as) = seqType t `seq` exprSize e + varSize b + 1 + foldr ((+) . altSize) 0 as
exprSize (Cast e co)     = (seqType co `seq` 1) + exprSize e
exprSize (Note n e)      = noteSize n + exprSize e
exprSize (Type t)        = seqType t `seq` 1

noteSize :: Note -> Int
noteSize (SCC cc)       = cc `seq` 1
noteSize InlineMe       = 1
noteSize (CoreNote s)   = s `seq` 1  -- hdaume: core annotations
 
varSize :: Var -> Int
varSize b  | isTyVar b = 1
	   | otherwise = seqType (idType b)		`seq`
			 megaSeqIdInfo (idInfo b) 	`seq`
			 1

varsSize :: [Var] -> Int
varsSize = sum . map varSize

bindSize :: CoreBind -> Int
bindSize (NonRec b e) = varSize b + exprSize e
bindSize (Rec prs)    = foldr ((+) . pairSize) 0 prs

pairSize :: (Var, CoreExpr) -> Int
pairSize (b,e) = varSize b + exprSize e

altSize :: CoreAlt -> Int
altSize (c,bs,e) = c `seq` varsSize bs + exprSize e
\end{code}


%************************************************************************
%*									*
\subsection{Hashing}
%*									*
%************************************************************************

\begin{code}
hashExpr :: CoreExpr -> Int
-- ^ Two expressions that hash to the same @Int@ may be equal (but may not be)
-- Two expressions that hash to the different Ints are definitely unequal.
--
-- The emphasis is on a crude, fast hash, rather than on high precision.
-- 
-- But unequal here means \"not identical\"; two alpha-equivalent 
-- expressions may hash to the different Ints.
--
-- We must be careful that @\\x.x@ and @\\y.y@ map to the same hash code,
-- (at least if we want the above invariant to be true).

hashExpr e = fromIntegral (hash_expr (1,emptyVarEnv) e .&. 0x7fffffff)
             -- UniqFM doesn't like negative Ints

type HashEnv = (Int, VarEnv Int)  -- Hash code for bound variables

hash_expr :: HashEnv -> CoreExpr -> Word32
-- Word32, because we're expecting overflows here, and overflowing
-- signed types just isn't cool.  In C it's even undefined.
hash_expr env (Note _ e)   	      = hash_expr env e
hash_expr env (Cast e _)              = hash_expr env e
hash_expr env (Var v)     	      = hashVar env v
hash_expr _   (Lit lit)               = fromIntegral (hashLiteral lit)
hash_expr env (App f e)   	      = hash_expr env f * fast_hash_expr env e
hash_expr env (Let (NonRec b r) e)    = hash_expr (extend_env env b) e * fast_hash_expr env r
hash_expr env (Let (Rec ((b,_):_)) e) = hash_expr (extend_env env b) e
hash_expr env (Case e _ _ _)	      = hash_expr env e
hash_expr env (Lam b e)	              = hash_expr (extend_env env b) e
hash_expr _   (Type _)                = WARN(True, text "hash_expr: type") 1
-- Shouldn't happen.  Better to use WARN than trace, because trace
-- prevents the CPR optimisation kicking in for hash_expr.

fast_hash_expr :: HashEnv -> CoreExpr -> Word32
fast_hash_expr env (Var v)     	= hashVar env v
fast_hash_expr env (Type t)	= fast_hash_type env t
fast_hash_expr _   (Lit lit)    = fromIntegral (hashLiteral lit)
fast_hash_expr env (Cast e _)   = fast_hash_expr env e
fast_hash_expr env (Note _ e)   = fast_hash_expr env e
fast_hash_expr env (App _ a)    = fast_hash_expr env a	-- A bit idiosyncratic ('a' not 'f')!
fast_hash_expr _   _            = 1

fast_hash_type :: HashEnv -> Type -> Word32
fast_hash_type env ty 
  | Just tv <- getTyVar_maybe ty            = hashVar env tv
  | Just (tc,tys) <- splitTyConApp_maybe ty = let hash_tc = fromIntegral (hashName (tyConName tc))
					      in foldr (\t n -> fast_hash_type env t + n) hash_tc tys
  | otherwise				    = 1

extend_env :: HashEnv -> Var -> (Int, VarEnv Int)
extend_env (n,env) b = (n+1, extendVarEnv env b n)

hashVar :: HashEnv -> Var -> Word32
hashVar (_,env) v
 = fromIntegral (lookupVarEnv env v `orElse` hashName (idName v))
\end{code}

%************************************************************************
%*									*
\subsection{Determining non-updatable right-hand-sides}
%*									*
%************************************************************************

Top-level constructor applications can usually be allocated
statically, but they can't if the constructor, or any of the
arguments, come from another DLL (because we can't refer to static
labels in other DLLs).

If this happens we simply make the RHS into an updatable thunk, 
and 'execute' it rather than allocating it statically.

\begin{code}
-- | This function is called only on *top-level* right-hand sides.
-- Returns @True@ if the RHS can be allocated statically in the output,
-- with no thunks involved at all.
rhsIsStatic :: PackageId -> CoreExpr -> Bool
-- It's called (i) in TidyPgm.hasCafRefs to decide if the rhs is, or
-- refers to, CAFs; (ii) in CoreToStg to decide whether to put an
-- update flag on it and (iii) in DsExpr to decide how to expand
-- list literals
--
-- The basic idea is that rhsIsStatic returns True only if the RHS is
--	(a) a value lambda
--	(b) a saturated constructor application with static args
--
-- BUT watch out for
--  (i)	Any cross-DLL references kill static-ness completely
--	because they must be 'executed' not statically allocated
--      ("DLL" here really only refers to Windows DLLs, on other platforms,
--      this is not necessary)
--
-- (ii) We treat partial applications as redexes, because in fact we 
--	make a thunk for them that runs and builds a PAP
-- 	at run-time.  The only appliations that are treated as 
--	static are *saturated* applications of constructors.

-- We used to try to be clever with nested structures like this:
--		ys = (:) w ((:) w [])
-- on the grounds that CorePrep will flatten ANF-ise it later.
-- But supporting this special case made the function much more 
-- complicated, because the special case only applies if there are no 
-- enclosing type lambdas:
--		ys = /\ a -> Foo (Baz ([] a))
-- Here the nested (Baz []) won't float out to top level in CorePrep.
--
-- But in fact, even without -O, nested structures at top level are 
-- flattened by the simplifier, so we don't need to be super-clever here.
--
-- Examples
--
--	f = \x::Int. x+7	TRUE
--	p = (True,False)	TRUE
--
--	d = (fst p, False)	FALSE because there's a redex inside
--				(this particular one doesn't happen but...)
--
--	h = D# (1.0## /## 2.0##)	FALSE (redex again)
--	n = /\a. Nil a			TRUE
--
--	t = /\a. (:) (case w a of ...) (Nil a)	FALSE (redex)
--
--
-- This is a bit like CoreUtils.exprIsHNF, with the following differences:
--    a) scc "foo" (\x -> ...) is updatable (so we catch the right SCC)
--
--    b) (C x xs), where C is a contructors is updatable if the application is
--	   dynamic
-- 
--    c) don't look through unfolding of f in (f x).

rhsIsStatic _this_pkg rhs = is_static False rhs
  where
  is_static :: Bool	-- True <=> in a constructor argument; must be atomic
  	  -> CoreExpr -> Bool
  
  is_static False (Lam b e) = isRuntimeVar b || is_static False e
  
  is_static _      (Note (SCC _) _) = False
  is_static in_arg (Note _ e)       = is_static in_arg e
  is_static in_arg (Cast e _)       = is_static in_arg e
  
  is_static _      (Lit lit)
    = case lit of
  	MachLabel _ _ _ -> False
        _             -> True
  	-- A MachLabel (foreign import "&foo") in an argument
  	-- prevents a constructor application from being static.  The
  	-- reason is that it might give rise to unresolvable symbols
  	-- in the object file: under Linux, references to "weak"
  	-- symbols from the data segment give rise to "unresolvable
  	-- relocation" errors at link time This might be due to a bug
  	-- in the linker, but we'll work around it here anyway. 
  	-- SDM 24/2/2004
  
  is_static in_arg other_expr = go other_expr 0
   where
    go (Var f) n_val_args
#if mingw32_TARGET_OS
        | not (isDllName _this_pkg (idName f))
#endif
	=  saturated_data_con f n_val_args
	|| (in_arg && n_val_args == 0)	
		-- A naked un-applied variable is *not* deemed a static RHS
		-- E.g.		f = g
		-- Reason: better to update so that the indirection gets shorted
		-- 	   out, and the true value will be seen
		-- NB: if you change this, you'll break the invariant that THUNK_STATICs
		--     are always updatable.  If you do so, make sure that non-updatable
		--     ones have enough space for their static link field!

    go (App f a) n_val_args
	| isTypeArg a 			 = go f n_val_args
	| not in_arg && is_static True a = go f (n_val_args + 1)
	-- The (not in_arg) checks that we aren't in a constructor argument;
	-- if we are, we don't allow (value) applications of any sort
	-- 
        -- NB. In case you wonder, args are sometimes not atomic.  eg.
        --   x = D# (1.0## /## 2.0##)
        -- can't float because /## can fail.

    go (Note (SCC _) _) _          = False
    go (Note _ f)       n_val_args = go f n_val_args
    go (Cast e _)       n_val_args = go e n_val_args

    go _                _          = False

    saturated_data_con f n_val_args
	= case isDataConWorkId_maybe f of
	    Just dc -> n_val_args == dataConRepArity dc
	    Nothing -> False
\end{code}
