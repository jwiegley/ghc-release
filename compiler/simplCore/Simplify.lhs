%
% (c) The AQUA Project, Glasgow University, 1993-1998
%
\section[Simplify]{The main module of the simplifier}

\begin{code}
module Simplify ( simplTopBinds, simplExpr ) where

#include "HsVersions.h"

import DynFlags
import SimplMonad
import Type hiding      ( substTy, extendTvSubst )
import SimplEnv
import SimplUtils
import FamInstEnv	( FamInstEnv )
import Id
import MkId		( mkImpossibleExpr, seqId )
import Var
import IdInfo
import Coercion
import FamInstEnv       ( topNormaliseType )
import DataCon          ( dataConRepStrictness, dataConUnivTyVars )
import CoreSyn
import NewDemand        ( isStrictDmd, splitStrictSig )
import PprCore          ( pprParendExpr, pprCoreExpr )
import CoreUnfold       ( mkUnfolding, callSiteInline, CallCtxt(..) )
import CoreUtils
import CoreArity	( exprArity )
import Rules            ( lookupRule, getRules )
import BasicTypes       ( isMarkedStrict, Arity )
import CostCentre       ( currentCCS, pushCCisNop )
import TysPrim          ( realWorldStatePrimTy )
import PrelInfo         ( realWorldPrimId )
import BasicTypes       ( TopLevelFlag(..), isTopLevel,
                          RecFlag(..), isNonRuleLoopBreaker )
import Maybes           ( orElse )
import Data.List        ( mapAccumL )
import Outputable
import FastString
\end{code}


The guts of the simplifier is in this module, but the driver loop for
the simplifier is in SimplCore.lhs.


-----------------------------------------
        *** IMPORTANT NOTE ***
-----------------------------------------
The simplifier used to guarantee that the output had no shadowing, but
it does not do so any more.   (Actually, it never did!)  The reason is
documented with simplifyArgs.


-----------------------------------------
        *** IMPORTANT NOTE ***
-----------------------------------------
Many parts of the simplifier return a bunch of "floats" as well as an
expression. This is wrapped as a datatype SimplUtils.FloatsWith.

All "floats" are let-binds, not case-binds, but some non-rec lets may
be unlifted (with RHS ok-for-speculation).



-----------------------------------------
        ORGANISATION OF FUNCTIONS
-----------------------------------------
simplTopBinds
  - simplify all top-level binders
  - for NonRec, call simplRecOrTopPair
  - for Rec,    call simplRecBind


        ------------------------------
simplExpr (applied lambda)      ==> simplNonRecBind
simplExpr (Let (NonRec ...) ..) ==> simplNonRecBind
simplExpr (Let (Rec ...)    ..) ==> simplify binders; simplRecBind

        ------------------------------
simplRecBind    [binders already simplfied]
  - use simplRecOrTopPair on each pair in turn

simplRecOrTopPair [binder already simplified]
  Used for: recursive bindings (top level and nested)
            top-level non-recursive bindings
  Returns:
  - check for PreInlineUnconditionally
  - simplLazyBind

simplNonRecBind
  Used for: non-top-level non-recursive bindings
            beta reductions (which amount to the same thing)
  Because it can deal with strict arts, it takes a
        "thing-inside" and returns an expression

  - check for PreInlineUnconditionally
  - simplify binder, including its IdInfo
  - if strict binding
        simplStrictArg
        mkAtomicArgs
        completeNonRecX
    else
        simplLazyBind
        addFloats

simplNonRecX:   [given a *simplified* RHS, but an *unsimplified* binder]
  Used for: binding case-binder and constr args in a known-constructor case
  - check for PreInLineUnconditionally
  - simplify binder
  - completeNonRecX

        ------------------------------
simplLazyBind:  [binder already simplified, RHS not]
  Used for: recursive bindings (top level and nested)
            top-level non-recursive bindings
            non-top-level, but *lazy* non-recursive bindings
        [must not be strict or unboxed]
  Returns floats + an augmented environment, not an expression
  - substituteIdInfo and add result to in-scope
        [so that rules are available in rec rhs]
  - simplify rhs
  - mkAtomicArgs
  - float if exposes constructor or PAP
  - completeBind


completeNonRecX:        [binder and rhs both simplified]
  - if the the thing needs case binding (unlifted and not ok-for-spec)
        build a Case
   else
        completeBind
        addFloats

completeBind:   [given a simplified RHS]
        [used for both rec and non-rec bindings, top level and not]
  - try PostInlineUnconditionally
  - add unfolding [this is the only place we add an unfolding]
  - add arity



Right hand sides and arguments
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
In many ways we want to treat
        (a) the right hand side of a let(rec), and
        (b) a function argument
in the same way.  But not always!  In particular, we would
like to leave these arguments exactly as they are, so they
will match a RULE more easily.

        f (g x, h x)
        g (+ x)

It's harder to make the rule match if we ANF-ise the constructor,
or eta-expand the PAP:

        f (let { a = g x; b = h x } in (a,b))
        g (\y. + x y)

On the other hand if we see the let-defns

        p = (g x, h x)
        q = + x

then we *do* want to ANF-ise and eta-expand, so that p and q
can be safely inlined.

Even floating lets out is a bit dubious.  For let RHS's we float lets
out if that exposes a value, so that the value can be inlined more vigorously.
For example

        r = let x = e in (x,x)

Here, if we float the let out we'll expose a nice constructor. We did experiments
that showed this to be a generally good thing.  But it was a bad thing to float
lets out unconditionally, because that meant they got allocated more often.

For function arguments, there's less reason to expose a constructor (it won't
get inlined).  Just possibly it might make a rule match, but I'm pretty skeptical.
So for the moment we don't float lets out of function arguments either.


Eta expansion
~~~~~~~~~~~~~~
For eta expansion, we want to catch things like

        case e of (a,b) -> \x -> case a of (p,q) -> \y -> r

If the \x was on the RHS of a let, we'd eta expand to bring the two
lambdas together.  And in general that's a good thing to do.  Perhaps
we should eta expand wherever we find a (value) lambda?  Then the eta
expansion at a let RHS can concentrate solely on the PAP case.


%************************************************************************
%*                                                                      *
\subsection{Bindings}
%*                                                                      *
%************************************************************************

\begin{code}
simplTopBinds :: SimplEnv -> [InBind] -> SimplM [OutBind]

simplTopBinds env0 binds0
  = do  {       -- Put all the top-level binders into scope at the start
                -- so that if a transformation rule has unexpectedly brought
                -- anything into scope, then we don't get a complaint about that.
                -- It's rather as if the top-level binders were imported.
        ; env1 <- simplRecBndrs env0 (bindersOfBinds binds0)
        ; dflags <- getDOptsSmpl
        ; let dump_flag = dopt Opt_D_dump_inlinings dflags ||
                          dopt Opt_D_dump_rule_firings dflags
        ; env2 <- simpl_binds dump_flag env1 binds0
        ; freeTick SimplifierDone
        ; return (getFloats env2) }
  where
        -- We need to track the zapped top-level binders, because
        -- they should have their fragile IdInfo zapped (notably occurrence info)
        -- That's why we run down binds and bndrs' simultaneously.
        --
        -- The dump-flag emits a trace for each top-level binding, which
        -- helps to locate the tracing for inlining and rule firing
    simpl_binds :: Bool -> SimplEnv -> [InBind] -> SimplM SimplEnv
    simpl_binds _    env []           = return env
    simpl_binds dump env (bind:binds) = do { env' <- trace_bind dump bind $
                                                     simpl_bind env bind
                                           ; simpl_binds dump env' binds }

    trace_bind True  bind = pprTrace "SimplBind" (ppr (bindersOf bind))
    trace_bind False _    = \x -> x

    simpl_bind env (Rec pairs)  = simplRecBind      env  TopLevel pairs
    simpl_bind env (NonRec b r) = simplRecOrTopPair env' TopLevel b b' r
        where
          (env', b') = addBndrRules env b (lookupRecBndr env b)
\end{code}


%************************************************************************
%*                                                                      *
\subsection{Lazy bindings}
%*                                                                      *
%************************************************************************

simplRecBind is used for
        * recursive bindings only

\begin{code}
simplRecBind :: SimplEnv -> TopLevelFlag
             -> [(InId, InExpr)]
             -> SimplM SimplEnv
simplRecBind env0 top_lvl pairs0
  = do  { let (env_with_info, triples) = mapAccumL add_rules env0 pairs0
        ; env1 <- go (zapFloats env_with_info) triples
        ; return (env0 `addRecFloats` env1) }
        -- addFloats adds the floats from env1,
        -- _and_ updates env0 with the in-scope set from env1
  where
    add_rules :: SimplEnv -> (InBndr,InExpr) -> (SimplEnv, (InBndr, OutBndr, InExpr))
        -- Add the (substituted) rules to the binder
    add_rules env (bndr, rhs) = (env', (bndr, bndr', rhs))
        where
          (env', bndr') = addBndrRules env bndr (lookupRecBndr env bndr)

    go env [] = return env

    go env ((old_bndr, new_bndr, rhs) : pairs)
        = do { env' <- simplRecOrTopPair env top_lvl old_bndr new_bndr rhs
             ; go env' pairs }
\end{code}

simplOrTopPair is used for
        * recursive bindings (whether top level or not)
        * top-level non-recursive bindings

It assumes the binder has already been simplified, but not its IdInfo.

\begin{code}
simplRecOrTopPair :: SimplEnv
                  -> TopLevelFlag
                  -> InId -> OutBndr -> InExpr  -- Binder and rhs
                  -> SimplM SimplEnv    -- Returns an env that includes the binding

simplRecOrTopPair env top_lvl old_bndr new_bndr rhs
  | preInlineUnconditionally env top_lvl old_bndr rhs   -- Check for unconditional inline
  = do  { tick (PreInlineUnconditionally old_bndr)
        ; return (extendIdSubst env old_bndr (mkContEx env rhs)) }

  | otherwise
  = simplLazyBind env top_lvl Recursive old_bndr new_bndr rhs env
        -- May not actually be recursive, but it doesn't matter
\end{code}


simplLazyBind is used for
  * [simplRecOrTopPair] recursive bindings (whether top level or not)
  * [simplRecOrTopPair] top-level non-recursive bindings
  * [simplNonRecE]      non-top-level *lazy* non-recursive bindings

Nota bene:
    1. It assumes that the binder is *already* simplified,
       and is in scope, and its IdInfo too, except unfolding

    2. It assumes that the binder type is lifted.

    3. It does not check for pre-inline-unconditionallly;
       that should have been done already.

\begin{code}
simplLazyBind :: SimplEnv
              -> TopLevelFlag -> RecFlag
              -> InId -> OutId          -- Binder, both pre-and post simpl
                                        -- The OutId has IdInfo, except arity, unfolding
              -> InExpr -> SimplEnv     -- The RHS and its environment
              -> SimplM SimplEnv

simplLazyBind env top_lvl is_rec bndr bndr1 rhs rhs_se
  = do  { let   rhs_env     = rhs_se `setInScope` env
		(tvs, body) = case collectTyBinders rhs of
			        (tvs, body) | not_lam body -> (tvs,body)
					    | otherwise	   -> ([], rhs)
		not_lam (Lam _ _) = False
		not_lam _	  = True
			-- Do not do the "abstract tyyvar" thing if there's
			-- a lambda inside, becuase it defeats eta-reduction
			--    f = /\a. \x. g a x  
			-- should eta-reduce

        ; (body_env, tvs') <- simplBinders rhs_env tvs
                -- See Note [Floating and type abstraction] in SimplUtils

        -- Simplify the RHS
        ; (body_env1, body1) <- simplExprF body_env body mkBoringStop

        -- ANF-ise a constructor or PAP rhs
        ; (body_env2, body2) <- prepareRhs body_env1 body1

        ; (env', rhs')
            <-  if not (doFloatFromRhs top_lvl is_rec False body2 body_env2)
                then                            -- No floating, just wrap up!
                     do { rhs' <- mkLam env tvs' (wrapFloats body_env2 body2)
                        ; return (env, rhs') }

                else if null tvs then           -- Simple floating
                     do { tick LetFloatFromLet
                        ; return (addFloats env body_env2, body2) }

                else                            -- Do type-abstraction first
                     do { tick LetFloatFromLet
                        ; (poly_binds, body3) <- abstractFloats tvs' body_env2 body2
                        ; rhs' <- mkLam env tvs' body3
                        ; let env' = foldl (addPolyBind top_lvl) env poly_binds
                        ; return (env', rhs') }

        ; completeBind env' top_lvl bndr bndr1 rhs' }
\end{code}

A specialised variant of simplNonRec used when the RHS is already simplified,
notably in knownCon.  It uses case-binding where necessary.

\begin{code}
simplNonRecX :: SimplEnv
             -> InId            -- Old binder
             -> OutExpr         -- Simplified RHS
             -> SimplM SimplEnv

simplNonRecX env bndr new_rhs
  | isDeadBinder bndr	-- Not uncommon; e.g. case (a,b) of b { (p,q) -> p }
  = return env		-- 		 Here b is dead, and we avoid creating
  | otherwise		--		 the binding b = (a,b)
  = do  { (env', bndr') <- simplBinder env bndr
        ; completeNonRecX env' (isStrictId bndr) bndr bndr' new_rhs }

completeNonRecX :: SimplEnv
                -> Bool
                -> InId                 -- Old binder
                -> OutId                -- New binder
                -> OutExpr              -- Simplified RHS
                -> SimplM SimplEnv

completeNonRecX env is_strict old_bndr new_bndr new_rhs
  = do  { (env1, rhs1) <- prepareRhs (zapFloats env) new_rhs
        ; (env2, rhs2) <-
                if doFloatFromRhs NotTopLevel NonRecursive is_strict rhs1 env1
                then do { tick LetFloatFromLet
                        ; return (addFloats env env1, rhs1) }   -- Add the floats to the main env
                else return (env, wrapFloats env1 rhs1)         -- Wrap the floats around the RHS
        ; completeBind env2 NotTopLevel old_bndr new_bndr rhs2 }
\end{code}

{- No, no, no!  Do not try preInlineUnconditionally in completeNonRecX
   Doing so risks exponential behaviour, because new_rhs has been simplified once already
   In the cases described by the folowing commment, postInlineUnconditionally will
   catch many of the relevant cases.
        -- This happens; for example, the case_bndr during case of
        -- known constructor:  case (a,b) of x { (p,q) -> ... }
        -- Here x isn't mentioned in the RHS, so we don't want to
        -- create the (dead) let-binding  let x = (a,b) in ...
        --
        -- Similarly, single occurrences can be inlined vigourously
        -- e.g.  case (f x, g y) of (a,b) -> ....
        -- If a,b occur once we can avoid constructing the let binding for them.

   Furthermore in the case-binding case preInlineUnconditionally risks extra thunks
        -- Consider     case I# (quotInt# x y) of
        --                I# v -> let w = J# v in ...
        -- If we gaily inline (quotInt# x y) for v, we end up building an
        -- extra thunk:
        --                let w = J# (quotInt# x y) in ...
        -- because quotInt# can fail.

  | preInlineUnconditionally env NotTopLevel bndr new_rhs
  = thing_inside (extendIdSubst env bndr (DoneEx new_rhs))
-}

----------------------------------
prepareRhs takes a putative RHS, checks whether it's a PAP or
constructor application and, if so, converts it to ANF, so that the
resulting thing can be inlined more easily.  Thus
        x = (f a, g b)
becomes
        t1 = f a
        t2 = g b
        x = (t1,t2)

We also want to deal well cases like this
        v = (f e1 `cast` co) e2
Here we want to make e1,e2 trivial and get
        x1 = e1; x2 = e2; v = (f x1 `cast` co) v2
That's what the 'go' loop in prepareRhs does

\begin{code}
prepareRhs :: SimplEnv -> OutExpr -> SimplM (SimplEnv, OutExpr)
-- Adds new floats to the env iff that allows us to return a good RHS
prepareRhs env (Cast rhs co)    -- Note [Float coercions]
  | (ty1, _ty2) <- coercionKind co       -- Do *not* do this if rhs has an unlifted type
  , not (isUnLiftedType ty1)            -- see Note [Float coercions (unlifted)]
  = do  { (env', rhs') <- makeTrivial env rhs
        ; return (env', Cast rhs' co) }

prepareRhs env0 rhs0
  = do  { (_is_val, env1, rhs1) <- go 0 env0 rhs0
        ; return (env1, rhs1) }
  where
    go n_val_args env (Cast rhs co)
        = do { (is_val, env', rhs') <- go n_val_args env rhs
             ; return (is_val, env', Cast rhs' co) }
    go n_val_args env (App fun (Type ty))
        = do { (is_val, env', rhs') <- go n_val_args env fun
             ; return (is_val, env', App rhs' (Type ty)) }
    go n_val_args env (App fun arg)
        = do { (is_val, env', fun') <- go (n_val_args+1) env fun
             ; case is_val of
                True -> do { (env'', arg') <- makeTrivial env' arg
                           ; return (True, env'', App fun' arg') }
                False -> return (False, env, App fun arg) }
    go n_val_args env (Var fun)
        = return (is_val, env, Var fun)
        where
          is_val = n_val_args > 0       -- There is at least one arg
                                        -- ...and the fun a constructor or PAP
                 && (isConLikeId fun || n_val_args < idArity fun)
    go _ env other
        = return (False, env, other)
\end{code}


Note [Float coercions]
~~~~~~~~~~~~~~~~~~~~~~
When we find the binding
        x = e `cast` co
we'd like to transform it to
        x' = e
        x = x `cast` co         -- A trivial binding
There's a chance that e will be a constructor application or function, or something
like that, so moving the coerion to the usage site may well cancel the coersions
and lead to further optimisation.  Example:

     data family T a :: *
     data instance T Int = T Int

     foo :: Int -> Int -> Int
     foo m n = ...
        where
          x = T m
          go 0 = 0
          go n = case x of { T m -> go (n-m) }
                -- This case should optimise

Note [Float coercions (unlifted)]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
BUT don't do [Float coercions] if 'e' has an unlifted type.
This *can* happen:

     foo :: Int = (error (# Int,Int #) "urk")
                  `cast` CoUnsafe (# Int,Int #) Int

If do the makeTrivial thing to the error call, we'll get
    foo = case error (# Int,Int #) "urk" of v -> v `cast` ...
But 'v' isn't in scope!

These strange casts can happen as a result of case-of-case
        bar = case (case x of { T -> (# 2,3 #); F -> error "urk" }) of
                (# p,q #) -> p+q


\begin{code}
makeTrivial :: SimplEnv -> OutExpr -> SimplM (SimplEnv, OutExpr)
-- Binds the expression to a variable, if it's not trivial, returning the variable
makeTrivial env expr
  | exprIsTrivial expr
  = return (env, expr)
  | otherwise           -- See Note [Take care] below
  = do  { var <- newId (fsLit "a") (exprType expr)
        ; env' <- completeNonRecX env False var var expr
--	  pprTrace "makeTrivial" (vcat [ppr var <+> ppr (exprArity (substExpr env' (Var var)))
--	  	   		       , ppr expr
--	  	   		       , ppr (substExpr env' (Var var))
--				       , ppr (idArity (fromJust (lookupInScope (seInScope env') var))) ]) $
	; return (env', substExpr env' (Var var)) }
	-- The substitution is needed becase we're constructing a new binding
	--     a = rhs
	-- And if rhs is of form (rhs1 |> co), then we might get
	--     a1 = rhs1
	--     a = a1 |> co
	-- and now a's RHS is trivial and can be substituted out, and that
	-- is what completeNonRecX will do
\end{code}


%************************************************************************
%*                                                                      *
\subsection{Completing a lazy binding}
%*                                                                      *
%************************************************************************

completeBind
  * deals only with Ids, not TyVars
  * takes an already-simplified binder and RHS
  * is used for both recursive and non-recursive bindings
  * is used for both top-level and non-top-level bindings

It does the following:
  - tries discarding a dead binding
  - tries PostInlineUnconditionally
  - add unfolding [this is the only place we add an unfolding]
  - add arity

It does *not* attempt to do let-to-case.  Why?  Because it is used for
  - top-level bindings (when let-to-case is impossible)
  - many situations where the "rhs" is known to be a WHNF
                (so let-to-case is inappropriate).

Nor does it do the atomic-argument thing

\begin{code}
completeBind :: SimplEnv
             -> TopLevelFlag            -- Flag stuck into unfolding
             -> InId                    -- Old binder
             -> OutId -> OutExpr        -- New binder and RHS
             -> SimplM SimplEnv
-- completeBind may choose to do its work
--      * by extending the substitution (e.g. let x = y in ...)
--      * or by adding to the floats in the envt

completeBind env top_lvl old_bndr new_bndr new_rhs
  | postInlineUnconditionally env top_lvl new_bndr occ_info new_rhs unfolding
                -- Inline and discard the binding
  = do  { tick (PostInlineUnconditionally old_bndr)
        ; -- pprTrace "postInlineUnconditionally" (ppr old_bndr <+> ppr new_bndr <+> ppr new_rhs) $
          return (extendIdSubst env old_bndr (DoneEx new_rhs)) }
        -- Use the substitution to make quite, quite sure that the
        -- substitution will happen, since we are going to discard the binding

  | otherwise
  = return (addNonRecWithUnf env new_bndr new_rhs unfolding wkr)
  where
    unfolding | omit_unfolding = NoUnfolding
	      | otherwise      = mkUnfolding (isTopLevel top_lvl) new_rhs
    old_info    = idInfo old_bndr
    occ_info    = occInfo old_info
    wkr		= substWorker env (workerInfo old_info)
    omit_unfolding = isNonRuleLoopBreaker occ_info 
		   --       or not (activeInline env old_bndr)
    		   -- Do *not* trim the unfolding in SimplGently, else
		   -- the specialiser can't see it!

-----------------
addPolyBind :: TopLevelFlag -> SimplEnv -> OutBind -> SimplEnv
-- Add a new binding to the environment, complete with its unfolding
-- but *do not* do postInlineUnconditionally, because we have already
-- processed some of the scope of the binding
-- We still want the unfolding though.  Consider
--	let 
--	      x = /\a. let y = ... in Just y
--	in body
-- Then we float the y-binding out (via abstractFloats and addPolyBind)
-- but 'x' may well then be inlined in 'body' in which case we'd like the 
-- opportunity to inline 'y' too.

addPolyBind top_lvl env (NonRec poly_id rhs)
  = addNonRecWithUnf env poly_id rhs unfolding NoWorker
  where
    unfolding | not (activeInline env poly_id) = NoUnfolding
	      | otherwise		       = mkUnfolding (isTopLevel top_lvl) rhs
		-- addNonRecWithInfo adds the new binding in the
		-- proper way (ie complete with unfolding etc),
		-- and extends the in-scope set

addPolyBind _ env bind@(Rec _) = extendFloats env bind
		-- Hack: letrecs are more awkward, so we extend "by steam"
		-- without adding unfoldings etc.  At worst this leads to
		-- more simplifier iterations

-----------------
addNonRecWithUnf :: SimplEnv
             	  -> OutId -> OutExpr        -- New binder and RHS
		  -> Unfolding -> WorkerInfo -- and unfolding
             	  -> SimplEnv
-- Add suitable IdInfo to the Id, add the binding to the floats, and extend the in-scope set
addNonRecWithUnf env new_bndr rhs unfolding wkr
  = ASSERT( isId new_bndr )
    WARN( new_arity < old_arity || new_arity < dmd_arity, 
          (ptext (sLit "Arity decrease:") <+> ppr final_id <+> ppr old_arity
		<+> ppr new_arity <+> ppr dmd_arity) $$ ppr rhs )
	-- Note [Arity decrease]
    final_id `seq`      -- This seq forces the Id, and hence its IdInfo,
	                -- and hence any inner substitutions
    addNonRec env final_id rhs
	-- The addNonRec adds it to the in-scope set too
  where
	dmd_arity = length $ fst $ splitStrictSig $ idNewStrictness new_bndr
	old_arity = idArity new_bndr

        --      Arity info
	new_arity = exprArity rhs
        new_bndr_info = idInfo new_bndr `setArityInfo` new_arity

        --      Unfolding info
        -- Add the unfolding *only* for non-loop-breakers
        -- Making loop breakers not have an unfolding at all
        -- means that we can avoid tests in exprIsConApp, for example.
        -- This is important: if exprIsConApp says 'yes' for a recursive
        -- thing, then we can get into an infinite loop

        --      Demand info
        -- If the unfolding is a value, the demand info may
        -- go pear-shaped, so we nuke it.  Example:
        --      let x = (a,b) in
        --      case x of (p,q) -> h p q x
        -- Here x is certainly demanded. But after we've nuked
        -- the case, we'll get just
        --      let x = (a,b) in h a b x
        -- and now x is not demanded (I'm assuming h is lazy)
        -- This really happens.  Similarly
        --      let f = \x -> e in ...f..f...
        -- After inlining f at some of its call sites the original binding may
        -- (for example) be no longer strictly demanded.
        -- The solution here is a bit ad hoc...
        info_w_unf = new_bndr_info `setUnfoldingInfo` unfolding
				   `setWorkerInfo`    wkr

        final_info | isEvaldUnfolding unfolding = zapDemandInfo info_w_unf `orElse` info_w_unf
                   | otherwise                  = info_w_unf
	
        final_id = new_bndr `setIdInfo` final_info
\end{code}

Note [Arity decrease]
~~~~~~~~~~~~~~~~~~~~~
Generally speaking the arity of a binding should not decrease.  But it *can* 
legitimately happen becuase of RULES.  Eg
	f = g Int
where g has arity 2, will have arity 2.  But if there's a rewrite rule
	g Int --> h
where h has arity 1, then f's arity will decrease.  Here's a real-life example,
which is in the output of Specialise:

     Rec {
	$dm {Arity 2} = \d.\x. op d
	{-# RULES forall d. $dm Int d = $s$dm #-}
	
	dInt = MkD .... opInt ...
	opInt {Arity 1} = $dm dInt

	$s$dm {Arity 0} = \x. op dInt }

Here opInt has arity 1; but when we apply the rule its arity drops to 0.
That's why Specialise goes to a little trouble to pin the right arity
on specialised functions too.


%************************************************************************
%*                                                                      *
\subsection[Simplify-simplExpr]{The main function: simplExpr}
%*                                                                      *
%************************************************************************

The reason for this OutExprStuff stuff is that we want to float *after*
simplifying a RHS, not before.  If we do so naively we get quadratic
behaviour as things float out.

To see why it's important to do it after, consider this (real) example:

        let t = f x
        in fst t
==>
        let t = let a = e1
                    b = e2
                in (a,b)
        in fst t
==>
        let a = e1
            b = e2
            t = (a,b)
        in
        a       -- Can't inline a this round, cos it appears twice
==>
        e1

Each of the ==> steps is a round of simplification.  We'd save a
whole round if we float first.  This can cascade.  Consider

        let f = g d
        in \x -> ...f...
==>
        let f = let d1 = ..d.. in \y -> e
        in \x -> ...f...
==>
        let d1 = ..d..
        in \x -> ...(\y ->e)...

Only in this second round can the \y be applied, and it
might do the same again.


\begin{code}
simplExpr :: SimplEnv -> CoreExpr -> SimplM CoreExpr
simplExpr env expr = simplExprC env expr mkBoringStop

simplExprC :: SimplEnv -> CoreExpr -> SimplCont -> SimplM CoreExpr
        -- Simplify an expression, given a continuation
simplExprC env expr cont
  = -- pprTrace "simplExprC" (ppr expr $$ ppr cont {- $$ ppr (seIdSubst env) -} $$ ppr (seFloats env) ) $
    do  { (env', expr') <- simplExprF (zapFloats env) expr cont
        ; -- pprTrace "simplExprC ret" (ppr expr $$ ppr expr') $
          -- pprTrace "simplExprC ret3" (ppr (seInScope env')) $
          -- pprTrace "simplExprC ret4" (ppr (seFloats env')) $
          return (wrapFloats env' expr') }

--------------------------------------------------
simplExprF :: SimplEnv -> InExpr -> SimplCont
           -> SimplM (SimplEnv, OutExpr)

simplExprF env e cont
  = -- pprTrace "simplExprF" (ppr e $$ ppr cont $$ ppr (seTvSubst env) $$ ppr (seIdSubst env) {- $$ ppr (seFloats env) -} ) $
    simplExprF' env e cont

simplExprF' :: SimplEnv -> InExpr -> SimplCont
            -> SimplM (SimplEnv, OutExpr)
simplExprF' env (Var v)        cont = simplVar env v cont
simplExprF' env (Lit lit)      cont = rebuild env (Lit lit) cont
simplExprF' env (Note n expr)  cont = simplNote env n expr cont
simplExprF' env (Cast body co) cont = simplCast env body co cont
simplExprF' env (App fun arg)  cont = simplExprF env fun $
                                      ApplyTo NoDup arg env cont

simplExprF' env expr@(Lam _ _) cont
  = simplLam env (map zap bndrs) body cont
        -- The main issue here is under-saturated lambdas
        --   (\x1. \x2. e) arg1
        -- Here x1 might have "occurs-once" occ-info, because occ-info
        -- is computed assuming that a group of lambdas is applied
        -- all at once.  If there are too few args, we must zap the
        -- occ-info.
  where
    n_args   = countArgs cont
    n_params = length bndrs
    (bndrs, body) = collectBinders expr
    zap | n_args >= n_params = \b -> b
        | otherwise          = \b -> if isTyVar b then b
                                     else zapLamIdInfo b
        -- NB: we count all the args incl type args
        -- so we must count all the binders (incl type lambdas)

simplExprF' env (Type ty) cont
  = ASSERT( contIsRhsOrArg cont )
    do  { ty' <- simplType env ty
        ; rebuild env (Type ty') cont }

simplExprF' env (Case scrut bndr _ alts) cont
  | not (switchIsOn (getSwitchChecker env) NoCaseOfCase)
  =     -- Simplify the scrutinee with a Select continuation
    simplExprF env scrut (Select NoDup bndr alts env cont)

  | otherwise
  =     -- If case-of-case is off, simply simplify the case expression
        -- in a vanilla Stop context, and rebuild the result around it
    do  { case_expr' <- simplExprC env scrut case_cont
        ; rebuild env case_expr' cont }
  where
    case_cont = Select NoDup bndr alts env mkBoringStop

simplExprF' env (Let (Rec pairs) body) cont
  = do  { env' <- simplRecBndrs env (map fst pairs)
                -- NB: bndrs' don't have unfoldings or rules
                -- We add them as we go down

        ; env'' <- simplRecBind env' NotTopLevel pairs
        ; simplExprF env'' body cont }

simplExprF' env (Let (NonRec bndr rhs) body) cont
  = simplNonRecE env bndr (rhs, env) ([], body) cont

---------------------------------
simplType :: SimplEnv -> InType -> SimplM OutType
        -- Kept monadic just so we can do the seqType
simplType env ty
  = -- pprTrace "simplType" (ppr ty $$ ppr (seTvSubst env)) $
    seqType new_ty   `seq`   return new_ty
  where
    new_ty = substTy env ty
\end{code}


%************************************************************************
%*                                                                      *
\subsection{The main rebuilder}
%*                                                                      *
%************************************************************************

\begin{code}
rebuild :: SimplEnv -> OutExpr -> SimplCont -> SimplM (SimplEnv, OutExpr)
-- At this point the substitution in the SimplEnv should be irrelevant
-- only the in-scope set and floats should matter
rebuild env expr cont0
  = -- pprTrace "rebuild" (ppr expr $$ ppr cont0 $$ ppr (seFloats env)) $
    case cont0 of
      Stop {}                      -> return (env, expr)
      CoerceIt co cont             -> rebuild env (mkCoerce co expr) cont
      Select _ bndr alts se cont   -> rebuildCase (se `setFloats` env) expr bndr alts cont
      StrictArg fun _ info cont    -> rebuildCall env (fun `App` expr) info cont
      StrictBind b bs body se cont -> do { env' <- simplNonRecX (se `setFloats` env) b expr
                                         ; simplLam env' bs body cont }
      ApplyTo _ arg se cont        -> do { arg' <- simplExpr (se `setInScope` env) arg
                                         ; rebuild env (App expr arg') cont }
\end{code}


%************************************************************************
%*                                                                      *
\subsection{Lambdas}
%*                                                                      *
%************************************************************************

\begin{code}
simplCast :: SimplEnv -> InExpr -> Coercion -> SimplCont
          -> SimplM (SimplEnv, OutExpr)
simplCast env body co0 cont0
  = do  { co1 <- simplType env co0
        ; simplExprF env body (addCoerce co1 cont0) }
  where
       addCoerce co cont = add_coerce co (coercionKind co) cont

       add_coerce _co (s1, k1) cont     -- co :: ty~ty
         | s1 `coreEqType` k1 = cont    -- is a no-op

       add_coerce co1 (s1, _k2) (CoerceIt co2 cont)
         | (_l1, t1) <- coercionKind co2
		-- 	e |> (g1 :: S1~L) |> (g2 :: L~T1)
                -- ==>
                --      e,                       if S1=T1
                --      e |> (g1 . g2 :: S1~T1)  otherwise
                --
                -- For example, in the initial form of a worker
                -- we may find  (coerce T (coerce S (\x.e))) y
                -- and we'd like it to simplify to e[y/x] in one round
                -- of simplification
         , s1 `coreEqType` t1  = cont            -- The coerces cancel out
         | otherwise           = CoerceIt (mkTransCoercion co1 co2) cont

       add_coerce co (s1s2, _t1t2) (ApplyTo dup (Type arg_ty) arg_se cont)
                -- (f |> g) ty  --->   (f ty) |> (g @ ty)
                -- This implements the PushT rule from the paper
         | Just (tyvar,_) <- splitForAllTy_maybe s1s2
         , not (isCoVar tyvar)
         = ApplyTo dup (Type ty') (zapSubstEnv env) (addCoerce (mkInstCoercion co ty') cont)
         where
           ty' = substTy (arg_se `setInScope` env) arg_ty

        -- ToDo: the PushC rule is not implemented at all

       add_coerce co (s1s2, _t1t2) (ApplyTo dup arg arg_se cont)
         | not (isTypeArg arg)  -- This implements the Push rule from the paper
         , isFunTy s1s2   -- t1t2 must be a function type, becuase it's applied
                --      (e |> (g :: s1s2 ~ t1->t2)) f
                -- ===>
                --      (e (f |> (arg g :: t1~s1))
		--	|> (res g :: s2->t2)
                --
                -- t1t2 must be a function type, t1->t2, because it's applied
                -- to something but s1s2 might conceivably not be
                --
                -- When we build the ApplyTo we can't mix the out-types
                -- with the InExpr in the argument, so we simply substitute
                -- to make it all consistent.  It's a bit messy.
                -- But it isn't a common case.
                --
                -- Example of use: Trac #995
         = ApplyTo dup new_arg (zapSubstEnv env) (addCoerce co2 cont)
         where
           -- we split coercion t1->t2 ~ s1->s2 into t1 ~ s1 and
           -- t2 ~ s2 with left and right on the curried form:
           --    (->) t1 t2 ~ (->) s1 s2
           [co1, co2] = decomposeCo 2 co
           new_arg    = mkCoerce (mkSymCoercion co1) arg'
           arg'       = substExpr (arg_se `setInScope` env) arg

       add_coerce co _ cont = CoerceIt co cont
\end{code}


%************************************************************************
%*                                                                      *
\subsection{Lambdas}
%*                                                                      *
%************************************************************************

\begin{code}
simplLam :: SimplEnv -> [InId] -> InExpr -> SimplCont
         -> SimplM (SimplEnv, OutExpr)

simplLam env [] body cont = simplExprF env body cont

        -- Beta reduction
simplLam env (bndr:bndrs) body (ApplyTo _ arg arg_se cont)
  = do  { tick (BetaReduction bndr)
        ; simplNonRecE env bndr (arg, arg_se) (bndrs, body) cont }

        -- Not enough args, so there are real lambdas left to put in the result
simplLam env bndrs body cont
  = do  { (env', bndrs') <- simplLamBndrs env bndrs
        ; body' <- simplExpr env' body
        ; new_lam <- mkLam env' bndrs' body'
        ; rebuild env' new_lam cont }

------------------
simplNonRecE :: SimplEnv
             -> InId                    -- The binder
             -> (InExpr, SimplEnv)      -- Rhs of binding (or arg of lambda)
             -> ([InBndr], InExpr)      -- Body of the let/lambda
                                        --      \xs.e
             -> SimplCont
             -> SimplM (SimplEnv, OutExpr)

-- simplNonRecE is used for
--  * non-top-level non-recursive lets in expressions
--  * beta reduction
--
-- It deals with strict bindings, via the StrictBind continuation,
-- which may abort the whole process
--
-- The "body" of the binding comes as a pair of ([InId],InExpr)
-- representing a lambda; so we recurse back to simplLam
-- Why?  Because of the binder-occ-info-zapping done before
--       the call to simplLam in simplExprF (Lam ...)

	-- First deal with type applications and type lets
	--   (/\a. e) (Type ty)   and   (let a = Type ty in e)
simplNonRecE env bndr (Type ty_arg, rhs_se) (bndrs, body) cont
  = ASSERT( isTyVar bndr )
    do	{ ty_arg' <- simplType (rhs_se `setInScope` env) ty_arg
	; simplLam (extendTvSubst env bndr ty_arg') bndrs body cont }

simplNonRecE env bndr (rhs, rhs_se) (bndrs, body) cont
  | preInlineUnconditionally env NotTopLevel bndr rhs
  = do  { tick (PreInlineUnconditionally bndr)
        ; simplLam (extendIdSubst env bndr (mkContEx rhs_se rhs)) bndrs body cont }

  | isStrictId bndr
  = do  { simplExprF (rhs_se `setFloats` env) rhs
                     (StrictBind bndr bndrs body env cont) }

  | otherwise
  = ASSERT( not (isTyVar bndr) )
    do  { (env1, bndr1) <- simplNonRecBndr env bndr
        ; let (env2, bndr2) = addBndrRules env1 bndr bndr1
        ; env3 <- simplLazyBind env2 NotTopLevel NonRecursive bndr bndr2 rhs rhs_se
        ; simplLam env3 bndrs body cont }
\end{code}


%************************************************************************
%*                                                                      *
\subsection{Notes}
%*                                                                      *
%************************************************************************

\begin{code}
-- Hack alert: we only distinguish subsumed cost centre stacks for the
-- purposes of inlining.  All other CCCSs are mapped to currentCCS.
simplNote :: SimplEnv -> Note -> CoreExpr -> SimplCont
          -> SimplM (SimplEnv, OutExpr)
simplNote env (SCC cc) e cont
  | pushCCisNop cc (getEnclosingCC env)  -- scc "f" (...(scc "f" e)...) 
  = simplExprF env e cont	         -- ==>  scc "f" (...e...)
  | otherwise
  = do  { e' <- simplExpr (setEnclosingCC env currentCCS) e
        ; rebuild env (mkSCC cc e') cont }

-- See notes with SimplMonad.inlineMode
simplNote env InlineMe e cont
  | Just (inside, outside) <- splitInlineCont cont  -- Boring boring continuation; see notes above
  = do  {                       -- Don't inline inside an INLINE expression
          e' <- simplExprC (setMode inlineMode env) e inside
        ; rebuild env (mkInlineMe e') outside }

  | otherwise   -- Dissolve the InlineMe note if there's
                -- an interesting context of any kind to combine with
                -- (even a type application -- anything except Stop)
  = simplExprF env e cont

simplNote env (CoreNote s) e cont = do
    e' <- simplExpr env e
    rebuild env (Note (CoreNote s) e') cont
\end{code}


%************************************************************************
%*                                                                      *
\subsection{Dealing with calls}
%*                                                                      *
%************************************************************************

\begin{code}
simplVar :: SimplEnv -> Id -> SimplCont -> SimplM (SimplEnv, OutExpr)
simplVar env var cont
  = case substId env var of
        DoneEx e         -> simplExprF (zapSubstEnv env) e cont
        ContEx tvs ids e -> simplExprF (setSubstEnv env tvs ids) e cont
        DoneId var1      -> completeCall (zapSubstEnv env) var1 cont
                -- Note [zapSubstEnv]
                -- The template is already simplified, so don't re-substitute.
                -- This is VITAL.  Consider
                --      let x = e in
                --      let y = \z -> ...x... in
                --      \ x -> ...y...
                -- We'll clone the inner \x, adding x->x' in the id_subst
                -- Then when we inline y, we must *not* replace x by x' in
                -- the inlined copy!!

---------------------------------------------------------
--      Dealing with a call site

completeCall :: SimplEnv -> Id -> SimplCont -> SimplM (SimplEnv, OutExpr)
completeCall env var cont
  = do  { let   (args,call_cont) = contArgs cont
                -- The args are OutExprs, obtained by *lazily* substituting
                -- in the args found in cont.  These args are only examined
                -- to limited depth (unless a rule fires).  But we must do
                -- the substitution; rule matching on un-simplified args would
                -- be bogus

        ------------- First try rules ----------------
        -- Do this before trying inlining.  Some functions have
        -- rules *and* are strict; in this case, we don't want to
        -- inline the wrapper of the non-specialised thing; better
        -- to call the specialised thing instead.
        --
        -- We used to use the black-listing mechanism to ensure that inlining of
        -- the wrapper didn't occur for things that have specialisations till a
        -- later phase, so but now we just try RULES first
	-- 
	-- See also Note [Rules for recursive functions]
	; mb_rule <- tryRules env var args call_cont
	; case mb_rule of {
	     Just (n_args, rule_rhs) -> simplExprF env rule_rhs (dropArgs n_args cont) ;
                 -- The ruleArity says how many args the rule consumed
           ; Nothing -> do       -- No rules


        ------------- Next try inlining ----------------
        { dflags <- getDOptsSmpl
        ; let   arg_infos = [interestingArg arg | arg <- args, isValArg arg]
                n_val_args = length arg_infos
                interesting_cont = interestingCallContext call_cont
                active_inline = activeInline env var
                maybe_inline  = callSiteInline dflags active_inline var
                                               (null args) arg_infos interesting_cont
        ; case maybe_inline of {
            Just unfolding      -- There is an inlining!
              ->  do { tick (UnfoldingDone var)
                     ; (if dopt Opt_D_dump_inlinings dflags then
                           pprTrace ("Inlining done: " ++ showSDoc (ppr var)) (vcat [
                                text "Before:" <+> ppr var <+> sep (map pprParendExpr args),
                                text "Inlined fn: " <+> nest 2 (ppr unfolding),
                                text "Cont:  " <+> ppr call_cont])
                         else
                                id)
                       simplExprF env unfolding cont }

            ; Nothing ->                -- No inlining!

        ------------- No inlining! ----------------
        -- Next, look for rules or specialisations that match
        --
        rebuildCall env (Var var)
                    (mkArgInfo var n_val_args call_cont) cont
    }}}}

rebuildCall :: SimplEnv
            -> OutExpr       -- Function 
            -> ArgInfo
            -> SimplCont
            -> SimplM (SimplEnv, OutExpr)
rebuildCall env fun (ArgInfo { ai_strs = [] }) cont
  -- When we run out of strictness args, it means
  -- that the call is definitely bottom; see SimplUtils.mkArgInfo
  -- Then we want to discard the entire strict continuation.  E.g.
  --    * case (error "hello") of { ... }
  --    * (error "Hello") arg
  --    * f (error "Hello") where f is strict
  --    etc
  -- Then, especially in the first of these cases, we'd like to discard
  -- the continuation, leaving just the bottoming expression.  But the
  -- type might not be right, so we may have to add a coerce.
  | not (contIsTrivial cont)     -- Only do this if there is a non-trivial
  = return (env, mk_coerce fun)  -- contination to discard, else we do it
  where                          -- again and again!
    fun_ty  = exprType fun
    cont_ty = contResultType env fun_ty cont
    co      = mkUnsafeCoercion fun_ty cont_ty
    mk_coerce expr | cont_ty `coreEqType` fun_ty = expr
                   | otherwise = mkCoerce co expr

rebuildCall env fun info (ApplyTo _ (Type arg_ty) se cont)
  = do  { ty' <- simplType (se `setInScope` env) arg_ty
        ; rebuildCall env (fun `App` Type ty') info cont }

rebuildCall env fun 
           (ArgInfo { ai_rules = has_rules, ai_strs = str:strs, ai_discs = disc:discs })
           (ApplyTo _ arg arg_se cont)
  | str 	        -- Strict argument
  = -- pprTrace "Strict Arg" (ppr arg $$ ppr (seIdSubst env) $$ ppr (seInScope env)) $
    simplExprF (arg_se `setFloats` env) arg
               (StrictArg fun cci arg_info' cont)
                -- Note [Shadowing]

  | otherwise                           -- Lazy argument
        -- DO NOT float anything outside, hence simplExprC
        -- There is no benefit (unlike in a let-binding), and we'd
        -- have to be very careful about bogus strictness through
        -- floating a demanded let.
  = do  { arg' <- simplExprC (arg_se `setInScope` env) arg
                             (mkLazyArgStop cci)
        ; rebuildCall env (fun `App` arg') arg_info' cont }
  where
    arg_info' = ArgInfo { ai_rules = has_rules, ai_strs = strs, ai_discs = discs }
    cci | has_rules || disc > 0 = ArgCtxt has_rules disc  -- Be keener here
        | otherwise             = BoringCtxt              -- Nothing interesting

rebuildCall env fun _ cont
  = rebuild env fun cont
\end{code}

Note [Shadowing]
~~~~~~~~~~~~~~~~
This part of the simplifier may break the no-shadowing invariant
Consider
        f (...(\a -> e)...) (case y of (a,b) -> e')
where f is strict in its second arg
If we simplify the innermost one first we get (...(\a -> e)...)
Simplifying the second arg makes us float the case out, so we end up with
        case y of (a,b) -> f (...(\a -> e)...) e'
So the output does not have the no-shadowing invariant.  However, there is
no danger of getting name-capture, because when the first arg was simplified
we used an in-scope set that at least mentioned all the variables free in its
static environment, and that is enough.

We can't just do innermost first, or we'd end up with a dual problem:
        case x of (a,b) -> f e (...(\a -> e')...)

I spent hours trying to recover the no-shadowing invariant, but I just could
not think of an elegant way to do it.  The simplifier is already knee-deep in
continuations.  We have to keep the right in-scope set around; AND we have
to get the effect that finding (error "foo") in a strict arg position will
discard the entire application and replace it with (error "foo").  Getting
all this at once is TOO HARD!


%************************************************************************
%*                                                                      *
                Rewrite rules
%*                                                                      *
%************************************************************************

\begin{code}
tryRules :: SimplEnv -> Id -> [OutExpr] -> SimplCont 
	 -> SimplM (Maybe (Arity, CoreExpr))	     -- The arity is the number of
	    	   	  	  		     -- args consumed by the rule
tryRules env fn args call_cont
  = do {  dflags <- getDOptsSmpl
        ; rule_base <- getSimplRules
        ; let   in_scope   = getInScope env
	  	rules      = getRules rule_base fn
                maybe_rule = case activeRule dflags env of
                                Nothing     -> Nothing  -- No rules apply
                                Just act_fn -> lookupRule act_fn in_scope
                                                          fn args rules 
        ; case (rules, maybe_rule) of {
	    ([], _)      	        -> return Nothing ;
	    (_,  Nothing) 	        -> return Nothing ;
            (_,  Just (rule, rule_rhs)) -> do

        { tick (RuleFired (ru_name rule))
        ; (if dopt Opt_D_dump_rule_firings dflags then
                   pprTrace "Rule fired" (vcat [
                        text "Rule:" <+> ftext (ru_name rule),
                        text "Before:" <+> ppr fn <+> sep (map pprParendExpr args),
                        text "After: " <+> pprCoreExpr rule_rhs,
                        text "Cont:  " <+> ppr call_cont])
                 else
                        id)             $
           return (Just (ruleArity rule, rule_rhs)) }}}
\end{code}

Note [Rules for recursive functions]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
You might think that we shouldn't apply rules for a loop breaker:
doing so might give rise to an infinite loop, because a RULE is
rather like an extra equation for the function:
     RULE:           f (g x) y = x+y
     Eqn:            f a     y = a-y

But it's too drastic to disable rules for loop breakers.
Even the foldr/build rule would be disabled, because foldr
is recursive, and hence a loop breaker:
     foldr k z (build g) = g k z
So it's up to the programmer: rules can cause divergence


%************************************************************************
%*                                                                      *
                Rebuilding a cse expression
%*                                                                      *
%************************************************************************

Note [Case elimination]
~~~~~~~~~~~~~~~~~~~~~~~
The case-elimination transformation discards redundant case expressions.
Start with a simple situation:

        case x# of      ===>   e[x#/y#]
          y# -> e

(when x#, y# are of primitive type, of course).  We can't (in general)
do this for algebraic cases, because we might turn bottom into
non-bottom!

The code in SimplUtils.prepareAlts has the effect of generalise this
idea to look for a case where we're scrutinising a variable, and we
know that only the default case can match.  For example:

        case x of
          0#      -> ...
          DEFAULT -> ...(case x of
                         0#      -> ...
                         DEFAULT -> ...) ...

Here the inner case is first trimmed to have only one alternative, the
DEFAULT, after which it's an instance of the previous case.  This
really only shows up in eliminating error-checking code.

We also make sure that we deal with this very common case:

        case e of
          x -> ...x...

Here we are using the case as a strict let; if x is used only once
then we want to inline it.  We have to be careful that this doesn't
make the program terminate when it would have diverged before, so we
check that
        - e is already evaluated (it may so if e is a variable)
        - x is used strictly, or

Lastly, the code in SimplUtils.mkCase combines identical RHSs.  So

        case e of       ===> case e of DEFAULT -> r
           True  -> r
           False -> r

Now again the case may be elminated by the CaseElim transformation.


Further notes about case elimination
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider:       test :: Integer -> IO ()
                test = print

Turns out that this compiles to:
    Print.test
      = \ eta :: Integer
          eta1 :: State# RealWorld ->
          case PrelNum.< eta PrelNum.zeroInteger of wild { __DEFAULT ->
          case hPutStr stdout
                 (PrelNum.jtos eta ($w[] @ Char))
                 eta1
          of wild1 { (# new_s, a4 #) -> PrelIO.lvl23 new_s  }}

Notice the strange '<' which has no effect at all. This is a funny one.
It started like this:

f x y = if x < 0 then jtos x
          else if y==0 then "" else jtos x

At a particular call site we have (f v 1).  So we inline to get

        if v < 0 then jtos x
        else if 1==0 then "" else jtos x

Now simplify the 1==0 conditional:

        if v<0 then jtos v else jtos v

Now common-up the two branches of the case:

        case (v<0) of DEFAULT -> jtos v

Why don't we drop the case?  Because it's strict in v.  It's technically
wrong to drop even unnecessary evaluations, and in practice they
may be a result of 'seq' so we *definitely* don't want to drop those.
I don't really know how to improve this situation.

\begin{code}
---------------------------------------------------------
--      Eliminate the case if possible

rebuildCase, reallyRebuildCase
   :: SimplEnv
   -> OutExpr          -- Scrutinee
   -> InId             -- Case binder
   -> [InAlt]          -- Alternatives (inceasing order)
   -> SimplCont
   -> SimplM (SimplEnv, OutExpr)

--------------------------------------------------
--      1. Eliminate the case if there's a known constructor
--------------------------------------------------

rebuildCase env scrut case_bndr alts cont
  | Just (con,args) <- exprIsConApp_maybe scrut
        -- Works when the scrutinee is a variable with a known unfolding
        -- as well as when it's an explicit constructor application
  = knownCon env scrut (DataAlt con) args case_bndr alts cont

  | Lit lit <- scrut    -- No need for same treatment as constructors
                        -- because literals are inlined more vigorously
  = knownCon env scrut (LitAlt lit) [] case_bndr alts cont


--------------------------------------------------
--      2. Eliminate the case if scrutinee is evaluated
--------------------------------------------------

rebuildCase env scrut case_bndr [(_, bndrs, rhs)] cont
  -- See if we can get rid of the case altogether
  -- See Note [Case eliminiation] 
  -- mkCase made sure that if all the alternatives are equal,
  -- then there is now only one (DEFAULT) rhs
 | all isDeadBinder bndrs       -- bndrs are [InId]

        -- Check that the scrutinee can be let-bound instead of case-bound
 , exprOkForSpeculation scrut
                -- OK not to evaluate it
                -- This includes things like (==# a# b#)::Bool
                -- so that we simplify
                --      case ==# a# b# of { True -> x; False -> x }
                -- to just
                --      x
                -- This particular example shows up in default methods for
                -- comparision operations (e.g. in (>=) for Int.Int32)
        || exprIsHNF scrut                      -- It's already evaluated
        || var_demanded_later scrut             -- It'll be demanded later

--      || not opt_SimplPedanticBottoms)        -- Or we don't care!
--      We used to allow improving termination by discarding cases, unless -fpedantic-bottoms was on,
--      but that breaks badly for the dataToTag# primop, which relies on a case to evaluate
--      its argument:  case x of { y -> dataToTag# y }
--      Here we must *not* discard the case, because dataToTag# just fetches the tag from
--      the info pointer.  So we'll be pedantic all the time, and see if that gives any
--      other problems
--      Also we don't want to discard 'seq's
  = do  { tick (CaseElim case_bndr)
        ; env' <- simplNonRecX env case_bndr scrut
        ; simplExprF env' rhs cont }
  where
        -- The case binder is going to be evaluated later,
        -- and the scrutinee is a simple variable
    var_demanded_later (Var v) = isStrictDmd (idNewDemandInfo case_bndr)
                                 && not (isTickBoxOp v)
                                    -- ugly hack; covering this case is what
                                    -- exprOkForSpeculation was intended for.
    var_demanded_later _       = False

rebuildCase env scrut case_bndr alts@[(_, bndrs, rhs)] cont
  | all isDeadBinder (case_bndr : bndrs)  -- So this is just 'seq'
  = 	-- For this case, see Note [Rules for seq] in MkId
    do { let rhs' = substExpr env rhs
             out_args = [Type (substTy env (idType case_bndr)), 
	     	         Type (exprType rhs'), scrut, rhs']
	     	      -- Lazily evaluated, so we don't do most of this
       ; mb_rule <- tryRules env seqId out_args cont
       ; case mb_rule of 
           Just (n_args, res) -> simplExprF (zapSubstEnv env) 
	   	       		    	    (mkApps res (drop n_args out_args))
                                            cont
	   Nothing -> reallyRebuildCase env scrut case_bndr alts cont }

rebuildCase env scrut case_bndr alts cont
  = reallyRebuildCase env scrut case_bndr alts cont

--------------------------------------------------
--      3. Catch-all case
--------------------------------------------------

reallyRebuildCase env scrut case_bndr alts cont
  = do  {       -- Prepare the continuation;
                -- The new subst_env is in place
          (env', dup_cont, nodup_cont) <- prepareCaseCont env alts cont

        -- Simplify the alternatives
        ; (scrut', case_bndr', alts') <- simplAlts env' scrut case_bndr alts dup_cont

	-- Check for empty alternatives
	; if null alts' then missingAlt env case_bndr alts cont
	  else do
	{ case_expr <- mkCase scrut' case_bndr' alts'

	-- Notice that rebuild gets the in-scope set from env, not alt_env
	-- The case binder *not* scope over the whole returned case-expression
	; rebuild env' case_expr nodup_cont } }
\end{code}

simplCaseBinder checks whether the scrutinee is a variable, v.  If so,
try to eliminate uses of v in the RHSs in favour of case_bndr; that
way, there's a chance that v will now only be used once, and hence
inlined.

Historical note: we use to do the "case binder swap" in the Simplifier
so there were additional complications if the scrutinee was a variable.
Now the binder-swap stuff is done in the occurrence analyer; see
OccurAnal Note [Binder swap].

Note [zapOccInfo]
~~~~~~~~~~~~~~~~~
If the case binder is not dead, then neither are the pattern bound
variables:  
        case <any> of x { (a,b) ->
        case x of { (p,q) -> p } }
Here (a,b) both look dead, but come alive after the inner case is eliminated.
The point is that we bring into the envt a binding
        let x = (a,b)
after the outer case, and that makes (a,b) alive.  At least we do unless
the case binder is guaranteed dead.

Note [Improving seq]
~~~~~~~~~~~~~~~~~~~
Consider
        type family F :: * -> *
        type instance F Int = Int

        ... case e of x { DEFAULT -> rhs } ...

where x::F Int.  Then we'd like to rewrite (F Int) to Int, getting

        case e `cast` co of x'::Int
           I# x# -> let x = x' `cast` sym co
                    in rhs

so that 'rhs' can take advantage of the form of x'.  Notice that Note
[Case of cast] may then apply to the result.

This showed up in Roman's experiments.  Example:
  foo :: F Int -> Int -> Int
  foo t n = t `seq` bar n
     where
       bar 0 = 0
       bar n = bar (n - case t of TI i -> i)
Here we'd like to avoid repeated evaluating t inside the loop, by
taking advantage of the `seq`.

At one point I did transformation in LiberateCase, but it's more robust here.
(Otherwise, there's a danger that we'll simply drop the 'seq' altogether, before
LiberateCase gets to see it.)




\begin{code}
improveSeq :: (FamInstEnv, FamInstEnv) -> SimplEnv
	   -> OutExpr -> InId -> OutId -> [InAlt]
	   -> SimplM (SimplEnv, OutExpr, OutId)
-- Note [Improving seq]
improveSeq fam_envs env scrut case_bndr case_bndr1 [(DEFAULT,_,_)]
  | Just (co, ty2) <- topNormaliseType fam_envs (idType case_bndr1)
  =  do { case_bndr2 <- newId (fsLit "nt") ty2
        ; let rhs  = DoneEx (Var case_bndr2 `Cast` mkSymCoercion co)
              env2 = extendIdSubst env case_bndr rhs
        ; return (env2, scrut `Cast` co, case_bndr2) }

improveSeq _ env scrut _ case_bndr1 _
  = return (env, scrut, case_bndr1)

{-
    improve_case_bndr env scrut case_bndr
        -- See Note [no-case-of-case]
	--  | switchIsOn (getSwitchChecker env) NoCaseOfCase
	--  = (env, case_bndr)

        | otherwise     -- Failed try; see Note [Suppressing the case binder-swap]
                        --     not (isEvaldUnfolding (idUnfolding v))
        = case scrut of
            Var v -> (modifyInScope env1 v case_bndr', case_bndr')
                -- Note about using modifyInScope for v here
                -- We could extend the substitution instead, but it would be
                -- a hack because then the substitution wouldn't be idempotent
                -- any more (v is an OutId).  And this does just as well.

            Cast (Var v) co -> (addBinderUnfolding env1 v rhs, case_bndr')
                            where
                                rhs = Cast (Var case_bndr') (mkSymCoercion co)

            _ -> (env, case_bndr)
        where
          case_bndr' = zapIdOccInfo case_bndr
          env1       = modifyInScope env case_bndr case_bndr'
-}
\end{code}


simplAlts does two things:

1.  Eliminate alternatives that cannot match, including the
    DEFAULT alternative.

2.  If the DEFAULT alternative can match only one possible constructor,
    then make that constructor explicit.
    e.g.
        case e of x { DEFAULT -> rhs }
     ===>
        case e of x { (a,b) -> rhs }
    where the type is a single constructor type.  This gives better code
    when rhs also scrutinises x or e.

Here "cannot match" includes knowledge from GADTs

It's a good idea do do this stuff before simplifying the alternatives, to
avoid simplifying alternatives we know can't happen, and to come up with
the list of constructors that are handled, to put into the IdInfo of the
case binder, for use when simplifying the alternatives.

Eliminating the default alternative in (1) isn't so obvious, but it can
happen:

data Colour = Red | Green | Blue

f x = case x of
        Red -> ..
        Green -> ..
        DEFAULT -> h x

h y = case y of
        Blue -> ..
        DEFAULT -> [ case y of ... ]

If we inline h into f, the default case of the inlined h can't happen.
If we don't notice this, we may end up filtering out *all* the cases
of the inner case y, which give us nowhere to go!


\begin{code}
simplAlts :: SimplEnv
          -> OutExpr
          -> InId                       -- Case binder
          -> [InAlt]			-- Non-empty
	  -> SimplCont
          -> SimplM (OutExpr, OutId, [OutAlt])  -- Includes the continuation
-- Like simplExpr, this just returns the simplified alternatives;
-- it not return an environment

simplAlts env scrut case_bndr alts cont'
  = -- pprTrace "simplAlts" (ppr alts $$ ppr (seIdSubst env)) $
    do  { let env0 = zapFloats env

        ; (env1, case_bndr1) <- simplBinder env0 case_bndr

        ; fam_envs <- getFamEnvs
	; (alt_env', scrut', case_bndr') <- improveSeq fam_envs env1 scrut 
						       case_bndr case_bndr1 alts

        ; (imposs_deflt_cons, in_alts) <- prepareAlts alt_env' scrut' case_bndr' alts

        ; alts' <- mapM (simplAlt alt_env' imposs_deflt_cons case_bndr' cont') in_alts
        ; return (scrut', case_bndr', alts') }

------------------------------------
simplAlt :: SimplEnv
         -> [AltCon]    -- These constructors can't be present when
                        -- matching the DEFAULT alternative
         -> OutId       -- The case binder
         -> SimplCont
         -> InAlt
         -> SimplM OutAlt

simplAlt env imposs_deflt_cons case_bndr' cont' (DEFAULT, bndrs, rhs)
  = ASSERT( null bndrs )
    do  { let env' = addBinderOtherCon env case_bndr' imposs_deflt_cons
                -- Record the constructors that the case-binder *can't* be.
        ; rhs' <- simplExprC env' rhs cont'
        ; return (DEFAULT, [], rhs') }

simplAlt env _ case_bndr' cont' (LitAlt lit, bndrs, rhs)
  = ASSERT( null bndrs )
    do  { let env' = addBinderUnfolding env case_bndr' (Lit lit)
        ; rhs' <- simplExprC env' rhs cont'
        ; return (LitAlt lit, [], rhs') }

simplAlt env _ case_bndr' cont' (DataAlt con, vs, rhs)
  = do  {       -- Deal with the pattern-bound variables
                -- Mark the ones that are in ! positions in the
                -- data constructor as certainly-evaluated.
                -- NB: simplLamBinders preserves this eval info
          let vs_with_evals = add_evals (dataConRepStrictness con)
        ; (env', vs') <- simplLamBndrs env vs_with_evals

                -- Bind the case-binder to (con args)
        ; let inst_tys' = tyConAppArgs (idType case_bndr')
              con_args  = map Type inst_tys' ++ varsToCoreExprs vs'
              env''     = addBinderUnfolding env' case_bndr'
                                             (mkConApp con con_args)

        ; rhs' <- simplExprC env'' rhs cont'
        ; return (DataAlt con, vs', rhs') }
  where
        -- add_evals records the evaluated-ness of the bound variables of
        -- a case pattern.  This is *important*.  Consider
        --      data T = T !Int !Int
        --
        --      case x of { T a b -> T (a+1) b }
        --
        -- We really must record that b is already evaluated so that we don't
        -- go and re-evaluate it when constructing the result.
        -- See Note [Data-con worker strictness] in MkId.lhs
    add_evals the_strs
        = go vs the_strs
        where
          go [] [] = []
          go (v:vs') strs | isTyVar v = v : go vs' strs
          go (v:vs') (str:strs)
            | isMarkedStrict str = evald_v  : go vs' strs
            | otherwise          = zapped_v : go vs' strs
            where
              zapped_v = zap_occ_info v
              evald_v  = zapped_v `setIdUnfolding` evaldUnfolding
          go _ _ = pprPanic "cat_evals" (ppr con $$ ppr vs $$ ppr the_strs)

	-- See Note [zapOccInfo]
        -- zap_occ_info: if the case binder is alive, then we add the unfolding
        --      case_bndr = C vs
        -- to the envt; so vs are now very much alive
        -- Note [Aug06] I can't see why this actually matters, but it's neater
        --        case e of t { (a,b) -> ...(case t of (p,q) -> p)... }
        --   ==>  case e of t { (a,b) -> ...(a)... }
        -- Look, Ma, a is alive now.
    zap_occ_info = zapCasePatIdOcc case_bndr'

addBinderUnfolding :: SimplEnv -> Id -> CoreExpr -> SimplEnv
addBinderUnfolding env bndr rhs
  = modifyInScope env (bndr `setIdUnfolding` mkUnfolding False rhs)

addBinderOtherCon :: SimplEnv -> Id -> [AltCon] -> SimplEnv
addBinderOtherCon env bndr cons
  = modifyInScope env (bndr `setIdUnfolding` mkOtherCon cons)

zapCasePatIdOcc :: Id -> Id -> Id
-- Consider  case e of b { (a,b) -> ... }
-- Then if we bind b to (a,b) in "...", and b is not dead,
-- then we must zap the deadness info on a,b
zapCasePatIdOcc case_bndr
  | isDeadBinder case_bndr = \ pat_id -> pat_id
  | otherwise	 	   = \ pat_id -> zapIdOccInfo pat_id
\end{code}


%************************************************************************
%*                                                                      *
\subsection{Known constructor}
%*                                                                      *
%************************************************************************

We are a bit careful with occurrence info.  Here's an example

        (\x* -> case x of (a*, b) -> f a) (h v, e)

where the * means "occurs once".  This effectively becomes
        case (h v, e) of (a*, b) -> f a)
and then
        let a* = h v; b = e in f a
and then
        f (h v)

All this should happen in one sweep.

\begin{code}
knownCon :: SimplEnv -> OutExpr -> AltCon
	 -> [OutExpr]	 	-- Args *including* the universal args
         -> InId -> [InAlt] -> SimplCont
         -> SimplM (SimplEnv, OutExpr)

knownCon env scrut con args bndr alts cont
  = do  { tick (KnownBranch bndr)
        ; case findAlt con alts of
	    Nothing  -> missingAlt env bndr alts cont
	    Just alt -> knownAlt env scrut args bndr alt cont
	}

-------------------
knownAlt :: SimplEnv -> OutExpr -> [OutExpr]
         -> InId -> InAlt -> SimplCont
         -> SimplM (SimplEnv, OutExpr)

knownAlt env scrut the_args bndr (DataAlt dc, bs, rhs) cont
  = do  { let n_drop_tys = length (dataConUnivTyVars dc)
        ; env' <- bind_args env bs (drop n_drop_tys the_args)
        ; let
                -- It's useful to bind bndr to scrut, rather than to a fresh
                -- binding      x = Con arg1 .. argn
                -- because very often the scrut is a variable, so we avoid
                -- creating, and then subsequently eliminating, a let-binding
                -- BUT, if scrut is a not a variable, we must be careful
                -- about duplicating the arg redexes; in that case, make
                -- a new con-app from the args
                bndr_rhs  = case scrut of
                                Var _ -> scrut
                                _     -> con_app
                con_app = mkConApp dc (take n_drop_tys the_args ++ con_args)
                con_args = [substExpr env' (varToCoreExpr b) | b <- bs]
                                -- args are aready OutExprs, but bs are InIds

        ; env'' <- simplNonRecX env' bndr bndr_rhs
        ; simplExprF env'' rhs cont }
  where
    zap_occ = zapCasePatIdOcc bndr    -- bndr is an InId

                  -- Ugh!
    bind_args env' [] _  = return env'

    bind_args env' (b:bs') (Type ty : args)
      = ASSERT( isTyVar b )
        bind_args (extendTvSubst env' b ty) bs' args

    bind_args env' (b:bs') (arg : args)
      = ASSERT( isId b )
        do { let b' = zap_occ b
             -- Note that the binder might be "dead", because it doesn't
             -- occur in the RHS; and simplNonRecX may therefore discard
             -- it via postInlineUnconditionally.
             -- Nevertheless we must keep it if the case-binder is alive,
             -- because it may be used in the con_app.  See Note [zapOccInfo]
           ; env'' <- simplNonRecX env' b' arg
           ; bind_args env'' bs' args }

    bind_args _ _ _ =
      pprPanic "bind_args" $ ppr dc $$ ppr bs $$ ppr the_args $$
                             text "scrut:" <+> ppr scrut

knownAlt env scrut _ bndr (_, bs, rhs) cont
  = ASSERT( null bs )	  -- Works for LitAlt and DEFAULT
    do  { env' <- simplNonRecX env bndr scrut
        ; simplExprF env' rhs cont }


-------------------
missingAlt :: SimplEnv -> Id -> [InAlt] -> SimplCont -> SimplM (SimplEnv, OutExpr)
   		-- This isn't strictly an error, although it is unusual. 
		-- It's possible that the simplifer might "see" that 
		-- an inner case has no accessible alternatives before 
		-- it "sees" that the entire branch of an outer case is 
		-- inaccessible.  So we simply put an error case here instead.
missingAlt env case_bndr alts cont
  = WARN( True, ptext (sLit "missingAlt") <+> ppr case_bndr )
    return (env, mkImpossibleExpr res_ty)
  where
    res_ty = contResultType env (substTy env (coreAltsType alts)) cont
\end{code}


%************************************************************************
%*                                                                      *
\subsection{Duplicating continuations}
%*                                                                      *
%************************************************************************

\begin{code}
prepareCaseCont :: SimplEnv
                -> [InAlt] -> SimplCont
                -> SimplM (SimplEnv, SimplCont,SimplCont)
                        -- Return a duplicatable continuation, a non-duplicable part
                        -- plus some extra bindings (that scope over the entire
                        -- continunation)

        -- No need to make it duplicatable if there's only one alternative
prepareCaseCont env [_] cont = return (env, cont, mkBoringStop)
prepareCaseCont env _   cont = mkDupableCont env cont
\end{code}

\begin{code}
mkDupableCont :: SimplEnv -> SimplCont
              -> SimplM (SimplEnv, SimplCont, SimplCont)

mkDupableCont env cont
  | contIsDupable cont
  = return (env, cont, mkBoringStop)

mkDupableCont _   (Stop {}) = panic "mkDupableCont"     -- Handled by previous eqn

mkDupableCont env (CoerceIt ty cont)
  = do  { (env', dup, nodup) <- mkDupableCont env cont
        ; return (env', CoerceIt ty dup, nodup) }

mkDupableCont env cont@(StrictBind {})
  =  return (env, mkBoringStop, cont)
        -- See Note [Duplicating StrictBind]

mkDupableCont env (StrictArg fun cci ai cont)
        -- See Note [Duplicating StrictArg]
  = do { (env', dup, nodup) <- mkDupableCont env cont
       ; (env'', fun') <- mk_dupable_call env' fun
       ; return (env'', StrictArg fun' cci ai dup, nodup) }
  where
    mk_dupable_call env (Var v)       = return (env, Var v)
    mk_dupable_call env (App fun arg) = do { (env', fun') <- mk_dupable_call env fun
                                           ; (env'', arg') <- makeTrivial env' arg
                                           ; return (env'', fun' `App` arg') }
    mk_dupable_call _ other = pprPanic "mk_dupable_call" (ppr other)
	-- The invariant of StrictArg is that the first arg is always an App chain

mkDupableCont env (ApplyTo _ arg se cont)
  =     -- e.g.         [...hole...] (...arg...)
        --      ==>
        --              let a = ...arg...
        --              in [...hole...] a
    do  { (env', dup_cont, nodup_cont) <- mkDupableCont env cont
        ; arg' <- simplExpr (se `setInScope` env') arg
        ; (env'', arg'') <- makeTrivial env' arg'
        ; let app_cont = ApplyTo OkToDup arg'' (zapSubstEnv env'') dup_cont
        ; return (env'', app_cont, nodup_cont) }

mkDupableCont env cont@(Select _ case_bndr [(_, bs, _rhs)] _ _)
--  See Note [Single-alternative case]
--  | not (exprIsDupable rhs && contIsDupable case_cont)
--  | not (isDeadBinder case_bndr)
  | all isDeadBinder bs  -- InIds
    && not (isUnLiftedType (idType case_bndr))
    -- Note [Single-alternative-unlifted]
  = return (env, mkBoringStop, cont)

mkDupableCont env (Select _ case_bndr alts se cont)
  =     -- e.g.         (case [...hole...] of { pi -> ei })
        --      ===>
        --              let ji = \xij -> ei
        --              in case [...hole...] of { pi -> ji xij }
    do  { tick (CaseOfCase case_bndr)
        ; (env', dup_cont, nodup_cont) <- mkDupableCont env cont
                -- NB: call mkDupableCont here, *not* prepareCaseCont
                -- We must make a duplicable continuation, whereas prepareCaseCont
                -- doesn't when there is a single case branch

        ; let alt_env = se `setInScope` env'
        ; (alt_env', case_bndr') <- simplBinder alt_env case_bndr
        ; alts' <- mapM (simplAlt alt_env' [] case_bndr' dup_cont) alts
        -- Safe to say that there are no handled-cons for the DEFAULT case
                -- NB: simplBinder does not zap deadness occ-info, so
                -- a dead case_bndr' will still advertise its deadness
                -- This is really important because in
                --      case e of b { (# p,q #) -> ... }
                -- b is always dead, and indeed we are not allowed to bind b to (# p,q #),
                -- which might happen if e was an explicit unboxed pair and b wasn't marked dead.
                -- In the new alts we build, we have the new case binder, so it must retain
                -- its deadness.
        -- NB: we don't use alt_env further; it has the substEnv for
        --     the alternatives, and we don't want that

        ; (env'', alts'') <- mkDupableAlts env' case_bndr' alts'
        ; return (env'',  -- Note [Duplicated env]
                  Select OkToDup case_bndr' alts'' (zapSubstEnv env'') mkBoringStop,
                  nodup_cont) }


mkDupableAlts :: SimplEnv -> OutId -> [InAlt]
              -> SimplM (SimplEnv, [InAlt])
-- Absorbs the continuation into the new alternatives

mkDupableAlts env case_bndr' the_alts
  = go env the_alts
  where
    go env0 [] = return (env0, [])
    go env0 (alt:alts)
        = do { (env1, alt') <- mkDupableAlt env0 case_bndr' alt
             ; (env2, alts') <- go env1 alts
             ; return (env2, alt' : alts' ) }

mkDupableAlt :: SimplEnv -> OutId -> (AltCon, [CoreBndr], CoreExpr)
              -> SimplM (SimplEnv, (AltCon, [CoreBndr], CoreExpr))
mkDupableAlt env case_bndr' (con, bndrs', rhs')
  | exprIsDupable rhs'  -- Note [Small alternative rhs]
  = return (env, (con, bndrs', rhs'))
  | otherwise
  = do  { let rhs_ty'     = exprType rhs'
              used_bndrs' = filter abstract_over (case_bndr' : bndrs')
              abstract_over bndr
                  | isTyVar bndr = True -- Abstract over all type variables just in case
                  | otherwise    = not (isDeadBinder bndr)
                        -- The deadness info on the new Ids is preserved by simplBinders

        ; (final_bndrs', final_args)    -- Note [Join point abstraction]
                <- if (any isId used_bndrs')
                   then return (used_bndrs', varsToCoreExprs used_bndrs')
                    else do { rw_id <- newId (fsLit "w") realWorldStatePrimTy
                            ; return ([rw_id], [Var realWorldPrimId]) }

        ; join_bndr <- newId (fsLit "$j") (mkPiTypes final_bndrs' rhs_ty')
                -- Note [Funky mkPiTypes]

        ; let   -- We make the lambdas into one-shot-lambdas.  The
                -- join point is sure to be applied at most once, and doing so
                -- prevents the body of the join point being floated out by
                -- the full laziness pass
                really_final_bndrs     = map one_shot final_bndrs'
                one_shot v | isId v    = setOneShotLambda v
                           | otherwise = v
                join_rhs  = mkLams really_final_bndrs rhs'
                join_call = mkApps (Var join_bndr) final_args

        ; return (addPolyBind NotTopLevel env (NonRec join_bndr join_rhs), (con, bndrs', join_call)) }
                -- See Note [Duplicated env]
\end{code}

Note [Duplicated env]
~~~~~~~~~~~~~~~~~~~~~
Some of the alternatives are simplified, but have not been turned into a join point
So they *must* have an zapped subst-env.  So we can't use completeNonRecX to
bind the join point, because it might to do PostInlineUnconditionally, and
we'd lose that when zapping the subst-env.  We could have a per-alt subst-env,
but zapping it (as we do in mkDupableCont, the Select case) is safe, and
at worst delays the join-point inlining.

Note [Small alternative rhs]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
It is worth checking for a small RHS because otherwise we
get extra let bindings that may cause an extra iteration of the simplifier to
inline back in place.  Quite often the rhs is just a variable or constructor.
The Ord instance of Maybe in PrelMaybe.lhs, for example, took several extra
iterations because the version with the let bindings looked big, and so wasn't
inlined, but after the join points had been inlined it looked smaller, and so
was inlined.

NB: we have to check the size of rhs', not rhs.
Duplicating a small InAlt might invalidate occurrence information
However, if it *is* dupable, we return the *un* simplified alternative,
because otherwise we'd need to pair it up with an empty subst-env....
but we only have one env shared between all the alts.
(Remember we must zap the subst-env before re-simplifying something).
Rather than do this we simply agree to re-simplify the original (small) thing later.

Note [Funky mkPiTypes]
~~~~~~~~~~~~~~~~~~~~~~
Notice the funky mkPiTypes.  If the contructor has existentials
it's possible that the join point will be abstracted over
type varaibles as well as term variables.
 Example:  Suppose we have
        data T = forall t.  C [t]
 Then faced with
        case (case e of ...) of
            C t xs::[t] -> rhs
 We get the join point
        let j :: forall t. [t] -> ...
            j = /\t \xs::[t] -> rhs
        in
        case (case e of ...) of
            C t xs::[t] -> j t xs

Note [Join point abstaction]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
If we try to lift a primitive-typed something out
for let-binding-purposes, we will *caseify* it (!),
with potentially-disastrous strictness results.  So
instead we turn it into a function: \v -> e
where v::State# RealWorld#.  The value passed to this function
is realworld#, which generates (almost) no code.

There's a slight infelicity here: we pass the overall
case_bndr to all the join points if it's used in *any* RHS,
because we don't know its usage in each RHS separately

We used to say "&& isUnLiftedType rhs_ty'" here, but now
we make the join point into a function whenever used_bndrs'
is empty.  This makes the join-point more CPR friendly.
Consider:       let j = if .. then I# 3 else I# 4
                in case .. of { A -> j; B -> j; C -> ... }

Now CPR doesn't w/w j because it's a thunk, so
that means that the enclosing function can't w/w either,
which is a lose.  Here's the example that happened in practice:
        kgmod :: Int -> Int -> Int
        kgmod x y = if x > 0 && y < 0 || x < 0 && y > 0
                    then 78
                    else 5

I have seen a case alternative like this:
        True -> \v -> ...
It's a bit silly to add the realWorld dummy arg in this case, making
        $j = \s v -> ...
           True -> $j s
(the \v alone is enough to make CPR happy) but I think it's rare

Note [Duplicating StrictArg]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The original plan had (where E is a big argument)
e.g.    f E [..hole..]
        ==>     let $j = \a -> f E a
                in $j [..hole..]

But this is terrible! Here's an example:
        && E (case x of { T -> F; F -> T })
Now, && is strict so we end up simplifying the case with
an ArgOf continuation.  If we let-bind it, we get
        let $j = \v -> && E v
        in simplExpr (case x of { T -> F; F -> T })
                     (ArgOf (\r -> $j r)
And after simplifying more we get
        let $j = \v -> && E v
        in case x of { T -> $j F; F -> $j T }
Which is a Very Bad Thing

What we do now is this
	f E [..hole..]
 	==> 	let a = E
		in f a [..hole..]
Now if the thing in the hole is a case expression (which is when
we'll call mkDupableCont), we'll push the function call into the
branches, which is what we want.  Now RULES for f may fire, and
call-pattern specialisation.  Here's an example from Trac #3116
     go (n+1) (case l of
           	 1  -> bs'
           	 _  -> Chunk p fpc (o+1) (l-1) bs')
If we can push the call for 'go' inside the case, we get
call-pattern specialisation for 'go', which is *crucial* for 
this program.

Here is the (&&) example: 
        && E (case x of { T -> F; F -> T })
  ==>   let a = E in 
        case x of { T -> && a F; F -> && a T }
Much better!

Notice that 
  * Arguments to f *after* the strict one are handled by 
    the ApplyTo case of mkDupableCont.  Eg
	f [..hole..] E

  * We can only do the let-binding of E because the function
    part of a StrictArg continuation is an explicit syntax
    tree.  In earlier versions we represented it as a function
    (CoreExpr -> CoreEpxr) which we couldn't take apart.

Do *not* duplicate StrictBind and StritArg continuations.  We gain
nothing by propagating them into the expressions, and we do lose a
lot.  

The desire not to duplicate is the entire reason that
mkDupableCont returns a pair of continuations.

Note [Duplicating StrictBind]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Unlike StrictArg, there doesn't seem anything to gain from
duplicating a StrictBind continuation, so we don't.

The desire not to duplicate is the entire reason that
mkDupableCont returns a pair of continuations.


Note [Single-alternative cases]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
This case is just like the ArgOf case.  Here's an example:
        data T a = MkT !a
        ...(MkT (abs x))...
Then we get
        case (case x of I# x' ->
              case x' <# 0# of
                True  -> I# (negate# x')
                False -> I# x') of y {
          DEFAULT -> MkT y
Because the (case x) has only one alternative, we'll transform to
        case x of I# x' ->
        case (case x' <# 0# of
                True  -> I# (negate# x')
                False -> I# x') of y {
          DEFAULT -> MkT y
But now we do *NOT* want to make a join point etc, giving
        case x of I# x' ->
        let $j = \y -> MkT y
        in case x' <# 0# of
                True  -> $j (I# (negate# x'))
                False -> $j (I# x')
In this case the $j will inline again, but suppose there was a big
strict computation enclosing the orginal call to MkT.  Then, it won't
"see" the MkT any more, because it's big and won't get duplicated.
And, what is worse, nothing was gained by the case-of-case transform.

When should use this case of mkDupableCont?
However, matching on *any* single-alternative case is a *disaster*;
  e.g.  case (case ....) of (a,b) -> (# a,b #)
  We must push the outer case into the inner one!
Other choices:

   * Match [(DEFAULT,_,_)], but in the common case of Int,
     the alternative-filling-in code turned the outer case into
                case (...) of y { I# _ -> MkT y }

   * Match on single alternative plus (not (isDeadBinder case_bndr))
     Rationale: pushing the case inwards won't eliminate the construction.
     But there's a risk of
                case (...) of y { (a,b) -> let z=(a,b) in ... }
     Now y looks dead, but it'll come alive again.  Still, this
     seems like the best option at the moment.

   * Match on single alternative plus (all (isDeadBinder bndrs))
     Rationale: this is essentially  seq.

   * Match when the rhs is *not* duplicable, and hence would lead to a
     join point.  This catches the disaster-case above.  We can test
     the *un-simplified* rhs, which is fine.  It might get bigger or
     smaller after simplification; if it gets smaller, this case might
     fire next time round.  NB also that we must test contIsDupable
     case_cont *btoo, because case_cont might be big!

     HOWEVER: I found that this version doesn't work well, because
     we can get         let x = case (...) of { small } in ...case x...
     When x is inlined into its full context, we find that it was a bad
     idea to have pushed the outer case inside the (...) case.

Note [Single-alternative-unlifted]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Here's another single-alternative where we really want to do case-of-case:

data Mk1 = Mk1 Int#
data Mk1 = Mk2 Int#

M1.f =
    \r [x_s74 y_s6X]
        case
            case y_s6X of tpl_s7m {
              M1.Mk1 ipv_s70 -> ipv_s70;
              M1.Mk2 ipv_s72 -> ipv_s72;
            }
        of
        wild_s7c
        { __DEFAULT ->
              case
                  case x_s74 of tpl_s7n {
                    M1.Mk1 ipv_s77 -> ipv_s77;
                    M1.Mk2 ipv_s79 -> ipv_s79;
                  }
              of
              wild1_s7b
              { __DEFAULT -> ==# [wild1_s7b wild_s7c];
              };
        };

So the outer case is doing *nothing at all*, other than serving as a
join-point.  In this case we really want to do case-of-case and decide
whether to use a real join point or just duplicate the continuation.

Hence: check whether the case binder's type is unlifted, because then
the outer case is *not* a seq.
