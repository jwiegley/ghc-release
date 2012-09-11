%
% (c) The University of Glasgow, 1994-2006
%

Core pass to saturate constructors and PrimOps

\begin{code}
module CorePrep (
      corePrepPgm, corePrepExpr
  ) where

#include "HsVersions.h"

import PrelNames	( lazyIdKey, hasKey )
import CoreUtils
import CoreArity
import CoreFVs
import CoreLint
import CoreSyn
import Type
import Coercion
import TyCon
import NewDemand
import Var
import VarSet
import VarEnv
import Id
import IdInfo
import DataCon
import PrimOp
import BasicTypes
import UniqSupply
import Maybes
import OrdList
import ErrUtils
import DynFlags
import Util
import Outputable
import MonadUtils
import FastString
import Control.Monad
\end{code}

-- ---------------------------------------------------------------------------
-- Overview
-- ---------------------------------------------------------------------------

The goal of this pass is to prepare for code generation.

1.  Saturate constructor and primop applications.

2.  Convert to A-normal form; that is, function arguments
    are always variables.

    * Use case for strict arguments:
	f E ==> case E of x -> f x
    	(where f is strict)

    * Use let for non-trivial lazy arguments
	f E ==> let x = E in f x
	(were f is lazy and x is non-trivial)

3.  Similarly, convert any unboxed lets into cases.
    [I'm experimenting with leaving 'ok-for-speculation' 
     rhss in let-form right up to this point.]

4.  Ensure that *value* lambdas only occur as the RHS of a binding
    (The code generator can't deal with anything else.)
    Type lambdas are ok, however, because the code gen discards them.

5.  [Not any more; nuked Jun 2002] Do the seq/par munging.

6.  Clone all local Ids.
    This means that all such Ids are unique, rather than the 
    weaker guarantee of no clashes which the simplifier provides.
    And that is what the code generator needs.

    We don't clone TyVars. The code gen doesn't need that, 
    and doing so would be tiresome because then we'd need
    to substitute in types.


7.  Give each dynamic CCall occurrence a fresh unique; this is
    rather like the cloning step above.

8.  Inject bindings for the "implicit" Ids:
	* Constructor wrappers
	* Constructor workers
    We want curried definitions for all of these in case they
    aren't inlined by some caller.
	
9.  Replace (lazy e) by e.  See Note [lazyId magic] in MkId.lhs

This is all done modulo type applications and abstractions, so that
when type erasure is done for conversion to STG, we don't end up with
any trivial or useless bindings.

  
Invariants
~~~~~~~~~~
Here is the syntax of the Core produced by CorePrep:

    Trivial expressions 
       triv ::= lit |  var  | triv ty  |  /\a. triv  |  triv |> co

    Applications
       app ::= lit  |  var  |  app triv  |  app ty  |  app |> co

    Expressions
       body ::= app  
              | let(rec) x = rhs in body     -- Boxed only
              | case body of pat -> body
	      | /\a. body
              | body |> co

    Right hand sides (only place where lambdas can occur)
       rhs ::= /\a.rhs  |  \x.rhs  |  body

We define a synonym for each of these non-terminals.  Functions
with the corresponding name produce a result in that syntax.

\begin{code}
type CpeTriv = CoreExpr	   -- Non-terminal 'triv'
type CpeApp  = CoreExpr	   -- Non-terminal 'app'
type CpeBody = CoreExpr	   -- Non-terminal 'body'
type CpeRhs  = CoreExpr	   -- Non-terminal 'rhs'
\end{code}

%************************************************************************
%*									*
		Top level stuff
%*									*
%************************************************************************

\begin{code}
corePrepPgm :: DynFlags -> [CoreBind] -> [TyCon] -> IO [CoreBind]
corePrepPgm dflags binds data_tycons = do
    showPass dflags "CorePrep"
    us <- mkSplitUniqSupply 's'

    let implicit_binds = mkDataConWorkers data_tycons
            -- NB: we must feed mkImplicitBinds through corePrep too
            -- so that they are suitably cloned and eta-expanded

        binds_out = initUs_ us $ do
                      floats1 <- corePrepTopBinds binds
                      floats2 <- corePrepTopBinds implicit_binds
                      return (deFloatTop (floats1 `appendFloats` floats2))

    endPass dflags "CorePrep" Opt_D_dump_prep binds_out
    return binds_out

corePrepExpr :: DynFlags -> CoreExpr -> IO CoreExpr
corePrepExpr dflags expr = do
    showPass dflags "CorePrep"
    us <- mkSplitUniqSupply 's'
    let new_expr = initUs_ us (cpeBodyNF emptyCorePrepEnv expr)
    dumpIfSet_dyn dflags Opt_D_dump_prep "CorePrep" (ppr new_expr)
    return new_expr

corePrepTopBinds :: [CoreBind] -> UniqSM Floats
-- Note [Floating out of top level bindings]
corePrepTopBinds binds 
  = go emptyCorePrepEnv binds
  where
    go _   []             = return emptyFloats
    go env (bind : binds) = do (env', bind') <- cpeBind TopLevel env bind
                               binds' <- go env' binds
                               return (bind' `appendFloats` binds')

mkDataConWorkers :: [TyCon] -> [CoreBind]
-- See Note [Data constructor workers]
mkDataConWorkers data_tycons
  = [ NonRec id (Var id)	-- The ice is thin here, but it works
    | tycon <- data_tycons, 	-- CorePrep will eta-expand it
      data_con <- tyConDataCons tycon,
      let id = dataConWorkId data_con ]
\end{code}

Note [Floating out of top level bindings]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
NB: we do need to float out of top-level bindings
Consider	x = length [True,False]
We want to get
		s1 = False : []
		s2 = True  : s1
		x  = length s2

We return a *list* of bindings, because we may start with
	x* = f (g y)
where x is demanded, in which case we want to finish with
	a = g y
	x* = f a
And then x will actually end up case-bound

Note [CafInfo and floating]
~~~~~~~~~~~~~~~~~~~~~~~~~~~
What happens to the CafInfo on the floated bindings?  By default, all
the CafInfos will be set to MayHaveCafRefs, which is safe.

This might be pessimistic, because the floated binding might not refer
to any CAFs and the GC will end up doing more traversal than is
necessary, but it's still better than not floating the bindings at
all, because then the GC would have to traverse the structure in the
heap instead.  Given this, we decided not to try to get the CafInfo on
the floated bindings correct, because it looks difficult.

But that means we can't float anything out of a NoCafRefs binding.
Consider       f = g (h x)
If f is NoCafRefs, we don't want to convert to
     	       sat = h x
               f = g sat
where sat conservatively says HasCafRefs, because now f's info
is wrong.  I don't think this is common, so we simply switch off
floating in this case.

Note [Data constructor workers]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Create any necessary "implicit" bindings for data con workers.  We
create the rather strange (non-recursive!) binding

	$wC = \x y -> $wC x y

i.e. a curried constructor that allocates.  This means that we can
treat the worker for a constructor like any other function in the rest
of the compiler.  The point here is that CoreToStg will generate a
StgConApp for the RHS, rather than a call to the worker (which would
give a loop).  As Lennart says: the ice is thin here, but it works.

Hmm.  Should we create bindings for dictionary constructors?  They are
always fully applied, and the bindings are just there to support
partial applications. But it's easier to let them through.


%************************************************************************
%*									*
		The main code
%*									*
%************************************************************************

\begin{code}
cpeBind :: TopLevelFlag
	-> CorePrepEnv -> CoreBind
	-> UniqSM (CorePrepEnv, Floats)
cpeBind top_lvl env (NonRec bndr rhs)
  = do { (_, bndr1) <- cloneBndr env bndr
       ; let is_strict   = isStrictDmd (idNewDemandInfo bndr)
             is_unlifted = isUnLiftedType (idType bndr)
       ; (floats, bndr2, rhs2) <- cpePair top_lvl NonRecursive 
       	 	  	       	  	  (is_strict || is_unlifted) 
					  env bndr1 rhs
       ; let new_float = mkFloat is_strict is_unlifted bndr2 rhs2

        -- We want bndr'' in the envt, because it records
        -- the evaluated-ness of the binder
       ; return (extendCorePrepEnv env bndr bndr2, 
       	         addFloat floats new_float) }

cpeBind top_lvl env (Rec pairs)
  = do { let (bndrs,rhss) = unzip pairs
       ; (env', bndrs1) <- cloneBndrs env (map fst pairs)
       ; stuff <- zipWithM (cpePair top_lvl Recursive False env') bndrs1 rhss

       ; let (floats_s, bndrs2, rhss2) = unzip3 stuff
             all_pairs = foldrOL add_float (bndrs1 `zip` rhss2)
	     	       	 	 	   (concatFloats floats_s)
       ; return (extendCorePrepEnvList env (bndrs `zip` bndrs2),
       	 	 unitFloat (FloatLet (Rec all_pairs))) }
  where
	-- Flatten all the floats, and the currrent
	-- group into a single giant Rec
    add_float (FloatLet (NonRec b r)) prs2 = (b,r) : prs2
    add_float (FloatLet (Rec prs1))   prs2 = prs1 ++ prs2
    add_float b                       _    = pprPanic "cpeBind" (ppr b)

---------------
cpePair :: TopLevelFlag -> RecFlag -> RhsDemand
	-> CorePrepEnv -> Id -> CoreExpr
	-> UniqSM (Floats, Id, CoreExpr)
-- Used for all bindings
cpePair top_lvl is_rec is_strict_or_unlifted env bndr rhs
  = do { (floats1, rhs1) <- cpeRhsE env rhs
       ; let (rhs1_bndrs, _) = collectBinders rhs1
       ; (floats2, rhs2)
       	    <- if want_float floats1 rhs1 
       	       then return (floats1, rhs1)
       	       else -- Non-empty floats will wrap rhs1
                    -- But: rhs1 might have lambdas, and we can't
		    --      put them inside a wrapBinds
	       if valBndrCount rhs1_bndrs <= arity 
	       then    -- Lambdas in rhs1 will be nuked by eta expansion
	       	    return (emptyFloats, wrapBinds floats1 rhs1)
	   
	       else do { body1 <- rhsToBodyNF rhs1
  	               ; return (emptyFloats, wrapBinds floats1 body1) } 

       ; (floats3, rhs')   -- Note [Silly extra arguments]
            <- if manifestArity rhs2 <= arity 
	       then return (floats2, cpeEtaExpand arity rhs2)
	       else WARN(True, text "CorePrep: silly extra arguments:" <+> ppr bndr)
	       	    (do { v <- newVar (idType bndr)
		        ; let float = mkFloat False False v rhs2
		        ; return (addFloat floats2 float, cpeEtaExpand arity (Var v)) })

	     	-- Record if the binder is evaluated
       ; let bndr' | exprIsHNF rhs' = bndr `setIdUnfolding` evaldUnfolding
       	     	   | otherwise      = bndr

       ; return (floats3, bndr', rhs') }
  where
    arity = idArity bndr	-- We must match this arity
    want_float floats rhs 
     | isTopLevel top_lvl = wantFloatTop bndr floats
     | otherwise          = wantFloatNested is_rec is_strict_or_unlifted floats rhs

{- Note [Silly extra arguments]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Suppose we had this
	f{arity=1} = \x\y. e
We *must* match the arity on the Id, so we have to generate
        f' = \x\y. e
 	f  = \x. f' x

It's a bizarre case: why is the arity on the Id wrong?  Reason
(in the days of __inline_me__): 
        f{arity=0} = __inline_me__ (let v = expensive in \xy. e)
When InlineMe notes go away this won't happen any more.  But
it seems good for CorePrep to be robust.
-}

-- ---------------------------------------------------------------------------
--		CpeRhs: produces a result satisfying CpeRhs
-- ---------------------------------------------------------------------------

cpeRhsE :: CorePrepEnv -> CoreExpr -> UniqSM (Floats, CpeRhs)
-- If
--	e  ===>  (bs, e')
-- then	
--	e = let bs in e'	(semantically, that is!)
--
-- For example
--	f (g x)	  ===>   ([v = g x], f v)

cpeRhsE _env expr@(Type _) = return (emptyFloats, expr)
cpeRhsE _env expr@(Lit _)  = return (emptyFloats, expr)
cpeRhsE env expr@(Var {})  = cpeApp env expr

cpeRhsE env (Var f `App` _ `App` arg)
  | f `hasKey` lazyIdKey  	  -- Replace (lazy a) by a
  = cpeRhsE env arg		  -- See Note [lazyId magic] in MkId

cpeRhsE env expr@(App {}) = cpeApp env expr

cpeRhsE env (Let bind expr)
  = do { (env', new_binds) <- cpeBind NotTopLevel env bind
       ; (floats, body) <- cpeRhsE env' expr
       ; return (new_binds `appendFloats` floats, body) }

cpeRhsE env (Note note expr)
  | ignoreNote note
  = cpeRhsE env expr
  | otherwise	      -- Just SCCs actually
  = do { body <- cpeBodyNF env expr
       ; return (emptyFloats, Note note body) }

cpeRhsE env (Cast expr co)
   = do { (floats, expr') <- cpeRhsE env expr
        ; return (floats, Cast expr' co) }

cpeRhsE env expr@(Lam {})
   = do { let (bndrs,body) = collectBinders expr
        ; (env', bndrs') <- cloneBndrs env bndrs
	; body' <- cpeBodyNF env' body
	; return (emptyFloats, mkLams bndrs' body') }

cpeRhsE env (Case (Var id) bndr ty [(DEFAULT,[],expr)])
  | Just (TickBox {}) <- isTickBoxOp_maybe id
  = do { body <- cpeBodyNF env expr
       ; return (emptyFloats, Case (Var id) bndr ty [(DEFAULT,[],body)]) }

cpeRhsE env (Case scrut bndr ty alts)
  = do { (floats, scrut') <- cpeBody env scrut
       ; let bndr1 = bndr `setIdUnfolding` evaldUnfolding
            -- Record that the case binder is evaluated in the alternatives
       ; (env', bndr2) <- cloneBndr env bndr1
       ; alts' <- mapM (sat_alt env') alts
       ; return (floats, Case scrut' bndr2 ty alts') }
  where
    sat_alt env (con, bs, rhs)
       = do { (env2, bs') <- cloneBndrs env bs
            ; rhs' <- cpeBodyNF env2 rhs
            ; return (con, bs', rhs') }

-- ---------------------------------------------------------------------------
--		CpeBody: produces a result satisfying CpeBody
-- ---------------------------------------------------------------------------

cpeBodyNF :: CorePrepEnv -> CoreExpr -> UniqSM CpeBody
cpeBodyNF env expr 
  = do { (floats, body) <- cpeBody env expr
       ; return (wrapBinds floats body) }

--------
cpeBody :: CorePrepEnv -> CoreExpr -> UniqSM (Floats, CpeBody)
cpeBody env expr
  = do { (floats1, rhs) <- cpeRhsE env expr
       ; (floats2, body) <- rhsToBody rhs
       ; return (floats1 `appendFloats` floats2, body) }

--------
rhsToBodyNF :: CpeRhs -> UniqSM CpeBody
rhsToBodyNF rhs = do { (floats,body) <- rhsToBody rhs
	    	     ; return (wrapBinds floats body) }

--------
rhsToBody :: CpeRhs -> UniqSM (Floats, CpeBody)
-- Remove top level lambdas by let-binding

rhsToBody (Note n expr)
        -- You can get things like
        --      case e of { p -> coerce t (\s -> ...) }
  = do { (floats, expr') <- rhsToBody expr
       ; return (floats, Note n expr') }

rhsToBody (Cast e co)
  = do { (floats, e') <- rhsToBody e
       ; return (floats, Cast e' co) }

rhsToBody expr@(Lam {})
  | Just no_lam_result <- tryEtaReduce bndrs body
  = return (emptyFloats, no_lam_result)
  | all isTyVar bndrs		-- Type lambdas are ok
  = return (emptyFloats, expr)
  | otherwise			-- Some value lambdas
  = do { fn <- newVar (exprType expr)
       ; let rhs   = cpeEtaExpand (exprArity expr) expr
       	     float = FloatLet (NonRec fn rhs)
       ; return (unitFloat float, Var fn) }
  where
    (bndrs,body) = collectBinders expr

rhsToBody expr = return (emptyFloats, expr)



-- ---------------------------------------------------------------------------
--		CpeApp: produces a result satisfying CpeApp
-- ---------------------------------------------------------------------------

cpeApp :: CorePrepEnv -> CoreExpr -> UniqSM (Floats, CpeRhs)
-- May return a CpeRhs because of saturating primops
cpeApp env expr 
  = do { (app, (head,depth), _, floats, ss) <- collect_args expr 0
       ; MASSERT(null ss)	-- make sure we used all the strictness info

	-- Now deal with the function
       ; case head of
           Var fn_id -> do { sat_app <- maybeSaturate fn_id app depth
	       	     	   ; return (floats, sat_app) }
           _other    -> return (floats, app) }

  where
    -- Deconstruct and rebuild the application, floating any non-atomic
    -- arguments to the outside.  We collect the type of the expression,
    -- the head of the application, and the number of actual value arguments,
    -- all of which are used to possibly saturate this application if it
    -- has a constructor or primop at the head.

    collect_args
	:: CoreExpr
	-> Int			   -- Current app depth
	-> UniqSM (CpeApp,	   -- The rebuilt expression
		   (CoreExpr,Int), -- The head of the application,
				   -- and no. of args it was applied to
		   Type,	   -- Type of the whole expr
		   Floats, 	   -- Any floats we pulled out
		   [Demand])	   -- Remaining argument demands

    collect_args (App fun arg@(Type arg_ty)) depth
      = do { (fun',hd,fun_ty,floats,ss) <- collect_args fun depth
           ; return (App fun' arg, hd, applyTy fun_ty arg_ty, floats, ss) }

    collect_args (App fun arg) depth
      = do { (fun',hd,fun_ty,floats,ss) <- collect_args fun (depth+1)
      	   ; let
              (ss1, ss_rest)   = case ss of
                                   (ss1:ss_rest) -> (ss1,     ss_rest)
                                   []            -> (lazyDmd, [])
              (arg_ty, res_ty) = expectJust "cpeBody:collect_args" $
                                 splitFunTy_maybe fun_ty

           ; (fs, arg') <- cpeArg env (isStrictDmd ss1) arg arg_ty
           ; return (App fun' arg', hd, res_ty, fs `appendFloats` floats, ss_rest) }

    collect_args (Var v) depth 
      = do { v1 <- fiddleCCall v
           ; let v2 = lookupCorePrepEnv env v1
           ; return (Var v2, (Var v2, depth), idType v2, emptyFloats, stricts) }
	where
	  stricts = case idNewStrictness v of
			StrictSig (DmdType _ demands _)
			    | listLengthCmp demands depth /= GT -> demands
			            -- length demands <= depth
			    | otherwise                         -> []
		-- If depth < length demands, then we have too few args to 
		-- satisfy strictness  info so we have to  ignore all the 
		-- strictness info, e.g. + (error "urk")
		-- Here, we can't evaluate the arg strictly, because this 
		-- partial application might be seq'd

    collect_args (Cast fun co) depth
      = do { let (_ty1,ty2) = coercionKind co
           ; (fun', hd, _, floats, ss) <- collect_args fun depth
           ; return (Cast fun' co, hd, ty2, floats, ss) }
          
    collect_args (Note note fun) depth
      | ignoreNote note         -- Drop these notes altogether
      = collect_args fun depth  -- They aren't used by the code generator

	-- N-variable fun, better let-bind it
    collect_args fun depth
      = do { (fun_floats, fun') <- cpeArg env True fun ty
      	     		  -- The True says that it's sure to be evaluated,
			  -- so we'll end up case-binding it
           ; return (fun', (fun', depth), ty, fun_floats, []) }
        where
	  ty = exprType fun

-- ---------------------------------------------------------------------------
--	CpeArg: produces a result satisfying CpeArg
-- ---------------------------------------------------------------------------

-- This is where we arrange that a non-trivial argument is let-bound
cpeArg :: CorePrepEnv -> RhsDemand -> CoreArg -> Type
       -> UniqSM (Floats, CpeTriv)
cpeArg env is_strict arg arg_ty
  | cpe_ExprIsTrivial arg   -- Do not eta expand etc a trivial argument
  = cpeBody env arg	    -- Must still do substitution though
  | otherwise
  = do { (floats1, arg1) <- cpeRhsE env arg	-- arg1 can be a lambda
       ; (floats2, arg2) <- if want_float floats1 arg1 
       	 	   	    then return (floats1, arg1)
       	 	   	    else do { body1 <- rhsToBodyNF arg1
  			            ; return (emptyFloats, wrapBinds floats1 body1) } 
	 	-- Else case: arg1 might have lambdas, and we can't
		--            put them inside a wrapBinds

       ; v <- newVar arg_ty
       ; let arg3      = cpeEtaExpand (exprArity arg2) arg2
       	     arg_float = mkFloat is_strict is_unlifted v arg3
       ; return (addFloat floats2 arg_float, Var v) }
  where
    is_unlifted = isUnLiftedType arg_ty
    want_float = wantFloatNested NonRecursive (is_strict || is_unlifted)
\end{code}

Note [Floating unlifted arguments]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider    C (let v* = expensive in v)

where the "*" indicates "will be demanded".  Usually v will have been
inlined by now, but let's suppose it hasn't (see Trac #2756).  Then we
do *not* want to get

     let v* = expensive in C v

because that has different strictness.  Hence the use of 'allLazy'.
(NB: the let v* turns into a FloatCase, in mkLocalNonRec.)


------------------------------------------------------------------------------
-- Building the saturated syntax
-- ---------------------------------------------------------------------------

maybeSaturate deals with saturating primops and constructors
The type is the type of the entire application

\begin{code}
maybeSaturate :: Id -> CpeApp -> Int -> UniqSM CpeRhs
maybeSaturate fn expr n_args
  | Just DataToTagOp <- isPrimOpId_maybe fn     -- DataToTag must have an evaluated arg
                                                -- A gruesome special case
  = saturateDataToTag sat_expr

  | hasNoBinding fn 	   -- There's no binding
  = return sat_expr

  | otherwise 
  = return expr
  where
    fn_arity	 = idArity fn
    excess_arity = fn_arity - n_args
    sat_expr     = cpeEtaExpand excess_arity expr

-------------
saturateDataToTag :: CpeApp -> UniqSM CpeApp
-- Horrid: ensure that the arg of data2TagOp is evaluated
--   (data2tag x) -->  (case x of y -> data2tag y)
-- (yuk yuk) take into account the lambdas we've now introduced
saturateDataToTag sat_expr
  = do { let (eta_bndrs, eta_body) = collectBinders sat_expr
       ; eta_body' <- eval_data2tag_arg eta_body
       ; return (mkLams eta_bndrs eta_body') }
  where
    eval_data2tag_arg :: CpeApp -> UniqSM CpeBody
    eval_data2tag_arg app@(fun `App` arg)
        | exprIsHNF arg         -- Includes nullary constructors
        = return app		-- The arg is evaluated
        | otherwise                     -- Arg not evaluated, so evaluate it
        = do { arg_id <- newVar (exprType arg)
             ; let arg_id1 = setIdUnfolding arg_id evaldUnfolding
             ; return (Case arg arg_id1 (exprType app)
                            [(DEFAULT, [], fun `App` Var arg_id1)]) }

    eval_data2tag_arg (Note note app)	-- Scc notes can appear
        = do { app' <- eval_data2tag_arg app
             ; return (Note note app') }

    eval_data2tag_arg other	-- Should not happen
	= pprPanic "eval_data2tag" (ppr other)
\end{code}




%************************************************************************
%*									*
		Simple CoreSyn operations
%*									*
%************************************************************************

\begin{code}
	-- We don't ignore SCCs, since they require some code generation
ignoreNote :: Note -> Bool
-- Tells which notes to drop altogether; they are ignored by code generation
-- Do not ignore SCCs!
-- It's important that we do drop InlineMe notes; for example
--    unzip = __inline_me__ (/\ab. foldr (..) (..))
-- Here unzip gets arity 1 so we'll eta-expand it. But we don't
-- want to get this:
--     unzip = /\ab \xs. (__inline_me__ ...) a b xs
ignoreNote (CoreNote _) = True 
ignoreNote InlineMe     = True
ignoreNote _other       = False


cpe_ExprIsTrivial :: CoreExpr -> Bool
-- Version that doesn't consider an scc annotation to be trivial.
cpe_ExprIsTrivial (Var _)                  = True
cpe_ExprIsTrivial (Type _)                 = True
cpe_ExprIsTrivial (Lit _)                  = True
cpe_ExprIsTrivial (App e arg)              = isTypeArg arg && cpe_ExprIsTrivial e
cpe_ExprIsTrivial (Note (SCC _) _)         = False
cpe_ExprIsTrivial (Note _ e)               = cpe_ExprIsTrivial e
cpe_ExprIsTrivial (Cast e _)               = cpe_ExprIsTrivial e
cpe_ExprIsTrivial (Lam b body) | isTyVar b = cpe_ExprIsTrivial body
cpe_ExprIsTrivial _                        = False
\end{code}

-- -----------------------------------------------------------------------------
--	Eta reduction
-- -----------------------------------------------------------------------------

Note [Eta expansion]
~~~~~~~~~~~~~~~~~~~~~
Eta expand to match the arity claimed by the binder Remember,
CorePrep must not change arity

Eta expansion might not have happened already, because it is done by
the simplifier only when there at least one lambda already.

NB1:we could refrain when the RHS is trivial (which can happen
    for exported things).  This would reduce the amount of code
    generated (a little) and make things a little words for
    code compiled without -O.  The case in point is data constructor
    wrappers.

NB2: we have to be careful that the result of etaExpand doesn't
   invalidate any of the assumptions that CorePrep is attempting
   to establish.  One possible cause is eta expanding inside of
   an SCC note - we're now careful in etaExpand to make sure the
   SCC is pushed inside any new lambdas that are generated.

Note [Eta expansion and the CorePrep invariants]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
It turns out to be much much easier to do eta expansion
*after* the main CorePrep stuff.  But that places constraints
on the eta expander: given a CpeRhs, it must return a CpeRhs.

For example here is what we do not want:
		f = /\a -> g (h 3)	-- h has arity 2
After ANFing we get
		f = /\a -> let s = h 3 in g s
and now we do NOT want eta expansion to give
		f = /\a -> \ y -> (let s = h 3 in g s) y

Instead CoreArity.etaExpand gives
		f = /\a -> \y -> let s = h 3 in g s y

\begin{code}
cpeEtaExpand :: Arity -> CoreExpr -> CoreExpr
cpeEtaExpand arity expr
  | arity == 0 = expr
  | otherwise  = etaExpand arity expr
\end{code}

-- -----------------------------------------------------------------------------
--	Eta reduction
-- -----------------------------------------------------------------------------

Why try eta reduction?  Hasn't the simplifier already done eta?
But the simplifier only eta reduces if that leaves something
trivial (like f, or f Int).  But for deLam it would be enough to
get to a partial application:
	case x of { p -> \xs. map f xs }
    ==> case x of { p -> map f }

\begin{code}
tryEtaReduce :: [CoreBndr] -> CoreExpr -> Maybe CoreExpr
tryEtaReduce bndrs expr@(App _ _)
  | ok_to_eta_reduce f &&
    n_remaining >= 0 &&
    and (zipWith ok bndrs last_args) &&
    not (any (`elemVarSet` fvs_remaining) bndrs)
  = Just remaining_expr
  where
    (f, args) = collectArgs expr
    remaining_expr = mkApps f remaining_args
    fvs_remaining = exprFreeVars remaining_expr
    (remaining_args, last_args) = splitAt n_remaining args
    n_remaining = length args - length bndrs

    ok bndr (Var arg) = bndr == arg
    ok _    _         = False

	  -- we can't eta reduce something which must be saturated.
    ok_to_eta_reduce (Var f) = not (hasNoBinding f)
    ok_to_eta_reduce _       = False --safe. ToDo: generalise

tryEtaReduce bndrs (Let bind@(NonRec _ r) body)
  | not (any (`elemVarSet` fvs) bndrs)
  = case tryEtaReduce bndrs body of
	Just e -> Just (Let bind e)
	Nothing -> Nothing
  where
    fvs = exprFreeVars r

tryEtaReduce _ _ = Nothing
\end{code}


-- -----------------------------------------------------------------------------
-- Demands
-- -----------------------------------------------------------------------------

\begin{code}
type RhsDemand = Bool  -- True => used strictly; hence not top-level, non-recursive
\end{code}

%************************************************************************
%*									*
		Floats
%*									*
%************************************************************************

\begin{code}
data FloatingBind 
  = FloatLet CoreBind	        -- Rhs of bindings are CpeRhss
  | FloatCase Id CpeBody Bool   -- The bool indicates "ok-for-speculation"

data Floats = Floats OkToSpec (OrdList FloatingBind)

-- Can we float these binds out of the rhs of a let?  We cache this decision
-- to avoid having to recompute it in a non-linear way when there are
-- deeply nested lets.
data OkToSpec
   = NotOkToSpec 	-- definitely not
   | OkToSpec		-- yes
   | IfUnboxedOk	-- only if floating an unboxed binding is ok

mkFloat :: Bool -> Bool -> Id -> CpeRhs -> FloatingBind
mkFloat is_strict is_unlifted bndr rhs
  | use_case  = FloatCase bndr rhs (exprOkForSpeculation rhs)
  | otherwise = FloatLet (NonRec bndr rhs)
  where
    use_case = is_unlifted || is_strict && not (exprIsHNF rhs)
     	      	-- Don't make a case for a value binding,
		-- even if it's strict.  Otherwise we get
		-- 	case (\x -> e) of ...!
             
emptyFloats :: Floats
emptyFloats = Floats OkToSpec nilOL

isEmptyFloats :: Floats -> Bool
isEmptyFloats (Floats _ bs) = isNilOL bs

wrapBinds :: Floats -> CoreExpr -> CoreExpr
wrapBinds (Floats _ binds) body
  = foldrOL mk_bind body binds
  where
    mk_bind (FloatCase bndr rhs _) body = Case rhs bndr (exprType body) [(DEFAULT, [], body)]
    mk_bind (FloatLet bind)        body = Let bind body

addFloat :: Floats -> FloatingBind -> Floats
addFloat (Floats ok_to_spec floats) new_float
  = Floats (combine ok_to_spec (check new_float)) (floats `snocOL` new_float)
  where
    check (FloatLet _) = OkToSpec
    check (FloatCase _ _ ok_for_spec) 
	| ok_for_spec  =  IfUnboxedOk
	| otherwise    =  NotOkToSpec
	-- The ok-for-speculation flag says that it's safe to
	-- float this Case out of a let, and thereby do it more eagerly
	-- We need the top-level flag because it's never ok to float
	-- an unboxed binding to the top level

unitFloat :: FloatingBind -> Floats
unitFloat = addFloat emptyFloats

appendFloats :: Floats -> Floats -> Floats
appendFloats (Floats spec1 floats1) (Floats spec2 floats2)
  = Floats (combine spec1 spec2) (floats1 `appOL` floats2)

concatFloats :: [Floats] -> OrdList FloatingBind
concatFloats = foldr (\ (Floats _ bs1) bs2 -> appOL bs1 bs2) nilOL

combine :: OkToSpec -> OkToSpec -> OkToSpec
combine NotOkToSpec _ = NotOkToSpec
combine _ NotOkToSpec = NotOkToSpec
combine IfUnboxedOk _ = IfUnboxedOk
combine _ IfUnboxedOk = IfUnboxedOk
combine _ _           = OkToSpec
    
instance Outputable FloatingBind where
  ppr (FloatLet bind)        = text "FloatLet" <+> ppr bind
  ppr (FloatCase b rhs spec) = text "FloatCase" <+> ppr b <+> ppr spec <+> equals <+> ppr rhs

deFloatTop :: Floats -> [CoreBind]
-- For top level only; we don't expect any FloatCases
deFloatTop (Floats _ floats)
  = foldrOL get [] floats
  where
    get (FloatLet b) bs = b:bs
    get b            _  = pprPanic "corePrepPgm" (ppr b)

-------------------------------------------
wantFloatTop :: Id -> Floats -> Bool
       -- Note [CafInfo and floating]
wantFloatTop bndr floats = isEmptyFloats floats
	     	  	 || (mayHaveCafRefs (idCafInfo bndr)
      			     && allLazyTop floats)

wantFloatNested :: RecFlag -> Bool -> Floats -> CpeRhs -> Bool
wantFloatNested is_rec strict_or_unlifted floats rhs
  =  isEmptyFloats floats
  || strict_or_unlifted
  || (allLazyNested is_rec floats && exprIsHNF rhs)
   	-- Why the test for allLazyNested? 
	--	v = f (x `divInt#` y)
	-- we don't want to float the case, even if f has arity 2,
	-- because floating the case would make it evaluated too early

allLazyTop :: Floats -> Bool
allLazyTop (Floats OkToSpec _) = True
allLazyTop _ 	   	       = False

allLazyNested :: RecFlag -> Floats -> Bool
allLazyNested _      (Floats OkToSpec    _) = True
allLazyNested _      (Floats NotOkToSpec _) = False
allLazyNested is_rec (Floats IfUnboxedOk _) = isNonRec is_rec
\end{code}


%************************************************************************
%*									*
		Cloning
%*									*
%************************************************************************

\begin{code}
-- ---------------------------------------------------------------------------
-- 			The environment
-- ---------------------------------------------------------------------------

data CorePrepEnv = CPE (IdEnv Id)	-- Clone local Ids

emptyCorePrepEnv :: CorePrepEnv
emptyCorePrepEnv = CPE emptyVarEnv

extendCorePrepEnv :: CorePrepEnv -> Id -> Id -> CorePrepEnv
extendCorePrepEnv (CPE env) id id' = CPE (extendVarEnv env id id')

extendCorePrepEnvList :: CorePrepEnv -> [(Id,Id)] -> CorePrepEnv
extendCorePrepEnvList (CPE env) prs = CPE (extendVarEnvList env prs)

lookupCorePrepEnv :: CorePrepEnv -> Id -> Id
lookupCorePrepEnv (CPE env) id
  = case lookupVarEnv env id of
	Nothing	 -> id
	Just id' -> id'

------------------------------------------------------------------------------
-- Cloning binders
-- ---------------------------------------------------------------------------

cloneBndrs :: CorePrepEnv -> [Var] -> UniqSM (CorePrepEnv, [Var])
cloneBndrs env bs = mapAccumLM cloneBndr env bs

cloneBndr  :: CorePrepEnv -> Var -> UniqSM (CorePrepEnv, Var)
cloneBndr env bndr
  | isLocalId bndr
  = do bndr' <- setVarUnique bndr <$> getUniqueM
       return (extendCorePrepEnv env bndr bndr', bndr')

  | otherwise	-- Top level things, which we don't want
		-- to clone, have become GlobalIds by now
		-- And we don't clone tyvars
  = return (env, bndr)
  

------------------------------------------------------------------------------
-- Cloning ccall Ids; each must have a unique name,
-- to give the code generator a handle to hang it on
-- ---------------------------------------------------------------------------

fiddleCCall :: Id -> UniqSM Id
fiddleCCall id 
  | isFCallId id = (id `setVarUnique`) <$> getUniqueM
  | otherwise    = return id

------------------------------------------------------------------------------
-- Generating new binders
-- ---------------------------------------------------------------------------

newVar :: Type -> UniqSM Id
newVar ty
 = seqType ty `seq` do
     uniq <- getUniqueM
     return (mkSysLocal (fsLit "sat") uniq ty)
\end{code}
