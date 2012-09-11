%
% (c) The University of Glasgow 2006
%

\begin{code}
module Unify ( 
	-- Matching of types: 
	--	the "tc" prefix indicates that matching always
	--	respects newtypes (rather than looking through them)
	tcMatchTy, tcMatchTys, tcMatchTyX, 
	ruleMatchTyX, tcMatchPreds, MatchEnv(..),
	
	dataConCannotMatch,

        -- GADT type refinement
	Refinement, emptyRefinement, isEmptyRefinement, 
	matchRefine, refineType, refinePred, refineResType,

        -- side-effect free unification
        tcUnifyTys, BindFlag(..)

   ) where

#include "HsVersions.h"

import Var
import VarEnv
import VarSet
import Type
import Coercion
import TyCon
import DataCon
import TypeRep
import Outputable
import ErrUtils
import Util
import Maybes
import UniqFM
import FastString
\end{code}


%************************************************************************
%*									*
		Matching
%*									*
%************************************************************************


Matching is much tricker than you might think.

1. The substitution we generate binds the *template type variables*
   which are given to us explicitly.

2. We want to match in the presence of foralls; 
	e.g 	(forall a. t1) ~ (forall b. t2)

   That is what the RnEnv2 is for; it does the alpha-renaming
   that makes it as if a and b were the same variable.
   Initialising the RnEnv2, so that it can generate a fresh
   binder when necessary, entails knowing the free variables of
   both types.

3. We must be careful not to bind a template type variable to a
   locally bound variable.  E.g.
	(forall a. x) ~ (forall b. b)
   where x is the template type variable.  Then we do not want to
   bind x to a/b!  This is a kind of occurs check.
   The necessary locals accumulate in the RnEnv2.


\begin{code}
data MatchEnv
  = ME	{ me_tmpls :: VarSet	-- Template tyvars
 	, me_env   :: RnEnv2	-- Renaming envt for nested foralls
	}			--   In-scope set includes template tyvars

tcMatchTy :: TyVarSet		-- Template tyvars
	  -> Type		-- Template
	  -> Type		-- Target
	  -> Maybe TvSubst	-- One-shot; in principle the template
				-- variables could be free in the target

tcMatchTy tmpls ty1 ty2
  = case match menv emptyTvSubstEnv ty1 ty2 of
	Just subst_env -> Just (TvSubst in_scope subst_env)
	Nothing	       -> Nothing
  where
    menv     = ME { me_tmpls = tmpls, me_env = mkRnEnv2 in_scope }
    in_scope = mkInScopeSet (tmpls `unionVarSet` tyVarsOfType ty2)
	-- We're assuming that all the interesting 
	-- tyvars in tys1 are in tmpls

tcMatchTys :: TyVarSet		-- Template tyvars
	   -> [Type]		-- Template
	   -> [Type]		-- Target
	   -> Maybe TvSubst	-- One-shot; in principle the template
				-- variables could be free in the target

tcMatchTys tmpls tys1 tys2
  = case match_tys menv emptyTvSubstEnv tys1 tys2 of
	Just subst_env -> Just (TvSubst in_scope subst_env)
	Nothing	       -> Nothing
  where
    menv     = ME { me_tmpls = tmpls, me_env = mkRnEnv2 in_scope }
    in_scope = mkInScopeSet (tmpls `unionVarSet` tyVarsOfTypes tys2)
	-- We're assuming that all the interesting 
	-- tyvars in tys1 are in tmpls

-- This is similar, but extends a substitution
tcMatchTyX :: TyVarSet 		-- Template tyvars
	   -> TvSubst		-- Substitution to extend
	   -> Type		-- Template
	   -> Type		-- Target
	   -> Maybe TvSubst
tcMatchTyX tmpls (TvSubst in_scope subst_env) ty1 ty2
  = case match menv subst_env ty1 ty2 of
	Just subst_env -> Just (TvSubst in_scope subst_env)
	Nothing	       -> Nothing
  where
    menv = ME {me_tmpls = tmpls, me_env = mkRnEnv2 in_scope}

tcMatchPreds
	:: [TyVar]			-- Bind these
	-> [PredType] -> [PredType]
   	-> Maybe TvSubstEnv
tcMatchPreds tmpls ps1 ps2
  = match_list (match_pred menv) emptyTvSubstEnv ps1 ps2
  where
    menv = ME { me_tmpls = mkVarSet tmpls, me_env = mkRnEnv2 in_scope_tyvars }
    in_scope_tyvars = mkInScopeSet (tyVarsOfTheta ps1 `unionVarSet` tyVarsOfTheta ps2)

-- This one is called from the expression matcher, which already has a MatchEnv in hand
ruleMatchTyX :: MatchEnv 
	 -> TvSubstEnv		-- Substitution to extend
	 -> Type		-- Template
	 -> Type		-- Target
	 -> Maybe TvSubstEnv

ruleMatchTyX menv subst ty1 ty2 = match menv subst ty1 ty2	-- Rename for export
\end{code}

Now the internals of matching

\begin{code}
match :: MatchEnv	-- For the most part this is pushed downwards
      -> TvSubstEnv 	-- Substitution so far:
			--   Domain is subset of template tyvars
			--   Free vars of range is subset of 
			--	in-scope set of the RnEnv2
      -> Type -> Type	-- Template and target respectively
      -> Maybe TvSubstEnv
-- This matcher works on core types; that is, it ignores PredTypes
-- Watch out if newtypes become transparent agin!
-- 	this matcher must respect newtypes

match menv subst ty1 ty2 | Just ty1' <- coreView ty1 = match menv subst ty1' ty2
			 | Just ty2' <- coreView ty2 = match menv subst ty1 ty2'

match menv subst (TyVarTy tv1) ty2
  | Just ty1' <- lookupVarEnv subst tv1'	-- tv1' is already bound
  = if tcEqTypeX (nukeRnEnvL rn_env) ty1' ty2
	-- ty1 has no locally-bound variables, hence nukeRnEnvL
	-- Note tcEqType...we are doing source-type matching here
    then Just subst
    else Nothing	-- ty2 doesn't match

  | tv1' `elemVarSet` me_tmpls menv
  = if any (inRnEnvR rn_env) (varSetElems (tyVarsOfType ty2))
    then Nothing	-- Occurs check
    else do { subst1 <- match_kind menv subst tv1 ty2
			-- Note [Matching kinds]
	    ; return (extendVarEnv subst1 tv1' ty2) }

   | otherwise	-- tv1 is not a template tyvar
   = case ty2 of
	TyVarTy tv2 | tv1' == rnOccR rn_env tv2 -> Just subst
	_                                       -> Nothing
  where
    rn_env = me_env menv
    tv1' = rnOccL rn_env tv1

match menv subst (ForAllTy tv1 ty1) (ForAllTy tv2 ty2) 
  = match menv' subst ty1 ty2
  where		-- Use the magic of rnBndr2 to go under the binders
    menv' = menv { me_env = rnBndr2 (me_env menv) tv1 tv2 }

match menv subst (PredTy p1) (PredTy p2) 
  = match_pred menv subst p1 p2
match menv subst (TyConApp tc1 tys1) (TyConApp tc2 tys2) 
  | tc1 == tc2 = match_tys menv subst tys1 tys2
match menv subst (FunTy ty1a ty1b) (FunTy ty2a ty2b) 
  = do { subst' <- match menv subst ty1a ty2a
       ; match menv subst' ty1b ty2b }
match menv subst (AppTy ty1a ty1b) ty2
  | Just (ty2a, ty2b) <- repSplitAppTy_maybe ty2
	-- 'repSplit' used because the tcView stuff is done above
  = do { subst' <- match menv subst ty1a ty2a
       ; match menv subst' ty1b ty2b }

match _ _ _ _
  = Nothing

--------------
match_kind :: MatchEnv -> TvSubstEnv -> TyVar -> Type -> Maybe TvSubstEnv
-- Match the kind of the template tyvar with the kind of Type
-- Note [Matching kinds]
match_kind menv subst tv ty
  | isCoVar tv = do { let (ty1,ty2) = splitCoercionKind (tyVarKind tv)
			  (ty3,ty4) = coercionKind ty
		    ; subst1 <- match menv subst ty1 ty3
		    ; match menv subst1 ty2 ty4 }
  | otherwise  = if typeKind ty `isSubKind` tyVarKind tv
		 then Just subst
		 else Nothing

-- Note [Matching kinds]
-- ~~~~~~~~~~~~~~~~~~~~~
-- For ordinary type variables, we don't want (m a) to match (n b) 
-- if say (a::*) and (b::*->*).  This is just a yes/no issue. 
--
-- For coercion kinds matters are more complicated.  If we have a 
-- coercion template variable co::a~[b], where a,b are presumably also
-- template type variables, then we must match co's kind against the 
-- kind of the actual argument, so as to give bindings to a,b.  
--
-- In fact I have no example in mind that *requires* this kind-matching
-- to instantiate template type variables, but it seems like the right
-- thing to do.  C.f. Note [Matching variable types] in Rules.lhs

--------------
match_tys :: MatchEnv -> TvSubstEnv -> [Type] -> [Type] -> Maybe TvSubstEnv
match_tys menv subst tys1 tys2 = match_list (match menv) subst tys1 tys2

--------------
match_list :: (TvSubstEnv -> a -> a -> Maybe TvSubstEnv)
	   -> TvSubstEnv -> [a] -> [a] -> Maybe TvSubstEnv
match_list _  subst []         []         = Just subst
match_list fn subst (ty1:tys1) (ty2:tys2) = do	{ subst' <- fn subst ty1 ty2
						; match_list fn subst' tys1 tys2 }
match_list _  _     _          _          = Nothing

--------------
match_pred :: MatchEnv -> TvSubstEnv -> PredType -> PredType -> Maybe TvSubstEnv
match_pred menv subst (ClassP c1 tys1) (ClassP c2 tys2)
  | c1 == c2 = match_tys menv subst tys1 tys2
match_pred menv subst (IParam n1 t1) (IParam n2 t2)
  | n1 == n2 = match menv subst t1 t2
match_pred _    _     _ _ = Nothing
\end{code}


%************************************************************************
%*									*
		GADTs
%*									*
%************************************************************************

Note [Pruning dead case alternatives]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider	data T a where
		   T1 :: T Int
		   T2 :: T a

		newtype X = MkX Int
		newtype Y = MkY Char

		type family F a
		type instance F Bool = Int

Now consider	case x of { T1 -> e1; T2 -> e2 }

The question before the house is this: if I know something about the type
of x, can I prune away the T1 alternative?

Suppose x::T Char.  It's impossible to construct a (T Char) using T1, 
	Answer = YES (clearly)

Suppose x::T (F a), where 'a' is in scope.  Then 'a' might be instantiated
to 'Bool', in which case x::T Int, so
	ANSWER = NO (clearly)

Suppose x::T X.  Then *in Haskell* it's impossible to construct a (non-bottom) 
value of type (T X) using T1.  But *in FC* it's quite possible.  The newtype
gives a coercion
	CoX :: X ~ Int
So (T CoX) :: T X ~ T Int; hence (T1 `cast` sym (T CoX)) is a non-bottom value
of type (T X) constructed with T1.  Hence
	ANSWER = NO (surprisingly)

Furthermore, this can even happen; see Trac #1251.  GHC's newtype-deriving
mechanism uses a cast, just as above, to move from one dictionary to another,
in effect giving the programmer access to CoX.

Finally, suppose x::T Y.  Then *even in FC* we can't construct a
non-bottom value of type (T Y) using T1.  That's because we can get
from Y to Char, but not to Int.


Here's a related question.  	data Eq a b where EQ :: Eq a a
Consider
	case x of { EQ -> ... }

Suppose x::Eq Int Char.  Is the alternative dead?  Clearly yes.

What about x::Eq Int a, in a context where we have evidence that a~Char.
Then again the alternative is dead.   


			Summary

We are really doing a test for unsatisfiability of the type
constraints implied by the match. And that is clearly, in general, a
hard thing to do.  

However, since we are simply dropping dead code, a conservative test
suffices.  There is a continuum of tests, ranging from easy to hard, that
drop more and more dead code.

For now we implement a very simple test: type variables match
anything, type functions (incl newtypes) match anything, and only
distinct data types fail to match.  We can elaborate later.

\begin{code}
dataConCannotMatch :: [Type] -> DataCon -> Bool
-- Returns True iff the data con *definitely cannot* match a 
--		    scrutinee of type (T tys)
--		    where T is the type constructor for the data con
--
dataConCannotMatch tys con
  | null eq_spec      = False	-- Common
  | all isTyVarTy tys = False	-- Also common
  | otherwise
  = cant_match_s (map (substTyVar subst . fst) eq_spec)
	         (map snd eq_spec)
  where
    dc_tvs  = dataConUnivTyVars con
    eq_spec = dataConEqSpec con
    subst   = zipTopTvSubst dc_tvs tys

    cant_match_s :: [Type] -> [Type] -> Bool
    cant_match_s tys1 tys2 = ASSERT( equalLength tys1 tys2 )
			     or (zipWith cant_match tys1 tys2)

    cant_match :: Type -> Type -> Bool
    cant_match t1 t2
	| Just t1' <- coreView t1 = cant_match t1' t2
	| Just t2' <- coreView t2 = cant_match t1 t2'

    cant_match (FunTy a1 r1) (FunTy a2 r2)
	= cant_match a1 a2 || cant_match r1 r2

    cant_match (TyConApp tc1 tys1) (TyConApp tc2 tys2)
	| isDataTyCon tc1 && isDataTyCon tc2
	= tc1 /= tc2 || cant_match_s tys1 tys2

    cant_match (FunTy {}) (TyConApp tc _) = isDataTyCon tc
    cant_match (TyConApp tc _) (FunTy {}) = isDataTyCon tc
	-- tc can't be FunTyCon by invariant

    cant_match (AppTy f1 a1) ty2
	| Just (f2, a2) <- repSplitAppTy_maybe ty2
	= cant_match f1 f2 || cant_match a1 a2
    cant_match ty1 (AppTy f2 a2)
	| Just (f1, a1) <- repSplitAppTy_maybe ty1
	= cant_match f1 f2 || cant_match a1 a2

    cant_match _ _ = False      -- Safe!

-- Things we could add;
--	foralls
--	look through newtypes
--	take account of tyvar bindings (EQ example above)
\end{code}


%************************************************************************
%*									*
		What a refinement is
%*									*
%************************************************************************

\begin{code}
data Refinement = Reft InScopeSet InternalReft 

type InternalReft = TyVarEnv (Coercion, Type)
-- INVARIANT:   a->(co,ty)   then   co :: (a~ty)
-- Not necessarily idemopotent

instance Outputable Refinement where
  ppr (Reft _in_scope env)
    = ptext (sLit "Refinement") <+>
        braces (ppr env)

emptyRefinement :: Refinement
emptyRefinement = (Reft emptyInScopeSet emptyVarEnv)

isEmptyRefinement :: Refinement -> Bool
isEmptyRefinement (Reft _ env) = isEmptyVarEnv env

refineType :: Refinement -> Type -> Maybe (Coercion, Type)
-- Apply the refinement to the type.
-- If (refineType r ty) = (co, ty')
-- Then co :: ty~ty'
-- Nothing => the refinement does nothing to this type
refineType (Reft in_scope env) ty
  | not (isEmptyVarEnv env),		-- Common case
    any (`elemVarEnv` env) (varSetElems (tyVarsOfType ty))
  = Just (substTy co_subst ty, substTy tv_subst ty)
  | otherwise
  = Nothing	-- The type doesn't mention any refined type variables
  where
    tv_subst = mkTvSubst in_scope (mapVarEnv snd env)
    co_subst = mkTvSubst in_scope (mapVarEnv fst env)
 
refinePred :: Refinement -> PredType -> Maybe (Coercion, PredType)
refinePred (Reft in_scope env) pred
  | not (isEmptyVarEnv env),		-- Common case
    any (`elemVarEnv` env) (varSetElems (tyVarsOfPred pred))
  = Just (mkPredTy (substPred co_subst pred), substPred tv_subst pred)
  | otherwise
  = Nothing	-- The type doesn't mention any refined type variables
  where
    tv_subst = mkTvSubst in_scope (mapVarEnv snd env)
    co_subst = mkTvSubst in_scope (mapVarEnv fst env)
 
refineResType :: Refinement -> Type -> Maybe (Coercion, Type)
-- Like refineType, but returns the 'sym' coercion
-- If (refineResType r ty) = (co, ty')
-- Then co :: ty'~ty
refineResType reft ty
  = case refineType reft ty of
      Just (co, ty1) -> Just (mkSymCoercion co, ty1)
      Nothing	     -> Nothing
\end{code}


%************************************************************************
%*									*
		Simple generation of a type refinement
%*									*
%************************************************************************

\begin{code}
matchRefine :: [TyVar] -> [Coercion] -> Refinement
\end{code}

Given a list of coercions, where for each coercion c::(ty1~ty2), the type ty2
is a specialisation of ty1, produce a type refinement that maps the variables
of ty1 to the corresponding sub-terms of ty2 using appropriate coercions; eg,

  matchRefine (co :: [(a, b)] ~ [(c, Maybe d)])
    = { right (left (right co)) :: a ~ c
      , right (right co)        :: b ~ Maybe d
      }

Precondition: The rhs types must indeed be a specialisation of the lhs types;
  i.e., some free variables of the lhs are replaced with either distinct free 
  variables or proper type terms to obtain the rhs.  (We don't perform full
  unification or type matching here!)

NB: matchRefine does *not* expand the type synonyms.

\begin{code}
matchRefine in_scope_tvs cos 
  = Reft in_scope (foldr plusVarEnv emptyVarEnv (map refineOne cos))
  where
    in_scope = mkInScopeSet (mkVarSet in_scope_tvs)
	-- NB: in_scope_tvs include both coercion variables
	--     *and* the tyvars in their kinds

    refineOne co = refine co ty1 ty2
      where
        (ty1, ty2) = coercionKind co

    refine co (TyVarTy tv) ty                     = unitVarEnv tv (co, ty)
    refine co (TyConApp _ tys) (TyConApp _ tys')  = refineArgs co tys tys'
    refine _  (PredTy _) (PredTy _)               = 
      error "Unify.matchRefine: PredTy"
    refine co (FunTy arg res) (FunTy arg' res')   =
      refine (mkRightCoercion (mkLeftCoercion co)) arg arg' 
      `plusVarEnv` 
      refine (mkRightCoercion co) res res'
    refine co (AppTy fun arg) (AppTy fun' arg')   = 
      refine (mkLeftCoercion co) fun fun' 
      `plusVarEnv`
      refine (mkRightCoercion co) arg arg'
    refine co (ForAllTy tv ty) (ForAllTy _tv ty') =
      refine (mkForAllCoercion tv co) ty ty' `delVarEnv` tv
    refine _ _ _ = error "RcGadt.matchRefine: mismatch"

    refineArgs :: Coercion -> [Type] -> [Type] -> InternalReft
    refineArgs co tys tys' = 
      fst $ foldr refineArg (emptyVarEnv, id) (zip tys tys')
      where
        refineArg (ty, ty') (reft, coWrapper) 
          = (refine (mkRightCoercion (coWrapper co)) ty ty' `plusVarEnv` reft, 
             mkLeftCoercion . coWrapper)
\end{code}


%************************************************************************
%*									*
		Unification
%*									*
%************************************************************************

\begin{code}
tcUnifyTys :: (TyVar -> BindFlag)
	   -> [Type] -> [Type]
	   -> Maybe TvSubst	-- A regular one-shot substitution
-- The two types may have common type variables, and indeed do so in the
-- second call to tcUnifyTys in FunDeps.checkClsFD
--
tcUnifyTys bind_fn tys1 tys2
  = maybeErrToMaybe $ initUM bind_fn $
    do { subst <- unifyList emptyTvSubstEnv tys1 tys2

	-- Find the fixed point of the resulting non-idempotent substitution
	; let in_scope = mkInScopeSet (tvs1 `unionVarSet` tvs2)
	      tv_env   = fixTvSubstEnv in_scope subst

	; return (mkTvSubst in_scope tv_env) }
  where
    tvs1 = tyVarsOfTypes tys1
    tvs2 = tyVarsOfTypes tys2

----------------------------
-- XXX Can we do this more nicely, by exploiting laziness?
-- Or avoid needing it in the first place?
fixTvSubstEnv :: InScopeSet -> TvSubstEnv -> TvSubstEnv
fixTvSubstEnv in_scope env = f env
  where
    f e = let e' = mapUFM (substTy (mkTvSubst in_scope e)) e
          in if and $ eltsUFM $ intersectUFM_C tcEqType e e'
             then e
             else f e'

\end{code}


%************************************************************************
%*									*
		The workhorse
%*									*
%************************************************************************

\begin{code}
unify :: TvSubstEnv	-- An existing substitution to extend
      -> Type -> Type 	-- Types to be unified, and witness of their equality
      -> UM TvSubstEnv		-- Just the extended substitution, 
				-- Nothing if unification failed
-- We do not require the incoming substitution to be idempotent,
-- nor guarantee that the outgoing one is.  That's fixed up by
-- the wrappers.

-- Respects newtypes, PredTypes

-- in unify, any NewTcApps/Preds should be taken at face value
unify subst (TyVarTy tv1) ty2  = uVar subst tv1 ty2
unify subst ty1 (TyVarTy tv2)  = uVar subst tv2 ty1

unify subst ty1 ty2 | Just ty1' <- tcView ty1 = unify subst ty1' ty2
unify subst ty1 ty2 | Just ty2' <- tcView ty2 = unify subst ty1 ty2'

unify subst (PredTy p1) (PredTy p2) = unify_pred subst p1 p2

unify subst (TyConApp tyc1 tys1) (TyConApp tyc2 tys2) 
  | tyc1 == tyc2 = unify_tys subst tys1 tys2

unify subst (FunTy ty1a ty1b) (FunTy ty2a ty2b) 
  = do	{ subst' <- unify subst ty1a ty2a
	; unify subst' ty1b ty2b }

	-- Applications need a bit of care!
	-- They can match FunTy and TyConApp, so use splitAppTy_maybe
	-- NB: we've already dealt with type variables and Notes,
	-- so if one type is an App the other one jolly well better be too
unify subst (AppTy ty1a ty1b) ty2
  | Just (ty2a, ty2b) <- repSplitAppTy_maybe ty2
  = do	{ subst' <- unify subst ty1a ty2a
        ; unify subst' ty1b ty2b }

unify subst ty1 (AppTy ty2a ty2b)
  | Just (ty1a, ty1b) <- repSplitAppTy_maybe ty1
  = do	{ subst' <- unify subst ty1a ty2a
        ; unify subst' ty1b ty2b }

unify _ ty1 ty2 = failWith (misMatch ty1 ty2)
	-- ForAlls??

------------------------------
unify_pred :: TvSubstEnv -> PredType -> PredType -> UM TvSubstEnv
unify_pred subst (ClassP c1 tys1) (ClassP c2 tys2)
  | c1 == c2 = unify_tys subst tys1 tys2
unify_pred subst (IParam n1 t1) (IParam n2 t2)
  | n1 == n2 = unify subst t1 t2
unify_pred _ p1 p2 = failWith (misMatch (PredTy p1) (PredTy p2))
 
------------------------------
unify_tys :: TvSubstEnv -> [Type] -> [Type] -> UM TvSubstEnv
unify_tys subst xs ys = unifyList subst xs ys

unifyList :: TvSubstEnv -> [Type] -> [Type] -> UM TvSubstEnv
unifyList subst orig_xs orig_ys
  = go subst orig_xs orig_ys
  where
    go subst []     []     = return subst
    go subst (x:xs) (y:ys) = do { subst' <- unify subst x y
				; go subst' xs ys }
    go _ _ _ = failWith (lengthMisMatch orig_xs orig_ys)

---------------------------------
uVar :: TvSubstEnv	-- An existing substitution to extend
     -> TyVar           -- Type variable to be unified
     -> Type            -- with this type
     -> UM TvSubstEnv

-- PRE-CONDITION: in the call (uVar swap r tv1 ty), we know that
--	if swap=False	(tv1~ty)
--	if swap=True	(ty~tv1)

uVar subst tv1 ty
 = -- Check to see whether tv1 is refined by the substitution
   case (lookupVarEnv subst tv1) of
     Just ty' -> unify subst ty' ty     -- Yes, call back into unify'
     Nothing  -> uUnrefined subst       -- No, continue
			    tv1 ty ty

uUnrefined :: TvSubstEnv          -- An existing substitution to extend
           -> TyVar               -- Type variable to be unified
           -> Type                -- with this type
           -> Type                -- (version w/ expanded synonyms)
           -> UM TvSubstEnv

-- We know that tv1 isn't refined

uUnrefined subst tv1 ty2 ty2'
  | Just ty2'' <- tcView ty2'
  = uUnrefined subst tv1 ty2 ty2''	-- Unwrap synonyms
		-- This is essential, in case we have
		--	type Foo a = a
		-- and then unify a ~ Foo a

uUnrefined subst tv1 ty2 (TyVarTy tv2)
  | tv1 == tv2		-- Same type variable
  = return subst

    -- Check to see whether tv2 is refined
  | Just ty' <- lookupVarEnv subst tv2
  = uUnrefined subst tv1 ty' ty'

  -- So both are unrefined; next, see if the kinds force the direction
  | eqKind k1 k2	-- Can update either; so check the bind-flags
  = do	{ b1 <- tvBindFlag tv1
	; b2 <- tvBindFlag tv2
	; case (b1,b2) of
	    (BindMe, _) 	 -> bind tv1 ty2
	    (Skolem, Skolem)	 -> failWith (misMatch ty1 ty2)
	    (Skolem, _)		 -> bind tv2 ty1
	}

  | k1 `isSubKind` k2 = bindTv subst tv2 ty1  -- Must update tv2
  | k2 `isSubKind` k1 = bindTv subst tv1 ty2  -- Must update tv1

  | otherwise = failWith (kindMisMatch tv1 ty2)
  where
    ty1 = TyVarTy tv1
    k1 = tyVarKind tv1
    k2 = tyVarKind tv2
    bind tv ty = return $ extendVarEnv subst tv ty

uUnrefined subst tv1 ty2 ty2'	-- ty2 is not a type variable
  | tv1 `elemVarSet` substTvSet subst (tyVarsOfType ty2')
  = failWith (occursCheck tv1 ty2)	-- Occurs check
  | not (k2 `isSubKind` k1)
  = failWith (kindMisMatch tv1 ty2)	-- Kind check
  | otherwise
  = bindTv subst tv1 ty2		-- Bind tyvar to the synonym if poss
  where
    k1 = tyVarKind tv1
    k2 = typeKind ty2'

substTvSet :: TvSubstEnv -> TyVarSet -> TyVarSet
-- Apply the non-idempotent substitution to a set of type variables,
-- remembering that the substitution isn't necessarily idempotent
substTvSet subst tvs
  = foldVarSet (unionVarSet . get) emptyVarSet tvs
  where
    get tv = case lookupVarEnv subst tv of
	       Nothing -> unitVarSet tv
	       Just ty -> substTvSet subst (tyVarsOfType ty)

bindTv :: TvSubstEnv -> TyVar -> Type -> UM TvSubstEnv
bindTv subst tv ty	-- ty is not a type variable
  = do  { b <- tvBindFlag tv
	; case b of
	    Skolem -> failWith (misMatch (TyVarTy tv) ty)
	    BindMe -> return $ extendVarEnv subst tv ty
	}
\end{code}

%************************************************************************
%*									*
		Binding decisions
%*									*
%************************************************************************

\begin{code}
data BindFlag 
  = BindMe	-- A regular type variable

  | Skolem	-- This type variable is a skolem constant
		-- Don't bind it; it only matches itself
\end{code}


%************************************************************************
%*									*
		Unification monad
%*									*
%************************************************************************

\begin{code}
newtype UM a = UM { unUM :: (TyVar -> BindFlag)
		         -> MaybeErr Message a }

instance Monad UM where
  return a = UM (\_tvs -> Succeeded a)
  fail s   = UM (\_tvs -> Failed (text s))
  m >>= k  = UM (\tvs -> case unUM m tvs of
			   Failed err -> Failed err
			   Succeeded v  -> unUM (k v) tvs)

initUM :: (TyVar -> BindFlag) -> UM a -> MaybeErr Message a
initUM badtvs um = unUM um badtvs

tvBindFlag :: TyVar -> UM BindFlag
tvBindFlag tv = UM (\tv_fn -> Succeeded (tv_fn tv))

failWith :: Message -> UM a
failWith msg = UM (\_tv_fn -> Failed msg)

maybeErrToMaybe :: MaybeErr fail succ -> Maybe succ
maybeErrToMaybe (Succeeded a) = Just a
maybeErrToMaybe (Failed _)    = Nothing
\end{code}


%************************************************************************
%*									*
		Error reporting
	We go to a lot more trouble to tidy the types
	in TcUnify.  Maybe we'll end up having to do that
	here too, but I'll leave it for now.
%*									*
%************************************************************************

\begin{code}
misMatch :: Type -> Type -> SDoc
misMatch t1 t2
  = ptext (sLit "Can't match types") <+> quotes (ppr t1) <+> 
    ptext (sLit "and") <+> quotes (ppr t2)

lengthMisMatch :: [Type] -> [Type] -> SDoc
lengthMisMatch tys1 tys2
  = sep [ptext (sLit "Can't match unequal length lists"), 
	 nest 2 (ppr tys1), nest 2 (ppr tys2) ]

kindMisMatch :: TyVar -> Type -> SDoc
kindMisMatch tv1 t2
  = vcat [ptext (sLit "Can't match kinds") <+> quotes (ppr (tyVarKind tv1)) <+> 
	    ptext (sLit "and") <+> quotes (ppr (typeKind t2)),
	  ptext (sLit "when matching") <+> quotes (ppr tv1) <+> 
		ptext (sLit "with") <+> quotes (ppr t2)]

occursCheck :: TyVar -> Type -> SDoc
occursCheck tv ty
  = hang (ptext (sLit "Can't construct the infinite type"))
       2 (ppr tv <+> equals <+> ppr ty)
\end{code}