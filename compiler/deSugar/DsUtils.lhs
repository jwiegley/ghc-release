%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

Utilities for desugaring

This module exports some utility functions of no great interest.

\begin{code}

-- | Utility functions for constructing Core syntax, principally for desugaring
module DsUtils (
	EquationInfo(..), 
	firstPat, shiftEqns,

	MatchResult(..), CanItFail(..), 
	cantFailMatchResult, alwaysFailMatchResult,
	extractMatchResult, combineMatchResults, 
	adjustMatchResult,  adjustMatchResultDs,
	mkCoLetMatchResult, mkViewMatchResult, mkGuardedMatchResult, 
	matchCanFail, mkEvalMatchResult,
	mkCoPrimCaseMatchResult, mkCoAlgCaseMatchResult,
	wrapBind, wrapBinds,

	mkErrorAppDs,

        seqVar,

        -- LHs tuples
        mkLHsVarTup, mkLHsTup, mkLHsVarPatTup, mkLHsPatTup,
        mkBigLHsVarTup, mkBigLHsTup, mkBigLHsVarPatTup, mkBigLHsPatTup,

        mkSelectorBinds,

        dsSyntaxTable, lookupEvidence,

	selectSimpleMatchVarL, selectMatchVars, selectMatchVar,
	mkTickBox, mkOptTickBox, mkBinaryTickBox
    ) where

#include "HsVersions.h"

import {-# SOURCE #-}	Match ( matchSimply )
import {-# SOURCE #-}	DsExpr( dsExpr )

import HsSyn
import TcHsSyn
import TcType( tcSplitTyConApp )
import CoreSyn
import DsMonad

import CoreUtils
import MkCore
import MkId
import Id
import Var
import Name
import Literal
import TyCon
import DataCon
import Type
import Coercion
import TysPrim
import TysWiredIn
import BasicTypes
import UniqSet
import UniqSupply
import PrelNames
import Outputable
import SrcLoc
import Util
import ListSetOps
import FastString
import StaticFlags

import Data.Char
\end{code}



%************************************************************************
%*									*
		Rebindable syntax
%*									*
%************************************************************************

\begin{code}
dsSyntaxTable :: SyntaxTable Id 
	       -> DsM ([CoreBind], 	-- Auxiliary bindings
		       [(Name,Id)])	-- Maps the standard name to its value

dsSyntaxTable rebound_ids = do
    (binds_s, prs) <- mapAndUnzipM mk_bind rebound_ids
    return (concat binds_s, prs)
  where
        -- The cheapo special case can happen when we 
        -- make an intermediate HsDo when desugaring a RecStmt
    mk_bind (std_name, HsVar id) = return ([], (std_name, id))
    mk_bind (std_name, expr) = do
           rhs <- dsExpr expr
           id <- newSysLocalDs (exprType rhs)
           return ([NonRec id rhs], (std_name, id))

lookupEvidence :: [(Name, Id)] -> Name -> Id
lookupEvidence prs std_name
  = assocDefault (mk_panic std_name) prs std_name
  where
    mk_panic std_name = pprPanic "dsSyntaxTable" (ptext (sLit "Not found:") <+> ppr std_name)
\end{code}

%************************************************************************
%*									*
\subsection{ Selecting match variables}
%*									*
%************************************************************************

We're about to match against some patterns.  We want to make some
@Ids@ to use as match variables.  If a pattern has an @Id@ readily at
hand, which should indeed be bound to the pattern as a whole, then use it;
otherwise, make one up.

\begin{code}
selectSimpleMatchVarL :: LPat Id -> DsM Id
selectSimpleMatchVarL pat = selectMatchVar (unLoc pat)

-- (selectMatchVars ps tys) chooses variables of type tys
-- to use for matching ps against.  If the pattern is a variable,
-- we try to use that, to save inventing lots of fresh variables.
--
-- OLD, but interesting note:
--    But even if it is a variable, its type might not match.  Consider
--	data T a where
--	  T1 :: Int -> T Int
--	  T2 :: a   -> T a
--
--	f :: T a -> a -> Int
--	f (T1 i) (x::Int) = x
--	f (T2 i) (y::a)   = 0
--    Then we must not choose (x::Int) as the matching variable!
-- And nowadays we won't, because the (x::Int) will be wrapped in a CoPat

selectMatchVars :: [Pat Id] -> DsM [Id]
selectMatchVars ps = mapM selectMatchVar ps

selectMatchVar :: Pat Id -> DsM Id
selectMatchVar (BangPat pat)   = selectMatchVar (unLoc pat)
selectMatchVar (LazyPat pat)   = selectMatchVar (unLoc pat)
selectMatchVar (ParPat pat)    = selectMatchVar (unLoc pat)
selectMatchVar (VarPat var)    = return var
selectMatchVar (AsPat var _) = return (unLoc var)
selectMatchVar other_pat       = newSysLocalDs (hsPatType other_pat)
				  -- OK, better make up one...
\end{code}


%************************************************************************
%*									*
%* type synonym EquationInfo and access functions for its pieces	*
%*									*
%************************************************************************
\subsection[EquationInfo-synonym]{@EquationInfo@: a useful synonym}

The ``equation info'' used by @match@ is relatively complicated and
worthy of a type synonym and a few handy functions.

\begin{code}
firstPat :: EquationInfo -> Pat Id
firstPat eqn = ASSERT( notNull (eqn_pats eqn) ) head (eqn_pats eqn)

shiftEqns :: [EquationInfo] -> [EquationInfo]
-- Drop the first pattern in each equation
shiftEqns eqns = [ eqn { eqn_pats = tail (eqn_pats eqn) } | eqn <- eqns ]
\end{code}

Functions on MatchResults

\begin{code}
matchCanFail :: MatchResult -> Bool
matchCanFail (MatchResult CanFail _)  = True
matchCanFail (MatchResult CantFail _) = False

alwaysFailMatchResult :: MatchResult
alwaysFailMatchResult = MatchResult CanFail (\fail -> return fail)

cantFailMatchResult :: CoreExpr -> MatchResult
cantFailMatchResult expr = MatchResult CantFail (\_ -> return expr)

extractMatchResult :: MatchResult -> CoreExpr -> DsM CoreExpr
extractMatchResult (MatchResult CantFail match_fn) _
  = match_fn (error "It can't fail!")

extractMatchResult (MatchResult CanFail match_fn) fail_expr = do
    (fail_bind, if_it_fails) <- mkFailurePair fail_expr
    body <- match_fn if_it_fails
    return (mkCoreLet fail_bind body)


combineMatchResults :: MatchResult -> MatchResult -> MatchResult
combineMatchResults (MatchResult CanFail      body_fn1)
                    (MatchResult can_it_fail2 body_fn2)
  = MatchResult can_it_fail2 body_fn
  where
    body_fn fail = do body2 <- body_fn2 fail
                      (fail_bind, duplicatable_expr) <- mkFailurePair body2
                      body1 <- body_fn1 duplicatable_expr
                      return (Let fail_bind body1)

combineMatchResults match_result1@(MatchResult CantFail _) _
  = match_result1

adjustMatchResult :: DsWrapper -> MatchResult -> MatchResult
adjustMatchResult encl_fn (MatchResult can_it_fail body_fn)
  = MatchResult can_it_fail (\fail -> encl_fn <$> body_fn fail)

adjustMatchResultDs :: (CoreExpr -> DsM CoreExpr) -> MatchResult -> MatchResult
adjustMatchResultDs encl_fn (MatchResult can_it_fail body_fn)
  = MatchResult can_it_fail (\fail -> encl_fn =<< body_fn fail)

wrapBinds :: [(Var,Var)] -> CoreExpr -> CoreExpr
wrapBinds [] e = e
wrapBinds ((new,old):prs) e = wrapBind new old (wrapBinds prs e)

wrapBind :: Var -> Var -> CoreExpr -> CoreExpr
wrapBind new old body	-- Can deal with term variables *or* type variables
  | new==old    = body
  | isTyVar new = Let (mkTyBind new (mkTyVarTy old)) body
  | otherwise   = Let (NonRec new (Var old))         body

seqVar :: Var -> CoreExpr -> CoreExpr
seqVar var body = Case (Var var) var (exprType body)
			[(DEFAULT, [], body)]

mkCoLetMatchResult :: CoreBind -> MatchResult -> MatchResult
mkCoLetMatchResult bind = adjustMatchResult (mkCoreLet bind)

-- (mkViewMatchResult var' viewExpr var mr) makes the expression
-- let var' = viewExpr var in mr
mkViewMatchResult :: Id -> CoreExpr -> Id -> MatchResult -> MatchResult
mkViewMatchResult var' viewExpr var = 
    adjustMatchResult (mkCoreLet (NonRec var' (mkCoreApp viewExpr (Var var))))

mkEvalMatchResult :: Id -> Type -> MatchResult -> MatchResult
mkEvalMatchResult var ty
  = adjustMatchResult (\e -> Case (Var var) var ty [(DEFAULT, [], e)]) 

mkGuardedMatchResult :: CoreExpr -> MatchResult -> MatchResult
mkGuardedMatchResult pred_expr (MatchResult _ body_fn)
  = MatchResult CanFail (\fail -> do body <- body_fn fail
                                     return (mkIfThenElse pred_expr body fail))

mkCoPrimCaseMatchResult :: Id				-- Scrutinee
                    -> Type                             -- Type of the case
		    -> [(Literal, MatchResult)]		-- Alternatives
		    -> MatchResult
mkCoPrimCaseMatchResult var ty match_alts
  = MatchResult CanFail mk_case
  where
    mk_case fail = do
        alts <- mapM (mk_alt fail) sorted_alts
        return (Case (Var var) var ty ((DEFAULT, [], fail) : alts))

    sorted_alts = sortWith fst match_alts	-- Right order for a Case
    mk_alt fail (lit, MatchResult _ body_fn) = do body <- body_fn fail
                                                  return (LitAlt lit, [], body)


mkCoAlgCaseMatchResult :: Id					-- Scrutinee
                    -> Type                                     -- Type of exp
		    -> [(DataCon, [CoreBndr], MatchResult)]	-- Alternatives
		    -> MatchResult
mkCoAlgCaseMatchResult var ty match_alts 
  | isNewTyCon tycon		-- Newtype case; use a let
  = ASSERT( null (tail match_alts) && null (tail arg_ids1) )
    mkCoLetMatchResult (NonRec arg_id1 newtype_rhs) match_result1

  | isPArrFakeAlts match_alts	-- Sugared parallel array; use a literal case 
  = MatchResult CanFail mk_parrCase

  | otherwise			-- Datatype case; use a case
  = MatchResult fail_flag mk_case
  where
    tycon = dataConTyCon con1
	-- [Interesting: becuase of GADTs, we can't rely on the type of 
	--  the scrutinised Id to be sufficiently refined to have a TyCon in it]

	-- Stuff for newtype
    (con1, arg_ids1, match_result1) = ASSERT( notNull match_alts ) head match_alts
    arg_id1 	= ASSERT( notNull arg_ids1 ) head arg_ids1
    var_ty      = idType var
    (tc, ty_args) = tcSplitTyConApp var_ty	-- Don't look through newtypes
    	 	    		    		-- (not that splitTyConApp does, these days)
    newtype_rhs = unwrapNewTypeBody tc ty_args (Var var)
		
	-- Stuff for data types
    data_cons      = tyConDataCons tycon
    match_results  = [match_result | (_,_,match_result) <- match_alts]

    fail_flag | exhaustive_case
	      = foldr1 orFail [can_it_fail | MatchResult can_it_fail _ <- match_results]
	      | otherwise
	      = CanFail

    wild_var = mkWildId (idType var)
    sorted_alts  = sortWith get_tag match_alts
    get_tag (con, _, _) = dataConTag con
    mk_case fail = do alts <- mapM (mk_alt fail) sorted_alts
                      return (Case (Var var) wild_var ty (mk_default fail ++ alts))

    mk_alt fail (con, args, MatchResult _ body_fn) = do
          body <- body_fn fail
          us <- newUniqueSupply
          return (mkReboxingAlt (uniqsFromSupply us) con args body)

    mk_default fail | exhaustive_case = []
		    | otherwise       = [(DEFAULT, [], fail)]

    un_mentioned_constructors
        = mkUniqSet data_cons `minusUniqSet` mkUniqSet [ con | (con, _, _) <- match_alts]
    exhaustive_case = isEmptyUniqSet un_mentioned_constructors

	-- Stuff for parallel arrays
	-- 
	--  * the following is to desugar cases over fake constructors for
	--   parallel arrays, which are introduced by `tidy1' in the `PArrPat'
	--   case
	--
	-- Concerning `isPArrFakeAlts':
	--
	--  * it is *not* sufficient to just check the type of the type
	--   constructor, as we have to be careful not to confuse the real
	--   representation of parallel arrays with the fake constructors;
	--   moreover, a list of alternatives must not mix fake and real
	--   constructors (this is checked earlier on)
	--
	-- FIXME: We actually go through the whole list and make sure that
	--	  either all or none of the constructors are fake parallel
	--	  array constructors.  This is to spot equations that mix fake
	--	  constructors with the real representation defined in
	--	  `PrelPArr'.  It would be nicer to spot this situation
	--	  earlier and raise a proper error message, but it can really
	--	  only happen in `PrelPArr' anyway.
	--
    isPArrFakeAlts [(dcon, _, _)]      = isPArrFakeCon dcon
    isPArrFakeAlts ((dcon, _, _):alts) = 
      case (isPArrFakeCon dcon, isPArrFakeAlts alts) of
        (True , True ) -> True
        (False, False) -> False
        _              -> panic "DsUtils: you may not mix `[:...:]' with `PArr' patterns"
    isPArrFakeAlts [] = panic "DsUtils: unexpectedly found an empty list of PArr fake alternatives"
    --
    mk_parrCase fail = do
      lengthP <- dsLookupGlobalId lengthPName
      alt <- unboxAlt
      return (Case (len lengthP) (mkWildId intTy) ty [alt])
      where
	elemTy      = case splitTyConApp (idType var) of
		        (_, [elemTy]) -> elemTy
		        _	        -> panic panicMsg
        panicMsg    = "DsUtils.mkCoAlgCaseMatchResult: not a parallel array?"
	len lengthP = mkApps (Var lengthP) [Type elemTy, Var var]
	--
	unboxAlt = do
	  l      <- newSysLocalDs intPrimTy
	  indexP <- dsLookupGlobalId indexPName
	  alts   <- mapM (mkAlt indexP) sorted_alts
	  return (DataAlt intDataCon, [l], (Case (Var l) wild ty (dft : alts)))
          where
	    wild = mkWildId intPrimTy
	    dft  = (DEFAULT, [], fail)
	--
	-- each alternative matches one array length (corresponding to one
	-- fake array constructor), so the match is on a literal; each
	-- alternative's body is extended by a local binding for each
	-- constructor argument, which are bound to array elements starting
	-- with the first
	--
	mkAlt indexP (con, args, MatchResult _ bodyFun) = do
	  body <- bodyFun fail
	  return (LitAlt lit, [], mkCoreLets binds body)
	  where
	    lit   = MachInt $ toInteger (dataConSourceArity con)
	    binds = [NonRec arg (indexExpr i) | (i, arg) <- zip [1..] args]
	    --
	    indexExpr i = mkApps (Var indexP) [Type elemTy, Var var, mkIntExpr i]
\end{code}

%************************************************************************
%*									*
\subsection{Desugarer's versions of some Core functions}
%*									*
%************************************************************************

\begin{code}
mkErrorAppDs :: Id 		-- The error function
	     -> Type		-- Type to which it should be applied
	     -> String		-- The error message string to pass
	     -> DsM CoreExpr

mkErrorAppDs err_id ty msg = do
    src_loc <- getSrcSpanDs
    let
        full_msg = showSDoc (hcat [ppr src_loc, text "|", text msg])
        core_msg = Lit (mkMachString full_msg)
        -- mkMachString returns a result of type String#
    return (mkApps (Var err_id) [Type ty, core_msg])
\end{code}

%************************************************************************
%*									*
\subsection[mkSelectorBind]{Make a selector bind}
%*									*
%************************************************************************

This is used in various places to do with lazy patterns.
For each binder $b$ in the pattern, we create a binding:
\begin{verbatim}
    b = case v of pat' -> b'
\end{verbatim}
where @pat'@ is @pat@ with each binder @b@ cloned into @b'@.

ToDo: making these bindings should really depend on whether there's
much work to be done per binding.  If the pattern is complex, it
should be de-mangled once, into a tuple (and then selected from).
Otherwise the demangling can be in-line in the bindings (as here).

Boring!  Boring!  One error message per binder.  The above ToDo is
even more helpful.  Something very similar happens for pattern-bound
expressions.

\begin{code}
mkSelectorBinds :: LPat Id	-- The pattern
		-> CoreExpr	-- Expression to which the pattern is bound
		-> DsM [(Id,CoreExpr)]

mkSelectorBinds (L _ (VarPat v)) val_expr
  = return [(v, val_expr)]

mkSelectorBinds pat val_expr
  | isSingleton binders || is_simple_lpat pat = do
        -- Given   p = e, where p binds x,y
        -- we are going to make
        --      v = p   (where v is fresh)
        --      x = case v of p -> x
        --      y = case v of p -> x

        -- Make up 'v'
        -- NB: give it the type of *pattern* p, not the type of the *rhs* e.
        -- This does not matter after desugaring, but there's a subtle 
        -- issue with implicit parameters. Consider
        --      (x,y) = ?i
        -- Then, ?i is given type {?i :: Int}, a PredType, which is opaque
        -- to the desugarer.  (Why opaque?  Because newtypes have to be.  Why
        -- does it get that type?  So that when we abstract over it we get the
        -- right top-level type  (?i::Int) => ...)
        --
        -- So to get the type of 'v', use the pattern not the rhs.  Often more
        -- efficient too.
      val_var <- newSysLocalDs (hsLPatType pat)

        -- For the error message we make one error-app, to avoid duplication.
        -- But we need it at different types... so we use coerce for that
      err_expr <- mkErrorAppDs iRREFUT_PAT_ERROR_ID  unitTy (showSDoc (ppr pat))
      err_var <- newSysLocalDs unitTy
      binds <- mapM (mk_bind val_var err_var) binders
      return ( (val_var, val_expr) : 
               (err_var, err_expr) :
               binds )


  | otherwise = do
      error_expr <- mkErrorAppDs iRREFUT_PAT_ERROR_ID   tuple_ty (showSDoc (ppr pat))
      tuple_expr <- matchSimply val_expr PatBindRhs pat local_tuple error_expr
      tuple_var <- newSysLocalDs tuple_ty
      let
          mk_tup_bind binder
            = (binder, mkTupleSelector binders binder tuple_var (Var tuple_var))
      return ( (tuple_var, tuple_expr) : map mk_tup_bind binders )
  where
    binders     = collectPatBinders pat
    local_tuple = mkBigCoreVarTup binders
    tuple_ty    = exprType local_tuple

    mk_bind scrut_var err_var bndr_var = do
    -- (mk_bind sv err_var) generates
    --          bv = case sv of { pat -> bv; other -> coerce (type-of-bv) err_var }
    -- Remember, pat binds bv
        rhs_expr <- matchSimply (Var scrut_var) PatBindRhs pat
                                (Var bndr_var) error_expr
        return (bndr_var, rhs_expr)
      where
        error_expr = mkCoerce co (Var err_var)
        co         = mkUnsafeCoercion (exprType (Var err_var)) (idType bndr_var)

    is_simple_lpat p = is_simple_pat (unLoc p)

    is_simple_pat (TuplePat ps Boxed _)        = all is_triv_lpat ps
    is_simple_pat (ConPatOut{ pat_args = ps }) = all is_triv_lpat (hsConPatArgs ps)
    is_simple_pat (VarPat _)                   = True
    is_simple_pat (ParPat p)                   = is_simple_lpat p
    is_simple_pat _                                    = False

    is_triv_lpat p = is_triv_pat (unLoc p)

    is_triv_pat (VarPat _)  = True
    is_triv_pat (WildPat _) = True
    is_triv_pat (ParPat p)  = is_triv_lpat p
    is_triv_pat _           = False

\end{code}

Creating tuples and their types for full Haskell expressions

\begin{code}

-- Smart constructors for source tuple expressions
mkLHsVarTup :: [Id] -> LHsExpr Id
mkLHsVarTup ids  = mkLHsTup (map nlHsVar ids)

mkLHsTup :: [LHsExpr Id] -> LHsExpr Id
mkLHsTup []     = nlHsVar unitDataConId
mkLHsTup [lexp] = lexp
mkLHsTup lexps  = L (getLoc (head lexps)) $ 
		  ExplicitTuple lexps Boxed

-- Smart constructors for source tuple patterns
mkLHsVarPatTup :: [Id] -> LPat Id
mkLHsVarPatTup bs  = mkLHsPatTup (map nlVarPat bs)

mkLHsPatTup :: [LPat Id] -> LPat Id
mkLHsPatTup []     = noLoc $ mkVanillaTuplePat [] Boxed
mkLHsPatTup [lpat] = lpat
mkLHsPatTup lpats  = L (getLoc (head lpats)) $ 
		     mkVanillaTuplePat lpats Boxed

-- The Big equivalents for the source tuple expressions
mkBigLHsVarTup :: [Id] -> LHsExpr Id
mkBigLHsVarTup ids = mkBigLHsTup (map nlHsVar ids)

mkBigLHsTup :: [LHsExpr Id] -> LHsExpr Id
mkBigLHsTup = mkChunkified mkLHsTup


-- The Big equivalents for the source tuple patterns
mkBigLHsVarPatTup :: [Id] -> LPat Id
mkBigLHsVarPatTup bs = mkBigLHsPatTup (map nlVarPat bs)

mkBigLHsPatTup :: [LPat Id] -> LPat Id
mkBigLHsPatTup = mkChunkified mkLHsPatTup
\end{code}

%************************************************************************
%*									*
\subsection[mkFailurePair]{Code for pattern-matching and other failures}
%*									*
%************************************************************************

Generally, we handle pattern matching failure like this: let-bind a
fail-variable, and use that variable if the thing fails:
\begin{verbatim}
	let fail.33 = error "Help"
	in
	case x of
		p1 -> ...
		p2 -> fail.33
		p3 -> fail.33
		p4 -> ...
\end{verbatim}
Then
\begin{itemize}
\item
If the case can't fail, then there'll be no mention of @fail.33@, and the
simplifier will later discard it.

\item
If it can fail in only one way, then the simplifier will inline it.

\item
Only if it is used more than once will the let-binding remain.
\end{itemize}

There's a problem when the result of the case expression is of
unboxed type.  Then the type of @fail.33@ is unboxed too, and
there is every chance that someone will change the let into a case:
\begin{verbatim}
	case error "Help" of
	  fail.33 -> case ....
\end{verbatim}

which is of course utterly wrong.  Rather than drop the condition that
only boxed types can be let-bound, we just turn the fail into a function
for the primitive case:
\begin{verbatim}
	let fail.33 :: Void -> Int#
	    fail.33 = \_ -> error "Help"
	in
	case x of
		p1 -> ...
		p2 -> fail.33 void
		p3 -> fail.33 void
		p4 -> ...
\end{verbatim}

Now @fail.33@ is a function, so it can be let-bound.

\begin{code}
mkFailurePair :: CoreExpr	-- Result type of the whole case expression
	      -> DsM (CoreBind,	-- Binds the newly-created fail variable
				-- to either the expression or \ _ -> expression
		      CoreExpr)	-- Either the fail variable, or fail variable
				-- applied to unit tuple
mkFailurePair expr
  | isUnLiftedType ty = do
     fail_fun_var <- newFailLocalDs (unitTy `mkFunTy` ty)
     fail_fun_arg <- newSysLocalDs unitTy
     return (NonRec fail_fun_var (Lam fail_fun_arg expr),
             App (Var fail_fun_var) (Var unitDataConId))

  | otherwise = do
     fail_var <- newFailLocalDs ty
     return (NonRec fail_var expr, Var fail_var)
  where
    ty = exprType expr
\end{code}

\begin{code}
mkOptTickBox :: Maybe (Int,[Id]) -> CoreExpr -> DsM CoreExpr
mkOptTickBox Nothing e   = return e
mkOptTickBox (Just (ix,ids)) e = mkTickBox ix ids e

mkTickBox :: Int -> [Id] -> CoreExpr -> DsM CoreExpr
mkTickBox ix vars e = do
       uq <- newUnique 	
       mod <- getModuleDs
       let tick | opt_Hpc   = mkTickBoxOpId uq mod ix
                | otherwise = mkBreakPointOpId uq mod ix
       uq2 <- newUnique 	
       let occName = mkVarOcc "tick"
       let name = mkInternalName uq2 occName noSrcSpan   -- use mkSysLocal?
       let var  = Id.mkLocalId name realWorldStatePrimTy
       scrut <- 
          if opt_Hpc 
            then return (Var tick)
            else do
              let tickVar = Var tick
              let tickType = mkFunTys (map idType vars) realWorldStatePrimTy 
              let scrutApTy = App tickVar (Type tickType)
              return (mkApps scrutApTy (map Var vars) :: Expr Id)
       return $ Case scrut var ty [(DEFAULT,[],e)]
  where
     ty = exprType e

mkBinaryTickBox :: Int -> Int -> CoreExpr -> DsM CoreExpr
mkBinaryTickBox ixT ixF e = do
       uq <- newUnique 	
       let bndr1 = mkSysLocal (fsLit "t1") uq boolTy 
       falseBox <- mkTickBox ixF [] $ Var falseDataConId
       trueBox  <- mkTickBox ixT [] $ Var trueDataConId
       return $ Case e bndr1 boolTy
                       [ (DataAlt falseDataCon, [], falseBox)
                       , (DataAlt trueDataCon,  [], trueBox)
                       ]
\end{code}