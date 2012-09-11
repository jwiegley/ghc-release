%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

TcMatches: Typecheck some @Matches@

\begin{code}
module TcMatches ( tcMatchesFun, tcGRHSsPat, tcMatchesCase, tcMatchLambda,
		   TcMatchCtxt(..), 
		   tcStmts, tcDoStmts, tcBody,
		   tcDoStmt, tcMDoStmt, tcGuardStmt
       ) where

import {-# SOURCE #-}	TcExpr( tcSyntaxOp, tcInferRhoNC, 
                                tcMonoExpr, tcMonoExprNC, tcPolyExpr )

import HsSyn
import TcRnMonad
import Inst
import TcEnv
import TcPat
import TcMType
import TcType
import TcBinds
import TcUnify
import TcSimplify
import MkCore
import Name
import TysWiredIn
import PrelNames
import Id
import TyCon
import TysPrim
import Outputable
import Util
import SrcLoc
import FastString

import Control.Monad

#include "HsVersions.h"
\end{code}

%************************************************************************
%*									*
\subsection{tcMatchesFun, tcMatchesCase}
%*									*
%************************************************************************

@tcMatchesFun@ typechecks a @[Match]@ list which occurs in a
@FunMonoBind@.  The second argument is the name of the function, which
is used in error messages.  It checks that all the equations have the
same number of arguments before using @tcMatches@ to do the work.

\begin{code}
tcMatchesFun :: Name -> Bool
	     -> MatchGroup Name
	     -> BoxyRhoType 		-- Expected type of function
	     -> TcM (HsWrapper, MatchGroup TcId)	-- Returns type of body

tcMatchesFun fun_name inf matches exp_ty
  = do	{  -- Check that they all have the same no of arguments
	   -- Location is in the monad, set the caller so that 
	   -- any inter-equation error messages get some vaguely
	   -- sensible location.	Note: we have to do this odd
	   -- ann-grabbing, because we don't always have annotations in
	   -- hand when we call tcMatchesFun...
	  checkArgs fun_name matches

	-- ToDo: Don't use "expected" stuff if there ain't a type signature
	-- because inconsistency between branches
	-- may show up as something wrong with the (non-existent) type signature

		-- This is one of two places places we call subFunTys
		-- The point is that if expected_y is a "hole", we want 
		-- to make pat_tys and rhs_ty as "holes" too.
	; subFunTys doc n_pats exp_ty (Just (FunSigCtxt fun_name)) $ \ pat_tys rhs_ty -> 
	  tcMatches match_ctxt pat_tys rhs_ty matches
	}
  where
    doc = ptext (sLit "The equation(s) for") <+> quotes (ppr fun_name)
	  <+> ptext (sLit "have") <+> speakNOf n_pats (ptext (sLit "argument"))
    n_pats = matchGroupArity matches
    match_ctxt = MC { mc_what = FunRhs fun_name inf, mc_body = tcBody }
\end{code}

@tcMatchesCase@ doesn't do the argument-count check because the
parser guarantees that each equation has exactly one argument.

\begin{code}
tcMatchesCase :: TcMatchCtxt		-- Case context
	      -> TcRhoType		-- Type of scrutinee
	      -> MatchGroup Name	-- The case alternatives
	      -> BoxyRhoType 		-- Type of whole case expressions
	      -> TcM (MatchGroup TcId)	-- Translated alternatives

tcMatchesCase ctxt scrut_ty matches res_ty
  | isEmptyMatchGroup matches
  =	  -- Allow empty case expressions
    do {  -- Make sure we follow the invariant that res_ty is filled in
          res_ty' <- refineBoxToTau res_ty
       ;  return (MatchGroup [] (mkFunTys [scrut_ty] res_ty')) }

  | otherwise
  = tcMatches ctxt [scrut_ty] res_ty matches

tcMatchLambda :: MatchGroup Name -> BoxyRhoType -> TcM (HsWrapper, MatchGroup TcId)
tcMatchLambda match res_ty 
  = subFunTys doc n_pats res_ty Nothing	$ \ pat_tys rhs_ty ->
    tcMatches match_ctxt pat_tys rhs_ty match
  where
    n_pats = matchGroupArity match
    doc = sep [ ptext (sLit "The lambda expression")
		 <+> quotes (pprSetDepth (PartWay 1) $ 
                             pprMatches (LambdaExpr :: HsMatchContext Name) match),
			-- The pprSetDepth makes the abstraction print briefly
		ptext (sLit "has") <+> speakNOf n_pats (ptext (sLit "argument"))]
    match_ctxt = MC { mc_what = LambdaExpr,
		      mc_body = tcBody }
\end{code}

@tcGRHSsPat@ typechecks @[GRHSs]@ that occur in a @PatMonoBind@.

\begin{code}
tcGRHSsPat :: GRHSs Name -> BoxyRhoType -> TcM (GRHSs TcId)
-- Used for pattern bindings
tcGRHSsPat grhss res_ty = tcGRHSs match_ctxt grhss res_ty
  where
    match_ctxt = MC { mc_what = PatBindRhs,
		      mc_body = tcBody }
\end{code}


%************************************************************************
%*									*
\subsection{tcMatch}
%*									*
%************************************************************************

\begin{code}
tcMatches :: TcMatchCtxt
	  -> [BoxySigmaType] 		-- Expected pattern types
	  -> BoxyRhoType		-- Expected result-type of the Match.
	  -> MatchGroup Name
	  -> TcM (MatchGroup TcId)

data TcMatchCtxt 	-- c.f. TcStmtCtxt, also in this module
  = MC { mc_what :: HsMatchContext Name,	-- What kind of thing this is
    	 mc_body :: LHsExpr Name 		-- Type checker for a body of
                                                -- an alternative
		 -> BoxyRhoType
		 -> TcM (LHsExpr TcId) }	

tcMatches ctxt pat_tys rhs_ty (MatchGroup matches _)
  = ASSERT( not (null matches) )	-- Ensure that rhs_ty is filled in
    do	{ matches' <- mapM (tcMatch ctxt pat_tys rhs_ty) matches
	; return (MatchGroup matches' (mkFunTys pat_tys rhs_ty)) }

-------------
tcMatch :: TcMatchCtxt
	-> [BoxySigmaType]	-- Expected pattern types
	-> BoxyRhoType	 	-- Expected result-type of the Match.
	-> LMatch Name
	-> TcM (LMatch TcId)

tcMatch ctxt pat_tys rhs_ty match 
  = wrapLocM (tc_match ctxt pat_tys rhs_ty) match
  where
    tc_match ctxt pat_tys rhs_ty match@(Match pats maybe_rhs_sig grhss)
      = add_match_ctxt match $
        do { (pats', grhss') <- tcPats (mc_what ctxt) pats pat_tys rhs_ty $
    			        tc_grhss ctxt maybe_rhs_sig grhss
	   ; return (Match pats' Nothing grhss') }

    tc_grhss ctxt Nothing grhss rhs_ty 
      = tcGRHSs ctxt grhss rhs_ty	-- No result signature

	-- Result type sigs are no longer supported
    tc_grhss _ (Just {}) _ _
      = panic "tc_ghrss"  	-- Rejected by renamer

	-- For (\x -> e), tcExpr has already said "In the expresssion \x->e"
	-- so we don't want to add "In the lambda abstraction \x->e"
    add_match_ctxt match thing_inside
	= case mc_what ctxt of
	    LambdaExpr -> thing_inside
	    m_ctxt     -> addErrCtxt (pprMatchInCtxt m_ctxt match) thing_inside

-------------
tcGRHSs :: TcMatchCtxt -> GRHSs Name -> BoxyRhoType
	-> TcM (GRHSs TcId)

-- Notice that we pass in the full res_ty, so that we get
-- good inference from simple things like
--	f = \(x::forall a.a->a) -> <stuff>
-- We used to force it to be a monotype when there was more than one guard
-- but we don't need to do that any more

tcGRHSs ctxt (GRHSs grhss binds) res_ty
  = do	{ (binds', grhss') <- tcLocalBinds binds $
			      mapM (wrapLocM (tcGRHS ctxt res_ty)) grhss

	; return (GRHSs grhss' binds') }

-------------
tcGRHS :: TcMatchCtxt -> BoxyRhoType -> GRHS Name -> TcM (GRHS TcId)

tcGRHS ctxt res_ty (GRHS guards rhs)
  = do  { (guards', rhs') <- tcStmts stmt_ctxt tcGuardStmt guards res_ty $
			     mc_body ctxt rhs
	; return (GRHS guards' rhs') }
  where
    stmt_ctxt  = PatGuard (mc_what ctxt)
\end{code}


%************************************************************************
%*									*
\subsection{@tcDoStmts@ typechecks a {\em list} of do statements}
%*									*
%************************************************************************

\begin{code}
tcDoStmts :: HsStmtContext Name 
	  -> [LStmt Name]
	  -> LHsExpr Name
	  -> BoxyRhoType
	  -> TcM (HsExpr TcId)		-- Returns a HsDo
tcDoStmts ListComp stmts body res_ty
  = do	{ (elt_ty, coi) <- boxySplitListTy res_ty
	; (stmts', body') <- tcStmts ListComp (tcLcStmt listTyCon) stmts 
				     elt_ty $
			     tcBody body
	; return $ mkHsWrapCoI coi 
                     (HsDo ListComp stmts' body' (mkListTy elt_ty)) }

tcDoStmts PArrComp stmts body res_ty
  = do	{ (elt_ty, coi) <- boxySplitPArrTy res_ty
	; (stmts', body') <- tcStmts PArrComp (tcLcStmt parrTyCon) stmts 
				     elt_ty $
			     tcBody body
	; return $ mkHsWrapCoI coi 
                     (HsDo PArrComp stmts' body' (mkPArrTy elt_ty)) }

tcDoStmts DoExpr stmts body res_ty
  = do	{ (stmts', body') <- tcStmts DoExpr tcDoStmt stmts res_ty $
			     tcBody body
	; return (HsDo DoExpr stmts' body' res_ty) }

tcDoStmts ctxt@(MDoExpr _) stmts body res_ty
  = do	{ ((m_ty, elt_ty), coi) <- boxySplitAppTy res_ty
 	; let res_ty' = mkAppTy m_ty elt_ty	-- The boxySplit consumes res_ty
	      tc_rhs rhs = withBox liftedTypeKind $ \ pat_ty ->
			   tcMonoExpr rhs (mkAppTy m_ty pat_ty)

	; (stmts', body') <- tcStmts ctxt (tcMDoStmt tc_rhs) stmts 
				     res_ty' $
			     tcBody body

	; let names = [mfixName, bindMName, thenMName, returnMName, failMName]
	; insts <- mapM (newMethodFromName DoOrigin m_ty) names
	; return $ 
            mkHsWrapCoI coi 
              (HsDo (MDoExpr (names `zip` insts)) stmts' body' res_ty') }

tcDoStmts ctxt _ _ _ = pprPanic "tcDoStmts" (pprStmtContext ctxt)

tcBody :: LHsExpr Name -> BoxyRhoType -> TcM (LHsExpr TcId)
tcBody body res_ty
  = do	{ traceTc (text "tcBody" <+> ppr res_ty)
	; body' <- tcMonoExpr body res_ty
	; return body' 
        } 
\end{code}


%************************************************************************
%*									*
\subsection{tcStmts}
%*									*
%************************************************************************

\begin{code}
type TcStmtChecker
  =  forall thing. HsStmtContext Name
        	-> Stmt Name
		-> BoxyRhoType			-- Result type for comprehension
	      	-> (BoxyRhoType -> TcM thing)	-- Checker for what follows the stmt
              	-> TcM (Stmt TcId, thing)

tcStmts :: HsStmtContext Name
	-> TcStmtChecker	-- NB: higher-rank type
        -> [LStmt Name]
	-> BoxyRhoType
	-> (BoxyRhoType -> TcM thing)
        -> TcM ([LStmt TcId], thing)

-- Note the higher-rank type.  stmt_chk is applied at different
-- types in the equations for tcStmts

tcStmts _ _ [] res_ty thing_inside
  = do	{ thing <- thing_inside res_ty
	; return ([], thing) }

-- LetStmts are handled uniformly, regardless of context
tcStmts ctxt stmt_chk (L loc (LetStmt binds) : stmts) res_ty thing_inside
  = do	{ (binds', (stmts',thing)) <- tcLocalBinds binds $
				      tcStmts ctxt stmt_chk stmts res_ty thing_inside
	; return (L loc (LetStmt binds') : stmts', thing) }

-- For the vanilla case, handle the location-setting part
tcStmts ctxt stmt_chk (L loc stmt : stmts) res_ty thing_inside
  = do 	{ (stmt', (stmts', thing)) <- 
		setSrcSpan loc		 		$
    		addErrCtxt (pprStmtInCtxt ctxt stmt)	$
		stmt_chk ctxt stmt res_ty		$ \ res_ty' ->
		popErrCtxt 				$
		tcStmts ctxt stmt_chk stmts res_ty'	$
		thing_inside
	; return (L loc stmt' : stmts', thing) }

--------------------------------
--	Pattern guards
tcGuardStmt :: TcStmtChecker
tcGuardStmt _ (ExprStmt guard _ _) res_ty thing_inside
  = do	{ guard' <- tcMonoExpr guard boolTy
	; thing  <- thing_inside res_ty
	; return (ExprStmt guard' noSyntaxExpr boolTy, thing) }

tcGuardStmt ctxt (BindStmt pat rhs _ _) res_ty thing_inside
  = do	{ (rhs', rhs_ty) <- tcInferRhoNC rhs	-- Stmt has a context already
	; (pat', thing)  <- tcPat (StmtCtxt ctxt) pat rhs_ty res_ty thing_inside
	; return (BindStmt pat' rhs' noSyntaxExpr noSyntaxExpr, thing) }

tcGuardStmt _ stmt _ _
  = pprPanic "tcGuardStmt: unexpected Stmt" (ppr stmt)


--------------------------------
--	List comprehensions and PArrays

tcLcStmt :: TyCon	-- The list/Parray type constructor ([] or PArray)
	 -> TcStmtChecker

-- A generator, pat <- rhs
tcLcStmt m_tc ctxt (BindStmt pat rhs _ _) res_ty thing_inside
 = do	{ (rhs', pat_ty) <- withBox liftedTypeKind $ \ ty ->
			    tcMonoExpr rhs (mkTyConApp m_tc [ty])
	; (pat', thing)  <- tcPat (StmtCtxt ctxt) pat pat_ty res_ty thing_inside
	; return (BindStmt pat' rhs' noSyntaxExpr noSyntaxExpr, thing) }

-- A boolean guard
tcLcStmt _ _ (ExprStmt rhs _ _) res_ty thing_inside
  = do	{ rhs'  <- tcMonoExpr rhs boolTy
	; thing <- thing_inside res_ty
	; return (ExprStmt rhs' noSyntaxExpr boolTy, thing) }

-- A parallel set of comprehensions
--	[ (g x, h x) | ... ; let g v = ...
--		     | ... ; let h v = ... ]
--
-- It's possible that g,h are overloaded, so we need to feed the LIE from the
-- (g x, h x) up through both lots of bindings (so we get the bindInstsOfLocalFuns).
-- Similarly if we had an existential pattern match:
--
--	data T = forall a. Show a => C a
--
--	[ (show x, show y) | ... ; C x <- ...
--			   | ... ; C y <- ... ]
--
-- Then we need the LIE from (show x, show y) to be simplified against
-- the bindings for x and y.  
-- 
-- It's difficult to do this in parallel, so we rely on the renamer to 
-- ensure that g,h and x,y don't duplicate, and simply grow the environment.
-- So the binders of the first parallel group will be in scope in the second
-- group.  But that's fine; there's no shadowing to worry about.

tcLcStmt m_tc ctxt (ParStmt bndr_stmts_s) elt_ty thing_inside
  = do	{ (pairs', thing) <- loop bndr_stmts_s
	; return (ParStmt pairs', thing) }
  where
    -- loop :: [([LStmt Name], [Name])] -> TcM ([([LStmt TcId], [TcId])], thing)
    loop [] = do { thing <- thing_inside elt_ty
		 ; return ([], thing) }		-- matching in the branches

    loop ((stmts, names) : pairs)
      = do { (stmts', (ids, pairs', thing))
		<- tcStmts ctxt (tcLcStmt m_tc) stmts elt_ty $ \ _elt_ty' ->
		   do { ids <- tcLookupLocalIds names
		      ; (pairs', thing) <- loop pairs
		      ; return (ids, pairs', thing) }
	   ; return ( (stmts', ids) : pairs', thing ) }

tcLcStmt m_tc ctxt (TransformStmt (stmts, binders) usingExpr maybeByExpr) elt_ty thing_inside = do
    (stmts', (binders', usingExpr', maybeByExpr', thing)) <- 
        tcStmts (TransformStmtCtxt ctxt) (tcLcStmt m_tc) stmts elt_ty $ \elt_ty' -> do
            let alphaListTy = mkTyConApp m_tc [alphaTy]
                    
            (usingExpr', maybeByExpr') <- 
                case maybeByExpr of
                    Nothing -> do
                        -- We must validate that usingExpr :: forall a. [a] -> [a]
                        usingExpr' <- tcPolyExpr usingExpr (mkForAllTy alphaTyVar (alphaListTy `mkFunTy` alphaListTy))
                        return (usingExpr', Nothing)
                    Just byExpr -> do
                        -- We must infer a type such that e :: t and then check that usingExpr :: forall a. (a -> t) -> [a] -> [a]
                        (byExpr', tTy) <- tcInferRhoNC byExpr
                        usingExpr' <- tcPolyExpr usingExpr (mkForAllTy alphaTyVar ((alphaTy `mkFunTy` tTy) `mkFunTy` (alphaListTy `mkFunTy` alphaListTy)))
                        return (usingExpr', Just byExpr')
            
            binders' <- tcLookupLocalIds binders
            thing <- thing_inside elt_ty'
            
            return (binders', usingExpr', maybeByExpr', thing)

    return (TransformStmt (stmts', binders') usingExpr' maybeByExpr', thing)

tcLcStmt m_tc ctxt (GroupStmt (stmts, bindersMap) groupByClause) elt_ty thing_inside = do
        (stmts', (bindersMap', groupByClause', thing)) <-
            tcStmts (TransformStmtCtxt ctxt) (tcLcStmt m_tc) stmts elt_ty $ \elt_ty' -> do
                let alphaListTy = mkTyConApp m_tc [alphaTy]
                    alphaListListTy = mkTyConApp m_tc [alphaListTy]
            
                groupByClause' <- 
                    case groupByClause of
                        GroupByNothing usingExpr ->
                            -- We must validate that usingExpr :: forall a. [a] -> [[a]]
                            tcPolyExpr usingExpr (mkForAllTy alphaTyVar (alphaListTy `mkFunTy` alphaListListTy)) >>= (return . GroupByNothing)
                        GroupBySomething eitherUsingExpr byExpr -> do
                            -- We must infer a type such that byExpr :: t
                            (byExpr', tTy) <- tcInferRhoNC byExpr
                            
                            -- If it exists, we then check that usingExpr :: forall a. (a -> t) -> [a] -> [[a]]
                            let expectedUsingType = mkForAllTy alphaTyVar ((alphaTy `mkFunTy` tTy) `mkFunTy` (alphaListTy `mkFunTy` alphaListListTy))
                            eitherUsingExpr' <- 
                                case eitherUsingExpr of
                                    Left usingExpr  -> (tcPolyExpr usingExpr expectedUsingType) >>= (return . Left)
                                    Right usingExpr -> (tcPolyExpr (noLoc usingExpr) expectedUsingType) >>= (return . Right . unLoc)
                            return $ GroupBySomething eitherUsingExpr' byExpr'
            
                -- Find the IDs and types of all old binders
                let (oldBinders, newBinders) = unzip bindersMap
                oldBinders' <- tcLookupLocalIds oldBinders
                
                -- Ensure that every old binder of type b is linked up with its new binder which should have type [b]
                let newBinders' = zipWith associateNewBinder oldBinders' newBinders
            
                -- Type check the thing in the environment with these new binders and return the result
                thing <- tcExtendIdEnv newBinders' (thing_inside elt_ty')
                return (zipEqual "tcLcStmt: Old and new binder lists were not of the same length" oldBinders' newBinders', groupByClause', thing)
        
        return (GroupStmt (stmts', bindersMap') groupByClause', thing)
    where
        associateNewBinder :: TcId -> Name -> TcId
        associateNewBinder oldBinder newBinder = mkLocalId newBinder (mkTyConApp m_tc [idType oldBinder])
    
tcLcStmt _ _ stmt _ _
  = pprPanic "tcLcStmt: unexpected Stmt" (ppr stmt)
        
--------------------------------
--	Do-notation
-- The main excitement here is dealing with rebindable syntax

tcDoStmt :: TcStmtChecker

tcDoStmt ctxt (BindStmt pat rhs bind_op fail_op) res_ty thing_inside
  = do	{ 	-- Deal with rebindable syntax:
		--	 (>>=) :: rhs_ty -> (pat_ty -> new_res_ty) -> res_ty
		-- This level of generality is needed for using do-notation
		-- in full generality; see Trac #1537

		-- I'd like to put this *after* the tcSyntaxOp 
                -- (see Note [Treat rebindable syntax first], but that breaks 
		-- the rigidity info for GADTs.  When we move to the new story
                -- for GADTs, we can move this after tcSyntaxOp
          (rhs', rhs_ty) <- tcInferRhoNC rhs

	; ((bind_op', new_res_ty), pat_ty) <- 
	     withBox liftedTypeKind $ \ pat_ty ->
	     withBox liftedTypeKind $ \ new_res_ty ->
	     tcSyntaxOp DoOrigin bind_op 
			     (mkFunTys [rhs_ty, mkFunTy pat_ty new_res_ty] res_ty)

		-- If (but only if) the pattern can fail, 
		-- typecheck the 'fail' operator
	; fail_op' <- if isIrrefutableHsPat pat 
		      then return noSyntaxExpr
		      else tcSyntaxOp DoOrigin fail_op (mkFunTy stringTy new_res_ty)

		-- We should typecheck the RHS *before* the pattern,
                -- because of GADTs. 
		-- 	do { pat <- rhs; <rest> }
		-- is rather like
		--	case rhs of { pat -> <rest> }
		-- We do inference on rhs, so that information about its type 
                -- can be refined when type-checking the pattern. 

	; (pat', thing) <- tcPat (StmtCtxt ctxt) pat pat_ty new_res_ty thing_inside

	; return (BindStmt pat' rhs' bind_op' fail_op', thing) }


tcDoStmt _ (ExprStmt rhs then_op _) res_ty thing_inside
  = do	{   	-- Deal with rebindable syntax; 
                --   (>>) :: rhs_ty -> new_res_ty -> res_ty
		-- See also Note [Treat rebindable syntax first]
	  ((then_op', rhs_ty), new_res_ty) <-
		withBox liftedTypeKind $ \ new_res_ty ->
		withBox liftedTypeKind $ \ rhs_ty ->
		tcSyntaxOp DoOrigin then_op 
			   (mkFunTys [rhs_ty, new_res_ty] res_ty)

        ; rhs' <- tcMonoExprNC rhs rhs_ty
	; thing <- thing_inside new_res_ty
	; return (ExprStmt rhs' then_op' rhs_ty, thing) }

tcDoStmt ctxt (RecStmt { recS_stmts = stmts, recS_later_ids = later_names
                       , recS_rec_ids = rec_names, recS_ret_fn = ret_op
                       , recS_mfix_fn = mfix_op, recS_bind_fn = bind_op }) 
         res_ty thing_inside
  = do  { let tup_names = rec_names ++ filterOut (`elem` rec_names) later_names
        ; tup_elt_tys <- newFlexiTyVarTys (length tup_names) liftedTypeKind
        ; let tup_ids = zipWith mkLocalId tup_names tup_elt_tys
	      tup_ty  = mkCoreTupTy tup_elt_tys

        ; tcExtendIdEnv tup_ids $ do
        { ((stmts', (ret_op', tup_rets)), stmts_ty)
                <- withBox liftedTypeKind $ \ stmts_ty ->
                   tcStmts ctxt tcDoStmt stmts stmts_ty   $ \ inner_res_ty ->
                   do { tup_rets <- zipWithM tc_ret tup_names tup_elt_tys
		      ; ret_op' <- tcSyntaxOp DoOrigin ret_op (mkFunTy tup_ty inner_res_ty)
                      ; return (ret_op', tup_rets) }

	; (mfix_op', mfix_res_ty) <- withBox liftedTypeKind $ \ mfix_res_ty ->
                                     tcSyntaxOp DoOrigin mfix_op
                                        (mkFunTy (mkFunTy tup_ty stmts_ty) mfix_res_ty)

	; (bind_op', new_res_ty) <- withBox liftedTypeKind $ \ new_res_ty ->
				    tcSyntaxOp DoOrigin bind_op 
			                (mkFunTys [mfix_res_ty, mkFunTy tup_ty new_res_ty] res_ty)

        ; (thing,lie) <- getLIE (thing_inside new_res_ty)
        ; lie_binds <- bindInstsOfLocalFuns lie tup_ids
  
        ; let rec_ids = takeList rec_names tup_ids
	; later_ids <- tcLookupLocalIds later_names
	; traceTc (text "tcdo" <+> vcat [ppr rec_ids <+> ppr (map idType rec_ids),
                                         ppr later_ids <+> ppr (map idType later_ids)])
        ; return (RecStmt { recS_stmts = stmts', recS_later_ids = later_ids
                          , recS_rec_ids = rec_ids, recS_ret_fn = ret_op' 
                          , recS_mfix_fn = mfix_op', recS_bind_fn = bind_op'
                          , recS_rec_rets = tup_rets, recS_dicts = lie_binds }, thing)
        }}
  where 
    -- Unify the types of the "final" Ids with those of "knot-tied" Ids
    tc_ret rec_name mono_ty
        = do { poly_id <- tcLookupId rec_name
                -- poly_id may have a polymorphic type
                -- but mono_ty is just a monomorphic type variable
             ; co_fn <- tcSubExp DoOrigin (idType poly_id) mono_ty
             ; return (mkHsWrap co_fn (HsVar poly_id)) }

tcDoStmt _ stmt _ _
  = pprPanic "tcDoStmt: unexpected Stmt" (ppr stmt)
\end{code}

Note [Treat rebindable syntax first]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
When typechecking
	do { bar; ... } :: IO ()
we want to typecheck 'bar' in the knowledge that it should be an IO thing,
pushing info from the context into the RHS.  To do this, we check the
rebindable syntax first, and push that information into (tcMonoExprNC rhs).
Otherwise the error shows up when cheking the rebindable syntax, and
the expected/inferred stuff is back to front (see Trac #3613).

\begin{code}
--------------------------------
--	Mdo-notation
-- The distinctive features here are
--	(a) RecStmts, and
--	(b) no rebindable syntax

tcMDoStmt :: (LHsExpr Name -> TcM (LHsExpr TcId, TcType))	-- RHS inference
	  -> TcStmtChecker
tcMDoStmt tc_rhs ctxt (BindStmt pat rhs _ _) res_ty thing_inside
  = do	{ (rhs', pat_ty) <- tc_rhs rhs
	; (pat', thing)  <- tcPat (StmtCtxt ctxt) pat pat_ty res_ty thing_inside
	; return (BindStmt pat' rhs' noSyntaxExpr noSyntaxExpr, thing) }

tcMDoStmt tc_rhs _ (ExprStmt rhs _ _) res_ty thing_inside
  = do	{ (rhs', elt_ty) <- tc_rhs rhs
	; thing 	 <- thing_inside res_ty
	; return (ExprStmt rhs' noSyntaxExpr elt_ty, thing) }

tcMDoStmt tc_rhs ctxt (RecStmt stmts laterNames recNames _ _ _ _ _) res_ty thing_inside
  = do	{ rec_tys <- newFlexiTyVarTys (length recNames) liftedTypeKind
	; let rec_ids = zipWith mkLocalId recNames rec_tys
	; tcExtendIdEnv rec_ids			$ do
    	{ (stmts', (later_ids, rec_rets))
		<- tcStmts ctxt (tcMDoStmt tc_rhs) stmts res_ty	$ \ _res_ty' ->
			-- ToDo: res_ty not really right
		   do { rec_rets <- zipWithM tc_ret recNames rec_tys
		      ; later_ids <- tcLookupLocalIds laterNames
		      ; return (later_ids, rec_rets) }

	; (thing,lie) <- tcExtendIdEnv later_ids (getLIE (thing_inside res_ty))
		-- NB:	The rec_ids for the recursive things 
		-- 	already scope over this part. This binding may shadow
		--	some of them with polymorphic things with the same Name
		--	(see note [RecStmt] in HsExpr)
	; lie_binds <- bindInstsOfLocalFuns lie later_ids
  
	; return (RecStmt stmts' later_ids rec_ids noSyntaxExpr noSyntaxExpr noSyntaxExpr rec_rets lie_binds, thing)
	}}
  where 
    -- Unify the types of the "final" Ids with those of "knot-tied" Ids
    tc_ret rec_name mono_ty
	= do { poly_id <- tcLookupId rec_name
		-- poly_id may have a polymorphic type
		-- but mono_ty is just a monomorphic type variable
	     ; co_fn <- tcSubExp DoOrigin (idType poly_id) mono_ty
	     ; return (mkHsWrap co_fn (HsVar poly_id)) }

tcMDoStmt _ _ stmt _ _
  = pprPanic "tcMDoStmt: unexpected Stmt" (ppr stmt)

\end{code}


%************************************************************************
%*									*
\subsection{Errors and contexts}
%*									*
%************************************************************************

@sameNoOfArgs@ takes a @[RenamedMatch]@ and decides whether the same
number of args are used in each equation.

\begin{code}
checkArgs :: Name -> MatchGroup Name -> TcM ()
checkArgs fun (MatchGroup (match1:matches) _)
    | null bad_matches = return ()
    | otherwise
    = failWithTc (vcat [ptext (sLit "Equations for") <+> quotes (ppr fun) <+> 
			  ptext (sLit "have different numbers of arguments"),
			nest 2 (ppr (getLoc match1)),
			nest 2 (ppr (getLoc (head bad_matches)))])
  where
    n_args1 = args_in_match match1
    bad_matches = [m | m <- matches, args_in_match m /= n_args1]

    args_in_match :: LMatch Name -> Int
    args_in_match (L _ (Match pats _ _)) = length pats
checkArgs _ _ = panic "TcPat.checkArgs" -- Matches always non-empty
\end{code}

