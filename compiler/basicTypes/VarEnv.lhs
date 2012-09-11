%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

\begin{code}
module VarEnv (
        -- * Var, Id and TyVar environments (maps)
	VarEnv, IdEnv, TyVarEnv,
	
	-- ** Manipulating these environments
	emptyVarEnv, unitVarEnv, mkVarEnv,
	elemVarEnv, varEnvElts, varEnvKeys,
	extendVarEnv, extendVarEnv_C, extendVarEnvList,
	plusVarEnv, plusVarEnv_C,
	delVarEnvList, delVarEnv,
	lookupVarEnv, lookupVarEnv_NF, lookupWithDefaultVarEnv,
	mapVarEnv, zipVarEnv,
	modifyVarEnv, modifyVarEnv_Directly,
	isEmptyVarEnv, foldVarEnv, 
	elemVarEnvByKey, lookupVarEnv_Directly,
	filterVarEnv_Directly,

	-- * The InScopeSet type
	InScopeSet, 
	
	-- ** Operations on InScopeSets
	emptyInScopeSet, mkInScopeSet, delInScopeSet,
	extendInScopeSet, extendInScopeSetList, extendInScopeSetSet, 
	modifyInScopeSet,
	getInScopeVars, lookupInScope, elemInScopeSet, uniqAway, 

	-- * The RnEnv2 type
	RnEnv2, 
	
	-- ** Operations on RnEnv2s
	mkRnEnv2, rnBndr2, rnBndrs2, rnOccL, rnOccR, inRnEnvL, inRnEnvR,
	rnBndrL, rnBndrR, nukeRnEnvL, nukeRnEnvR, extendRnInScopeList,
	rnInScope, rnInScopeSet, lookupRnInScope,

	-- * TidyEnv and its operation
	TidyEnv, 
	emptyTidyEnv
    ) where

import OccName
import Var
import VarSet
import UniqFM
import Unique
import Util
import Maybes
import Outputable
import FastTypes
import StaticFlags
import FastString
\end{code}


%************************************************************************
%*									*
		In-scope sets
%*									*
%************************************************************************

\begin{code}
-- | A set of variables that are in scope at some point
data InScopeSet = InScope (VarEnv Var) FastInt
	-- The Int# is a kind of hash-value used by uniqAway
	-- For example, it might be the size of the set
	-- INVARIANT: it's not zero; we use it as a multiplier in uniqAway

instance Outputable InScopeSet where
  ppr (InScope s _) = ptext (sLit "InScope") <+> ppr s

emptyInScopeSet :: InScopeSet
emptyInScopeSet = InScope emptyVarSet (_ILIT(1))

getInScopeVars ::  InScopeSet -> VarEnv Var
getInScopeVars (InScope vs _) = vs

mkInScopeSet :: VarEnv Var -> InScopeSet
mkInScopeSet in_scope = InScope in_scope (_ILIT(1))

extendInScopeSet :: InScopeSet -> Var -> InScopeSet
extendInScopeSet (InScope in_scope n) v = InScope (extendVarEnv in_scope v v) (n +# _ILIT(1))

extendInScopeSetList :: InScopeSet -> [Var] -> InScopeSet
extendInScopeSetList (InScope in_scope n) vs
   = InScope (foldl (\s v -> extendVarEnv s v v) in_scope vs)
		    (n +# iUnbox (length vs))

extendInScopeSetSet :: InScopeSet -> VarEnv Var -> InScopeSet
extendInScopeSetSet (InScope in_scope n) vs
   = InScope (in_scope `plusVarEnv` vs) (n +# iUnbox (sizeUFM vs))

-- | Replace the first 'Var' with the second in the set of in-scope variables
modifyInScopeSet :: InScopeSet -> Var -> Var -> InScopeSet
-- Exploit the fact that the in-scope "set" is really a map
-- 	Make old_v map to new_v
-- QUESTION: shouldn't we add a mapping from new_v to new_v as it is presumably now in scope? - MB 08
modifyInScopeSet (InScope in_scope n) old_v new_v = InScope (extendVarEnv in_scope old_v new_v) (n +# _ILIT(1))

delInScopeSet :: InScopeSet -> Var -> InScopeSet
delInScopeSet (InScope in_scope n) v = InScope (in_scope `delVarEnv` v) n

elemInScopeSet :: Var -> InScopeSet -> Bool
elemInScopeSet v (InScope in_scope _) = v `elemVarEnv` in_scope

-- | If the given variable was even added to the 'InScopeSet', or if it was the \"from\" argument
-- of any 'modifyInScopeSet' operation, returns that variable with all appropriate modifications
-- applied to it. Otherwise, return @Nothing@
lookupInScope :: InScopeSet -> Var -> Maybe Var
-- It's important to look for a fixed point
-- When we see (case x of y { I# v -> ... })
-- we add  [x -> y] to the in-scope set (Simplify.simplCaseBinder and
-- modifyInScopeSet).
--
-- When we lookup up an occurrence of x, we map to y, but then
-- we want to look up y in case it has acquired more evaluation information by now.
lookupInScope (InScope in_scope _) v 
  = go v
  where
    go v = case lookupVarEnv in_scope v of
		Just v' | v == v'   -> Just v'	-- Reached a fixed point
			| otherwise -> go v'
		Nothing		    -> Nothing
\end{code}

\begin{code}
-- | @uniqAway in_scope v@ finds a unique that is not used in the
-- in-scope set, and gives that to v. 
uniqAway :: InScopeSet -> Var -> Var
-- It starts with v's current unique, of course, in the hope that it won't
-- have to change, and thereafter uses a combination of that and the hash-code
-- found in the in-scope set
uniqAway in_scope var
  | var `elemInScopeSet` in_scope = uniqAway' in_scope var	-- Make a new one
  | otherwise 			  = var				-- Nothing to do

uniqAway' :: InScopeSet -> Var -> Var
-- This one *always* makes up a new variable
uniqAway' (InScope set n) var
  = try (_ILIT(1))
  where
    orig_unique = getUnique var
    try k 
	  | debugIsOn && (k ># _ILIT(1000))
	  = pprPanic "uniqAway loop:" (ppr (iBox k) <+> text "tries" <+> ppr var <+> int (iBox n)) 
	  | uniq `elemVarSetByKey` set = try (k +# _ILIT(1))
	  | debugIsOn && opt_PprStyle_Debug && (k ># _ILIT(3))
	  = pprTrace "uniqAway:" (ppr (iBox k) <+> text "tries" <+> ppr var <+> int (iBox n)) 
	    setVarUnique var uniq
	  | otherwise = setVarUnique var uniq
	  where
	    uniq = deriveUnique orig_unique (iBox (n *# k))
\end{code}

%************************************************************************
%*									*
		Dual renaming
%*									*
%************************************************************************

\begin{code}
-- | When we are comparing (or matching) types or terms, we are faced with 
-- \"going under\" corresponding binders.  E.g. when comparing:
--
-- > \x. e1	~   \y. e2
--
-- Basically we want to rename [@x@ -> @y@] or [@y@ -> @x@], but there are lots of 
-- things we must be careful of.  In particular, @x@ might be free in @e2@, or
-- y in @e1@.  So the idea is that we come up with a fresh binder that is free
-- in neither, and rename @x@ and @y@ respectively.  That means we must maintain:
--
-- 1. A renaming for the left-hand expression
--
-- 2. A renaming for the right-hand expressions
--
-- 3. An in-scope set
-- 
-- Furthermore, when matching, we want to be able to have an 'occurs check',
-- to prevent:
--
-- > \x. f   ~   \y. y
--
-- matching with [@f@ -> @y@].  So for each expression we want to know that set of
-- locally-bound variables. That is precisely the domain of the mappings 1.
-- and 2., but we must ensure that we always extend the mappings as we go in.
--
-- All of this information is bundled up in the 'RnEnv2'
data RnEnv2
  = RV2 { envL 	   :: VarEnv Var	-- Renaming for Left term
	, envR 	   :: VarEnv Var	-- Renaming for Right term
	, in_scope :: InScopeSet }	-- In scope in left or right terms

-- The renamings envL and envR are *guaranteed* to contain a binding
-- for every variable bound as we go into the term, even if it is not
-- renamed.  That way we can ask what variables are locally bound
-- (inRnEnvL, inRnEnvR)

mkRnEnv2 :: InScopeSet -> RnEnv2
mkRnEnv2 vars = RV2	{ envL 	   = emptyVarEnv 
			, envR 	   = emptyVarEnv
			, in_scope = vars }

extendRnInScopeList :: RnEnv2 -> [Var] -> RnEnv2
extendRnInScopeList env vs
  = env { in_scope = extendInScopeSetList (in_scope env) vs }

rnInScope :: Var -> RnEnv2 -> Bool
rnInScope x env = x `elemInScopeSet` in_scope env

rnInScopeSet :: RnEnv2 -> InScopeSet
rnInScopeSet = in_scope

rnBndrs2 :: RnEnv2 -> [Var] -> [Var] -> RnEnv2
-- ^ Applies 'rnBndr2' to several variables: the two variable lists must be of equal length
rnBndrs2 env bsL bsR = foldl2 rnBndr2 env bsL bsR 

rnBndr2 :: RnEnv2 -> Var -> Var -> RnEnv2
-- ^ @rnBndr2 env bL bR@ goes under a binder @bL@ in the Left term,
-- 		         and binder @bR@ in the Right term.
-- It finds a new binder, @new_b@,
-- and returns an environment mapping @bL -> new_b@ and @bR -> new_b@
rnBndr2 (RV2 { envL = envL, envR = envR, in_scope = in_scope }) bL bR
  = RV2 { envL 	   = extendVarEnv envL bL new_b	  -- See Note
	, envR 	   = extendVarEnv envR bR new_b	  -- [Rebinding]
	, in_scope = extendInScopeSet in_scope new_b }
  where
	-- Find a new binder not in scope in either term
    new_b | not (bL `elemInScopeSet` in_scope) = bL
      	  | not (bR `elemInScopeSet` in_scope) = bR
      	  | otherwise			       = uniqAway' in_scope bL

	-- Note [Rebinding]
	-- If the new var is the same as the old one, note that
	-- the extendVarEnv *deletes* any current renaming
	-- E.g.	  (\x. \x. ...)	 ~  (\y. \z. ...)
	--
	--   Inside \x  \y	{ [x->y], [y->y],       {y} }
	-- 	 \x  \z	  	{ [x->x], [y->y, z->x], {y,x} }

rnBndrL :: RnEnv2 -> Var -> (RnEnv2, Var)
-- ^ Similar to 'rnBndr2' but used when there's a binder on the left
-- side only. Useful when eta-expanding
rnBndrL (RV2 { envL = envL, envR = envR, in_scope = in_scope }) bL
  = (RV2 { envL     = extendVarEnv envL bL new_b
	 , envR     = extendVarEnv envR new_b new_b 	-- Note [rnBndrLR]
	 , in_scope = extendInScopeSet in_scope new_b }, new_b)
  where
    new_b = uniqAway in_scope bL

rnBndrR :: RnEnv2 -> Var -> (RnEnv2, Var)
-- ^ Similar to 'rnBndr2' but used when there's a binder on the right
-- side only. Useful when eta-expanding
rnBndrR (RV2 { envL = envL, envR = envR, in_scope = in_scope }) bR
  = (RV2 { envL     = extendVarEnv envL new_b new_b	-- Note [rnBndrLR]
	 , envR     = extendVarEnv envR bR new_b
	 , in_scope = extendInScopeSet in_scope new_b }, new_b)
  where
    new_b = uniqAway in_scope bR

-- Note [rnBndrLR] 
-- ~~~~~~~~~~~~~~~
-- Notice that in rnBndrL, rnBndrR, we extend envR, envL respectively
-- with a binding [new_b -> new_b], where new_b is the new binder.
-- This is important when doing eta expansion; e.g. matching (\x.M) ~ N
-- In effect we switch to (\x'.M) ~ (\x'.N x'), where x' is new_b
-- So we must add x' to the env of both L and R.  (x' is fresh, so it
-- can't capture anything in N.)  
--
-- If we don't do this, we can get silly matches like
--	forall a.  \y.a  ~   v
-- succeeding with [x -> v y], which is bogus of course 

rnOccL, rnOccR :: RnEnv2 -> Var -> Var
-- ^ Look up the renaming of an occurrence in the left or right term
rnOccL (RV2 { envL = env }) v = lookupVarEnv env v `orElse` v
rnOccR (RV2 { envR = env }) v = lookupVarEnv env v `orElse` v

inRnEnvL, inRnEnvR :: RnEnv2 -> Var -> Bool
-- ^ Tells whether a variable is locally bound
inRnEnvL (RV2 { envL = env }) v = v `elemVarEnv` env
inRnEnvR (RV2 { envR = env }) v = v `elemVarEnv` env

lookupRnInScope :: RnEnv2 -> Var -> Var
lookupRnInScope env v = lookupInScope (in_scope env) v `orElse` v

nukeRnEnvL, nukeRnEnvR :: RnEnv2 -> RnEnv2
-- ^ Wipe the left or right side renaming
nukeRnEnvL env = env { envL = emptyVarEnv }
nukeRnEnvR env = env { envR = emptyVarEnv }
\end{code}


%************************************************************************
%*									*
		Tidying
%*									*
%************************************************************************

\begin{code}
-- | When tidying up print names, we keep a mapping of in-scope occ-names
-- (the 'TidyOccEnv') and a Var-to-Var of the current renamings
type TidyEnv = (TidyOccEnv, VarEnv Var)

emptyTidyEnv :: TidyEnv
emptyTidyEnv = (emptyTidyOccEnv, emptyVarEnv)
\end{code}


%************************************************************************
%*									*
\subsection{@VarEnv@s}
%*									*
%************************************************************************

\begin{code}
type VarEnv elt   = UniqFM elt
type IdEnv elt    = VarEnv elt
type TyVarEnv elt = VarEnv elt

emptyVarEnv	  :: VarEnv a
mkVarEnv	  :: [(Var, a)] -> VarEnv a
zipVarEnv	  :: [Var] -> [a] -> VarEnv a
unitVarEnv	  :: Var -> a -> VarEnv a
extendVarEnv	  :: VarEnv a -> Var -> a -> VarEnv a
extendVarEnv_C	  :: (a->a->a) -> VarEnv a -> Var -> a -> VarEnv a
plusVarEnv	  :: VarEnv a -> VarEnv a -> VarEnv a
extendVarEnvList  :: VarEnv a -> [(Var, a)] -> VarEnv a
		  
lookupVarEnv_Directly :: VarEnv a -> Unique -> Maybe a
filterVarEnv_Directly :: (Unique -> a -> Bool) -> VarEnv a -> VarEnv a
delVarEnvList     :: VarEnv a -> [Var] -> VarEnv a
delVarEnv	  :: VarEnv a -> Var -> VarEnv a
plusVarEnv_C	  :: (a -> a -> a) -> VarEnv a -> VarEnv a -> VarEnv a
mapVarEnv	  :: (a -> b) -> VarEnv a -> VarEnv b
modifyVarEnv	  :: (a -> a) -> VarEnv a -> Var -> VarEnv a
varEnvElts	  :: VarEnv a -> [a]
varEnvKeys	  :: VarEnv a -> [Unique]
		  
isEmptyVarEnv	  :: VarEnv a -> Bool
lookupVarEnv	  :: VarEnv a -> Var -> Maybe a
lookupVarEnv_NF   :: VarEnv a -> Var -> a
lookupWithDefaultVarEnv :: VarEnv a -> a -> Var -> a
elemVarEnv	  :: Var -> VarEnv a -> Bool
elemVarEnvByKey   :: Unique -> VarEnv a -> Bool
foldVarEnv	  :: (a -> b -> b) -> b -> VarEnv a -> b
\end{code}

\begin{code}
elemVarEnv       = elemUFM
elemVarEnvByKey  = elemUFM_Directly
extendVarEnv	 = addToUFM
extendVarEnv_C	 = addToUFM_C
extendVarEnvList = addListToUFM
plusVarEnv_C	 = plusUFM_C
delVarEnvList	 = delListFromUFM
delVarEnv	 = delFromUFM
plusVarEnv	 = plusUFM
lookupVarEnv	 = lookupUFM
lookupWithDefaultVarEnv = lookupWithDefaultUFM
mapVarEnv	 = mapUFM
mkVarEnv	 = listToUFM
emptyVarEnv	 = emptyUFM
varEnvElts	 = eltsUFM
varEnvKeys	 = keysUFM
unitVarEnv	 = unitUFM
isEmptyVarEnv	 = isNullUFM
foldVarEnv	 = foldUFM
lookupVarEnv_Directly = lookupUFM_Directly
filterVarEnv_Directly = filterUFM_Directly

zipVarEnv tyvars tys   = mkVarEnv (zipEqual "zipVarEnv" tyvars tys)
lookupVarEnv_NF env id = case lookupVarEnv env id of
                         Just xx -> xx
                         Nothing -> panic "lookupVarEnv_NF: Nothing"
\end{code}

@modifyVarEnv@: Look up a thing in the VarEnv, 
then mash it with the modify function, and put it back.

\begin{code}
modifyVarEnv mangle_fn env key
  = case (lookupVarEnv env key) of
      Nothing -> env
      Just xx -> extendVarEnv env key (mangle_fn xx)

modifyVarEnv_Directly :: (a -> a) -> UniqFM a -> Unique -> UniqFM a
modifyVarEnv_Directly mangle_fn env key
  = case (lookupUFM_Directly env key) of
      Nothing -> env
      Just xx -> addToUFM_Directly env key (mangle_fn xx)
\end{code}
