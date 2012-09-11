%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

Matching guarded right-hand-sides (GRHSs)

\begin{code}
{-# OPTIONS -fno-warn-incomplete-patterns #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

module DsGRHSs ( dsGuarded, dsGRHSs ) where

#include "HsVersions.h"

import {-# SOURCE #-} DsExpr  ( dsLExpr, dsLocalBinds )
import {-# SOURCE #-} Match   ( matchSinglePat )

import HsSyn
import CoreSyn
import Var
import Type

import DsMonad
import DsUtils
import PrelInfo
import TysWiredIn
import PrelNames
import Name
import SrcLoc

\end{code}

@dsGuarded@ is used for both @case@ expressions and pattern bindings.
It desugars:
\begin{verbatim}
	| g1 -> e1
	...
	| gn -> en
	where binds
\end{verbatim}
producing an expression with a runtime error in the corner if
necessary.  The type argument gives the type of the @ei@.

\begin{code}
dsGuarded :: GRHSs Id -> Type -> DsM CoreExpr

dsGuarded grhss rhs_ty = do
    match_result <- dsGRHSs PatBindRhs [] grhss rhs_ty
    error_expr <- mkErrorAppDs nON_EXHAUSTIVE_GUARDS_ERROR_ID rhs_ty ""
    extractMatchResult match_result error_expr
\end{code}

In contrast, @dsGRHSs@ produces a @MatchResult@.

\begin{code}
dsGRHSs :: HsMatchContext Name -> [Pat Id]	-- These are to build a MatchContext from
	-> GRHSs Id				-- Guarded RHSs
	-> Type					-- Type of RHS
	-> DsM MatchResult
dsGRHSs hs_ctx pats (GRHSs grhss binds) rhs_ty = do
    match_results <- mapM (dsGRHS hs_ctx pats rhs_ty) grhss
    let 
	match_result1 = foldr1 combineMatchResults match_results
	match_result2 = adjustMatchResultDs 
                                 (\e -> dsLocalBinds binds e) 
                                 match_result1
		-- NB: nested dsLet inside matchResult
    --
    return match_result2

dsGRHS :: HsMatchContext Name -> [Pat Id] -> Type -> LGRHS Id -> DsM MatchResult
dsGRHS hs_ctx _ rhs_ty (L _ (GRHS guards rhs))
  = matchGuards (map unLoc guards) hs_ctx rhs rhs_ty
\end{code}


%************************************************************************
%*									*
%*  matchGuard : make a MatchResult from a guarded RHS			*
%*									*
%************************************************************************

\begin{code}
matchGuards :: [Stmt Id] 		-- Guard
            -> HsMatchContext Name	-- Context
	    -> LHsExpr Id		-- RHS
	    -> Type			-- Type of RHS of guard
	    -> DsM MatchResult

-- See comments with HsExpr.Stmt re what an ExprStmt means
-- Here we must be in a guard context (not do-expression, nor list-comp)	

matchGuards [] _ rhs _
  = do	{ core_rhs <- dsLExpr rhs
	; return (cantFailMatchResult core_rhs) }

	-- ExprStmts must be guards
	-- Turn an "otherwise" guard is a no-op.  This ensures that 
	-- you don't get a "non-exhaustive eqns" message when the guards 
	-- finish in "otherwise".
	-- NB:	The success of this clause depends on the typechecker not
	-- 	wrapping the 'otherwise' in empty HsTyApp or HsWrap constructors
	--	If it does, you'll get bogus overlap warnings
matchGuards (ExprStmt e _ _ : stmts) ctx rhs rhs_ty
  | Just addTicks <- isTrueLHsExpr e = do
    match_result <- matchGuards stmts ctx rhs rhs_ty
    return (adjustMatchResultDs addTicks match_result)
matchGuards (ExprStmt expr _ _ : stmts) ctx rhs rhs_ty = do
    match_result <- matchGuards stmts ctx rhs rhs_ty
    pred_expr <- dsLExpr expr
    return (mkGuardedMatchResult pred_expr match_result)

matchGuards (LetStmt binds : stmts) ctx rhs rhs_ty = do
    match_result <- matchGuards stmts ctx rhs rhs_ty
    return (adjustMatchResultDs (dsLocalBinds binds) match_result)
	-- NB the dsLet occurs inside the match_result
	-- Reason: dsLet takes the body expression as its argument
	--	   so we can't desugar the bindings without the
	--	   body expression in hand

matchGuards (BindStmt pat bind_rhs _ _ : stmts) ctx rhs rhs_ty = do
    match_result <- matchGuards stmts ctx rhs rhs_ty
    core_rhs <- dsLExpr bind_rhs
    matchSinglePat core_rhs ctx pat rhs_ty match_result

isTrueLHsExpr :: LHsExpr Id -> Maybe (CoreExpr -> DsM CoreExpr)

-- Returns Just {..} if we're sure that the expression is True
-- I.e.   * 'True' datacon
--	  * 'otherwise' Id
--	  * Trivial wappings of these
-- The arguments to Just are any HsTicks that we have found,
-- because we still want to tick then, even it they are aways evaluted.
isTrueLHsExpr (L _ (HsVar v)) |  v `hasKey` otherwiseIdKey
                              || v `hasKey` getUnique trueDataConId
                                      = Just return
	-- trueDataConId doesn't have the same unique as trueDataCon
isTrueLHsExpr (L _ (HsTick    ix frees e))
    | Just ticks <- isTrueLHsExpr e   = Just (\x -> ticks x >>= mkTickBox ix frees)
   -- This encodes that the result is constant True for Hpc tick purposes;
   -- which is specifically what isTrueLHsExpr is trying to find out.
isTrueLHsExpr (L _ (HsBinTick ixT _ e))
    | Just ticks <- isTrueLHsExpr e   = Just (\x -> ticks x >>= mkTickBox ixT [])
isTrueLHsExpr (L _ (HsPar e))         = isTrueLHsExpr e
isTrueLHsExpr _                       = Nothing
\end{code}

Should {\em fail} if @e@ returns @D@
\begin{verbatim}
f x | p <- e', let C y# = e, f y# = r1
    | otherwise 	 = r2 
\end{verbatim}