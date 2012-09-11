Normalisation of type terms relative to type instances as well as
normalisation and entailment checking of equality constraints.

\begin{code}
module TcTyFuns (
  -- type normalisation wrt to toplevel equalities only
  tcNormaliseFamInst,

  -- instance normalisation wrt to equalities
  tcReduceEqs,

  -- errors
  misMatchMsg, failWithMisMatch,

) where


#include "HsVersions.h"

--friends
import TcRnMonad
import TcEnv
import Inst
import TcType
import TcMType

-- GHC
import Coercion
import Type
import TypeRep 	( Type(..) )
import TyCon
import HsSyn
import VarEnv
import VarSet
import Var
import Name
import Bag
import Outputable
import SrcLoc	( Located(..) )
import Maybes
import FastString

-- standard
import Data.List
import Control.Monad
\end{code}


%************************************************************************
%*									*
		Normalisation of types wrt toplevel equality schemata
%*									*
%************************************************************************

Unfold a single synonym family instance and yield the witnessing coercion.
Return 'Nothing' if the given type is either not synonym family instance
or is a synonym family instance that has no matching instance declaration.
(Applies only if the type family application is outermost.)

For example, if we have

  :Co:R42T a :: T [a] ~ :R42T a

then 'T [Int]' unfolds to (:R42T Int, :Co:R42T Int).

\begin{code}
tcUnfoldSynFamInst :: Type -> TcM (Maybe (Type, Coercion))
tcUnfoldSynFamInst (TyConApp tycon tys)
  | not (isOpenSynTyCon tycon)     -- unfold *only* _synonym_ family instances
  = return Nothing
  | otherwise
  = do { -- we only use the indexing arguments for matching, 
         -- not the additional ones
       ; maybeFamInst <- tcLookupFamInst tycon idxTys
       ; case maybeFamInst of
           Nothing                -> return Nothing
           Just (rep_tc, rep_tys) -> return $ Just (mkTyConApp rep_tc tys',
		                                    mkTyConApp coe_tc tys')
             where
               tys'   = rep_tys ++ restTys
               coe_tc = expectJust "TcTyFuns.tcUnfoldSynFamInst" 
                                   (tyConFamilyCoercion_maybe rep_tc)
       }
    where
        n                = tyConArity tycon
        (idxTys, restTys) = splitAt n tys
tcUnfoldSynFamInst _other = return Nothing
\end{code}

Normalise 'Type's and 'PredType's by unfolding type family applications where
possible (ie, we treat family instances as a TRS).  Also zonk meta variables.

	tcNormaliseFamInst ty = (co, ty')
	then   co : ty ~ ty'

\begin{code}
-- |Normalise the given type as far as possible with toplevel equalities.
-- This results in a coercion witnessing the type equality, in addition to the
-- normalised type.
--
tcNormaliseFamInst :: TcType -> TcM (CoercionI, TcType)
tcNormaliseFamInst = tcGenericNormaliseFamInst tcUnfoldSynFamInst
\end{code}

Generic normalisation of 'Type's and 'PredType's; ie, walk the type term and
apply the normalisation function gives as the first argument to every TyConApp
and every TyVarTy subterm.

	tcGenericNormaliseFamInst fun ty = (co, ty')
	then   co : ty ~ ty'

This function is (by way of using smart constructors) careful to ensure that
the returned coercion is exactly IdCo (and not some semantically equivalent,
but syntactically different coercion) whenever (ty' `tcEqType` ty).  This
makes it easy for the caller to determine whether the type changed.  BUT
even if we return IdCo, ty' may be *syntactically* different from ty due to
unfolded closed type synonyms (by way of tcCoreView).  In the interest of
good error messages, callers should discard ty' in favour of ty in this case.

\begin{code}
tcGenericNormaliseFamInst :: (TcType -> TcM (Maybe (TcType, Coercion))) 	
                             -- what to do with type functions and tyvars
	                   -> TcType  			-- old type
	                   -> TcM (CoercionI, TcType)	-- (coercion, new type)
tcGenericNormaliseFamInst fun ty
  | Just ty' <- tcView ty = tcGenericNormaliseFamInst fun ty' 
tcGenericNormaliseFamInst fun (TyConApp tyCon tys)
  = do	{ (cois, ntys) <- mapAndUnzipM (tcGenericNormaliseFamInst fun) tys
	; let tycon_coi = mkTyConAppCoI tyCon ntys cois
	; maybe_ty_co <- fun (mkTyConApp tyCon ntys)     -- use normalised args!
	; case maybe_ty_co of
	    -- a matching family instance exists
	    Just (ty', co) ->
	      do { let first_coi = mkTransCoI tycon_coi (ACo co)
		 ; (rest_coi, nty) <- tcGenericNormaliseFamInst fun ty'
		 ; let fix_coi = mkTransCoI first_coi rest_coi
	   	 ; return (fix_coi, nty)
		 }
	    -- no matching family instance exists
	    -- we do not do anything
	    Nothing -> return (tycon_coi, mkTyConApp tyCon ntys)
	}
tcGenericNormaliseFamInst fun (AppTy ty1 ty2)
  = do	{ (coi1,nty1) <- tcGenericNormaliseFamInst fun ty1
	; (coi2,nty2) <- tcGenericNormaliseFamInst fun ty2
	; return (mkAppTyCoI nty1 coi1 nty2 coi2, mkAppTy nty1 nty2)
	}
tcGenericNormaliseFamInst fun (FunTy ty1 ty2)
  = do	{ (coi1,nty1) <- tcGenericNormaliseFamInst fun ty1
	; (coi2,nty2) <- tcGenericNormaliseFamInst fun ty2
	; return (mkFunTyCoI nty1 coi1 nty2 coi2, mkFunTy nty1 nty2)
	}
tcGenericNormaliseFamInst fun (ForAllTy tyvar ty1)
  = do 	{ (coi,nty1) <- tcGenericNormaliseFamInst fun ty1
	; return (mkForAllTyCoI tyvar coi, mkForAllTy tyvar nty1)
	}
tcGenericNormaliseFamInst fun ty@(TyVarTy tv)
  | isTcTyVar tv
  = do	{ traceTc (text "tcGenericNormaliseFamInst" <+> ppr ty)
	; res <- lookupTcTyVar tv
	; case res of
	    DoneTv _ -> 
	      do { maybe_ty' <- fun ty
		 ; case maybe_ty' of
		     Nothing	     -> return (IdCo, ty)
		     Just (ty', co1) -> 
                       do { (coi2, ty'') <- tcGenericNormaliseFamInst fun ty'
			  ; return (ACo co1 `mkTransCoI` coi2, ty'') 
			  }
		 }
	    IndirectTv ty' -> tcGenericNormaliseFamInst fun ty' 
	}
  | otherwise
  = return (IdCo, ty)
tcGenericNormaliseFamInst fun (PredTy predty)
  = do 	{ (coi, pred') <- tcGenericNormaliseFamInstPred fun predty
	; return (coi, PredTy pred') }

---------------------------------
tcGenericNormaliseFamInstPred :: (TcType -> TcM (Maybe (TcType,Coercion)))
	                      -> TcPredType
	                      -> TcM (CoercionI, TcPredType)

tcGenericNormaliseFamInstPred fun (ClassP cls tys) 
  = do { (cois, tys')<- mapAndUnzipM (tcGenericNormaliseFamInst fun) tys
       ; return (mkClassPPredCoI cls tys' cois, ClassP cls tys')
       }
tcGenericNormaliseFamInstPred fun (IParam ipn ty) 
  = do { (coi, ty') <- tcGenericNormaliseFamInst fun ty
       ; return $ (mkIParamPredCoI ipn coi, IParam ipn ty')
       }
tcGenericNormaliseFamInstPred fun (EqPred ty1 ty2) 
  = do { (coi1, ty1') <- tcGenericNormaliseFamInst fun ty1
       ; (coi2, ty2') <- tcGenericNormaliseFamInst fun ty2
       ; return (mkEqPredCoI ty1' coi1 ty2' coi2, EqPred ty1' ty2') }
\end{code}


%************************************************************************
%*									*
		Normalisation of instances wrt to equalities
%*									*
%************************************************************************

\begin{code}
tcReduceEqs :: [Inst]             -- locals
            -> [Inst]             -- wanteds
            -> TcM ([Inst],       -- normalised locals (w/o equalities)
                    [Inst],       -- normalised wanteds (including equalities)
                    TcDictBinds,  -- bindings for all simplified dictionaries
                    Bool)         -- whether any flexibles where instantiated
tcReduceEqs locals wanteds
  = do { let (local_eqs  , local_dicts)   = partition isEqInst locals
             (wanteds_eqs, wanteds_dicts) = partition isEqInst wanteds
       ; eqCfg1 <- normaliseEqs (local_eqs ++ wanteds_eqs)
       ; eqCfg2 <- normaliseDicts False local_dicts
       ; eqCfg3 <- normaliseDicts True  wanteds_dicts
       ; eqCfg <- propagateEqs (eqCfg1 `unionEqConfig` eqCfg2 
                                       `unionEqConfig` eqCfg3)
       ; finaliseEqsAndDicts eqCfg
       }
\end{code}


%************************************************************************
%*									*
		Equality Configurations
%*									*
%************************************************************************

We maintain normalised equalities together with the skolems introduced as
intermediates during flattening of equalities as well as 

\begin{code}
-- |Configuration of normalised equalities used during solving.
--
data EqConfig = EqConfig { eqs     :: [RewriteInst]     -- all equalities
                         , locals  :: [Inst]            -- given dicts
                         , wanteds :: [Inst]            -- wanted dicts
                         , binds   :: TcDictBinds       -- bindings
                         , skolems :: TyVarSet          -- flattening skolems
                         }

addSkolems :: EqConfig -> TyVarSet -> EqConfig
addSkolems eqCfg newSkolems 
  = eqCfg {skolems = skolems eqCfg `unionVarSet` newSkolems}

addEq :: EqConfig -> RewriteInst -> EqConfig
addEq eqCfg eq = eqCfg {eqs = eq : eqs eqCfg}

unionEqConfig :: EqConfig -> EqConfig -> EqConfig
unionEqConfig eqc1 eqc2 = EqConfig 
                          { eqs     = eqs eqc1 ++ eqs eqc2
                          , locals  = locals eqc1 ++ locals eqc2
                          , wanteds = wanteds eqc1 ++ wanteds eqc2
                          , binds   = binds eqc1 `unionBags` binds eqc2
                          , skolems = skolems eqc1 `unionVarSet` skolems eqc2
                          }

emptyEqConfig :: EqConfig
emptyEqConfig = EqConfig
                { eqs     = []
                , locals  = []
                , wanteds = []
                , binds   = emptyBag
                , skolems = emptyVarSet
                }

instance Outputable EqConfig where
  ppr (EqConfig {eqs = eqs, locals = locals, wanteds = wanteds, binds = binds})
    = vcat [ppr eqs, ppr locals, ppr wanteds, ppr binds]
\end{code}

The set of operations on an equality configuration.  We obtain the initialise
configuration by normalisation ('normaliseEqs'), solve the equalities by
propagation ('propagateEqs'), and eventually finalise the configuration when
no further propoagation is possible.

\begin{code}
-- |Turn a set of equalities into an equality configuration for solving.
--
-- Precondition: The Insts are zonked.
--
normaliseEqs :: [Inst] -> TcM EqConfig
normaliseEqs eqs 
  = do { ASSERTM2( allM wantedEqInstIsUnsolved eqs, ppr eqs )
       ; traceTc $ ptext (sLit "Entering normaliseEqs")

       ; (eqss, skolemss) <- mapAndUnzipM normEqInst eqs
       ; return $ emptyEqConfig { eqs = concat eqss
                                , skolems = unionVarSets skolemss 
                                }
       }

-- |Flatten the type arguments of all dictionaries, returning the result as a 
-- equality configuration.  The dictionaries go into the 'wanted' component if 
-- the second argument is 'True'.
--
-- Precondition: The Insts are zonked.
--
normaliseDicts :: Bool -> [Inst] -> TcM EqConfig
normaliseDicts isWanted insts
  = do { traceTc $ hang (ptext (sLit "Entering normaliseDicts") <+>
                         ptext (if isWanted then sLit "[Wanted] for" 
                                            else sLit "[Local] for"))
                     4 (ppr insts)
       ; (insts', eqss, bindss, skolemss) <- mapAndUnzip4M (normDict isWanted) 
                                                           insts

       ; traceTc $ hang (ptext (sLit "normaliseDicts returns"))
                     4 (ppr insts' $$ ppr eqss)
       ; return $ emptyEqConfig { eqs     = concat eqss
                                , locals  = if isWanted then [] else insts'
                                , wanteds = if isWanted then insts' else []
                                , binds   = unionManyBags bindss
                                , skolems = unionVarSets skolemss
                                }
       }

-- |Solves the equalities as far as possible by applying propagation rules.
--
propagateEqs :: EqConfig -> TcM EqConfig
propagateEqs eqCfg@(EqConfig {eqs = todoEqs}) 
  = do { traceTc $ hang (ptext (sLit "Entering propagateEqs:"))
                     4 (ppr eqCfg)

       ; propagate todoEqs (eqCfg {eqs = []})
       }

-- |Finalise a set of equalities and associated dictionaries after
-- propagation.  The returned Boolean value is `True' iff any flexible
-- variables, except those introduced by flattening (i.e., those in the
-- `skolems' component of the argument) where instantiated. The first returned
-- set of instances are the locals (without equalities) and the second set are
-- all residual wanteds, including equalities. 
--
finaliseEqsAndDicts :: EqConfig 
                    -> TcM ([Inst], [Inst], TcDictBinds, Bool)
finaliseEqsAndDicts (EqConfig { eqs     = eqs
                              , locals  = locals
                              , wanteds = wanteds
                              , binds   = binds
                              , skolems = skolems
                              })
  = do { traceTc $ ptext (sLit "finaliseEqsAndDicts")
       ; (eqs', subst_binds, locals', wanteds') <- substitute eqs locals wanteds
       ; (eqs'', improved) <- instantiateAndExtract eqs' (null locals) skolems
       ; let final_binds = subst_binds `unionBags` binds

         -- Assert that all cotvs of wanted equalities are still unfilled, and
         -- zonk all final insts, to make any improvement visible
       ; ASSERTM2( allM wantedEqInstIsUnsolved eqs'', ppr eqs'' )
       ; zonked_locals  <- zonkInsts locals'
       ; zonked_wanteds <- zonkInsts (eqs'' ++ wanteds')
       ; return (zonked_locals, zonked_wanteds, final_binds, improved)
       }
\end{code}


%************************************************************************
%*									*
		Normalisation of equalities
%*									*
%************************************************************************

A normal equality is a properly oriented equality with associated coercion
that contains at most one family equality (in its left-hand side) is oriented
such that it may be used as a reqrite rule.  It has one of the following two 
forms:

(1) co :: F t1..tn ~ t  (family equalities)
(2) co :: x ~ t         (variable equalities)

Variable equalities fall again in two classes:

(2a) co :: x ~ t, where t is *not* a variable, or
(2b) co :: x ~ y, where x > y.

The types t, t1, ..., tn may not contain any occurrences of synonym
families.  Moreover, in Forms (2) & (3), the left-hand side may not occur in
the right-hand side, and the relation x > y is an arbitrary, but total order
on type variables

\begin{code}
data RewriteInst
  = RewriteVar  -- Form (2) above
    { rwi_var     :: TyVar    -- may be rigid or flexible
    , rwi_right   :: TcType   -- contains no synonym family applications
    , rwi_co      :: EqInstCo -- the wanted or given coercion
    , rwi_loc     :: InstLoc
    , rwi_name    :: Name     -- no semantic significance (cf. TcRnTypes.EqInst)
    , rwi_swapped :: Bool     -- swapped orientation of original EqInst
    }
  | RewriteFam  -- Forms (1) above
    { rwi_fam     :: TyCon    -- synonym family tycon
    , rwi_args    :: [Type]   -- contain no synonym family applications
    , rwi_right   :: TcType   -- contains no synonym family applications
    , rwi_co      :: EqInstCo -- the wanted or given coercion
    , rwi_loc     :: InstLoc
    , rwi_name    :: Name     -- no semantic significance (cf. TcRnTypes.EqInst)
    , rwi_swapped :: Bool     -- swapped orientation of original EqInst
    }

isWantedRewriteInst :: RewriteInst -> Bool
isWantedRewriteInst = isWantedCo . rwi_co

rewriteInstToInst :: RewriteInst -> TcM Inst
rewriteInstToInst eq@(RewriteVar {rwi_var = tv})
  = deriveEqInst eq (mkTyVarTy tv) (rwi_right eq) (rwi_co eq)
rewriteInstToInst eq@(RewriteFam {rwi_fam = fam, rwi_args = args})
  = deriveEqInst eq (mkTyConApp fam args) (rwi_right eq) (rwi_co eq)

-- Derive an EqInst based from a RewriteInst, possibly swapping the types
-- around. 
--
deriveEqInst :: RewriteInst -> TcType -> TcType -> EqInstCo -> TcM Inst
deriveEqInst rewrite ty1 ty2 co
  = do { co_adjusted <- if not swapped then return co 
                                       else mkSymEqInstCo co (ty2, ty1)
       ; return $ EqInst
                  { tci_left  = left
                  , tci_right = right
                  , tci_co    = co_adjusted
                  , tci_loc   = rwi_loc rewrite
                  , tci_name  = rwi_name rewrite
                  }
       }
  where
    swapped       = rwi_swapped rewrite
    (left, right) = if not swapped then (ty1, ty2) else (ty2, ty1)

instance Outputable RewriteInst where
  ppr (RewriteFam {rwi_fam = fam, rwi_args = args, rwi_right = rhs, rwi_co =co})
    = hsep [ pprEqInstCo co <+> text "::" 
           , ppr (mkTyConApp fam args)
           , text "~>"
           , ppr rhs
           ]
  ppr (RewriteVar {rwi_var = tv, rwi_right = rhs, rwi_co =co})
    = hsep [ pprEqInstCo co <+> text "::" 
           , ppr tv
           , text "~>"
           , ppr rhs
           ]

pprEqInstCo :: EqInstCo -> SDoc
pprEqInstCo (Left cotv) = ptext (sLit "Wanted") <+> ppr cotv
pprEqInstCo (Right co)  = ptext (sLit "Local") <+> ppr co
\end{code}

The following functions turn an arbitrary equality into a set of normal
equalities.  This implements the WFlat and LFlat rules of the paper in one
sweep.  However, we use flexible variables for both locals and wanteds, and
avoid to carry around the unflattening substitution \Sigma (for locals) by
already updating the skolems for locals with the family application that they
represent - i.e., they will turn into that family application on the next
zonking (which only happens after finalisation).

In a corresponding manner, normDict normalises class dictionaries by
extracting any synonym family applications and generation appropriate normal
equalities. 

Whenever we encounter a loopy equality (of the form a ~ T .. (F ...a...) ...),
we drop that equality and raise an error if it is a wanted or a warning if it
is a local.

\begin{code}
normEqInst :: Inst -> TcM ([RewriteInst], TyVarSet)
-- Normalise one equality.
normEqInst inst
  = ASSERT( isEqInst inst )
    do { traceTc $ ptext (sLit "normEqInst of ") <+> 
                   pprEqInstCo co <+> text "::" <+> 
                   ppr ty1 <+> text "~" <+> ppr ty2
       ; res <- go ty1 ty2 co
       ; traceTc $ ptext (sLit "normEqInst returns") <+> ppr res
       ; return res
       }
  where
    (ty1, ty2) = eqInstTys inst
    co         = eqInstCoercion inst

      -- look through synonyms
    go ty1 ty2 co | Just ty1' <- tcView ty1 = go ty1' ty2 co
    go ty1 ty2 co | Just ty2' <- tcView ty2 = go ty1 ty2' co

      -- left-to-right rule with type family head
    go ty1@(TyConApp con args) ty2 co 
      | isOpenSynTyConApp ty1           -- only if not oversaturated
      = mkRewriteFam False con args ty2 co

      -- right-to-left rule with type family head
    go ty1 ty2@(TyConApp con args) co 
      | isOpenSynTyConApp ty2           -- only if not oversaturated
      = do { co' <- mkSymEqInstCo co (ty2, ty1)
           ; mkRewriteFam True con args ty1 co'
           }

      -- no outermost family
    go ty1 ty2 co
      = do { (ty1', co1, ty1_eqs, ty1_skolems) <- flattenType inst ty1
           ; (ty2', co2, ty2_eqs, ty2_skolems) <- flattenType inst ty2
           ; let ty12_eqs  = ty1_eqs ++ ty2_eqs
                 sym_co2   = mkSymCoercion co2
                 eqTys     = (ty1', ty2')
           ; (co', ty12_eqs') <- adjustCoercions co co1 sym_co2 eqTys ty12_eqs
           ; eqs <- checkOrientation ty1' ty2' co' inst
           ; if isLoopyEquality eqs ty12_eqs' 
             then do { if isWantedCo (tci_co inst)
                       then
                          addErrCtxt (ptext (sLit "Rejecting loopy equality")) $
                            eqInstMisMatch inst
                       else
                         warnDroppingLoopyEquality ty1 ty2
                     ; return ([], emptyVarSet)         -- drop the equality
                     }
             else
               return (eqs ++ ty12_eqs',
                      ty1_skolems `unionVarSet` ty2_skolems)
           }

    mkRewriteFam swapped con args ty2 co
      = do { (args', cargs, args_eqss, args_skolemss) 
               <- mapAndUnzip4M (flattenType inst) args
           ; (ty2', co2, ty2_eqs, ty2_skolems) <- flattenType inst ty2
           ; let co1       = mkTyConApp con cargs
                 sym_co2   = mkSymCoercion co2
                 all_eqs   = concat args_eqss ++ ty2_eqs
                 eqTys     = (mkTyConApp con args', ty2')
           ; (co', all_eqs') <- adjustCoercions co co1 sym_co2 eqTys all_eqs
           ; let thisRewriteFam = RewriteFam 
                                  { rwi_fam     = con
                                  , rwi_args    = args'
                                  , rwi_right   = ty2'
                                  , rwi_co      = co'
                                  , rwi_loc     = tci_loc inst
                                  , rwi_name    = tci_name inst
                                  , rwi_swapped = swapped
                                  }
           ; return $ (thisRewriteFam : all_eqs',
                       unionVarSets (ty2_skolems:args_skolemss))
           }

    -- If the original equality has the form a ~ T .. (F ...a...) ..., we will
    -- have a variable equality with 'a' on the lhs as the first equality.
    -- Then, check whether 'a' occurs in the lhs of any family equality
    -- generated by flattening.
    isLoopyEquality (RewriteVar {rwi_var = tv}:_) eqs
      = any inRewriteFam eqs
      where
        inRewriteFam (RewriteFam {rwi_args = args}) 
          = tv `elemVarSet` tyVarsOfTypes args
        inRewriteFam _ = False
    isLoopyEquality _ _ = False

normDict :: Bool -> Inst -> TcM (Inst, [RewriteInst], TcDictBinds, TyVarSet)
-- Normalise one dictionary or IP constraint.
normDict isWanted inst@(Dict {tci_pred = ClassP clas args})
  = do { (args', cargs, args_eqss, args_skolemss) 
           <- mapAndUnzip4M (flattenType inst) args
       ; let rewriteCo = PredTy $ ClassP clas cargs
             eqs       = concat args_eqss
             pred'     = ClassP clas args'
       ; if null eqs
         then  -- don't generate a binding if there is nothing to flatten
           return (inst, [], emptyBag, emptyVarSet)
         else do {
       ; (inst', bind) <- mkDictBind inst isWanted rewriteCo pred'
       ; eqs' <- if isWanted then return eqs else mapM wantedToLocal eqs
       ; return (inst', eqs', bind, unionVarSets args_skolemss)
       }}
normDict _isWanted inst
  = return (inst, [], emptyBag, emptyVarSet)
-- !!!TODO: Still need to normalise IP constraints.

checkOrientation :: Type -> Type -> EqInstCo -> Inst -> TcM [RewriteInst]
-- Performs the occurs check, decomposition, and proper orientation
-- (returns a singleton, or an empty list in case of a trivial equality)
-- NB: We cannot assume that the two types already have outermost type
--     synonyms expanded due to the recursion in the case of type applications.
checkOrientation ty1 ty2 co inst
  = go ty1 ty2
  where
      -- look through synonyms
    go ty1 ty2 | Just ty1' <- tcView ty1 = go ty1' ty2
    go ty1 ty2 | Just ty2' <- tcView ty2 = go ty1 ty2'

      -- identical types => trivial
    go ty1 ty2
      | ty1 `tcEqType` ty2
      = do { mkIdEqInstCo co ty1
           ; return []
           }

      -- two tvs, left greater => unchanged
    go ty1@(TyVarTy tv1) ty2@(TyVarTy tv2)
      | tv1 > tv2
      = mkRewriteVar False tv1 ty2 co

      -- two tvs, right greater => swap
      | otherwise
      = do { co' <- mkSymEqInstCo co (ty2, ty1)
           ; mkRewriteVar True tv2 ty1 co'
           }

      -- only lhs is a tv => unchanged
    go ty1@(TyVarTy tv1) ty2
      | ty1 `tcPartOfType` ty2      -- occurs check!
      = occurCheckErr ty1 ty2
      | otherwise 
      = mkRewriteVar False tv1 ty2 co

      -- only rhs is a tv => swap
    go ty1 ty2@(TyVarTy tv2)
      | ty2 `tcPartOfType` ty1      -- occurs check!
      = occurCheckErr ty2 ty1
      | otherwise 
      = do { co' <- mkSymEqInstCo co (ty2, ty1)
           ; mkRewriteVar True tv2 ty1 co'
           }

      -- type applications => decompose
    go ty1 ty2 
      | Just (ty1_l, ty1_r) <- repSplitAppTy_maybe ty1   -- won't split fam apps
      , Just (ty2_l, ty2_r) <- repSplitAppTy_maybe ty2
      = do { (co_l, co_r) <- mkAppEqInstCo co (ty1_l, ty2_l) (ty1_r, ty2_r)
           ; eqs_l <- checkOrientation ty1_l ty2_l co_l inst
           ; eqs_r <- checkOrientation ty1_r ty2_r co_r inst
           ; return $ eqs_l ++ eqs_r
           }
-- !!!TODO: would be more efficient to handle the FunApp and the data
-- constructor application explicitly.

      -- inconsistency => type error
    go ty1 ty2
      = ASSERT( (not . isForAllTy $ ty1) && (not . isForAllTy $ ty2) )
        eqInstMisMatch inst

    mkRewriteVar swapped tv ty co = return [RewriteVar 
                                            { rwi_var     = tv
                                            , rwi_right   = ty
                                            , rwi_co      = co
                                            , rwi_loc     = tci_loc inst
                                            , rwi_name    = tci_name inst
                                            , rwi_swapped = swapped
                                            }]

flattenType :: Inst     -- context to get location  & name
            -> Type     -- the type to flatten
            -> TcM (Type,           -- the flattened type
                    Coercion,       -- coercion witness of flattening wanteds
                    [RewriteInst],  -- extra equalities
                    TyVarSet)       -- new intermediate skolems
-- Removes all family synonyms from a type by moving them into extra equalities
flattenType inst ty
  = go ty
  where
      -- look through synonyms
    go ty | Just ty' <- tcView ty 
      = do { (ty_flat, co, eqs, skolems) <- go ty'
           ; if null eqs
             then     -- unchanged, keep the old type with folded synonyms
               return (ty, ty, [], emptyVarSet)
             else 
               return (ty_flat, co, eqs, skolems)
           }

      -- type variable => nothing to do
    go ty@(TyVarTy _)
      = return (ty, ty, [] , emptyVarSet)

      -- type family application & family arity matches number of args
      -- => flatten to "gamma :: F t1'..tn' ~ alpha" (alpha & gamma fresh)
    go ty@(TyConApp con args)
      | isOpenSynTyConApp ty   -- only if not oversaturated
      = do { (args', cargs, args_eqss, args_skolemss) <- mapAndUnzip4M go args
           ; alpha <- newFlexiTyVar (typeKind ty)
           ; let alphaTy = mkTyVarTy alpha
           ; cotv <- newMetaCoVar (mkTyConApp con args') alphaTy
           ; let thisRewriteFam = RewriteFam 
                                  { rwi_fam     = con
                                  , rwi_args    = args'
                                  , rwi_right   = alphaTy
                                  , rwi_co      = mkWantedCo cotv
                                  , rwi_loc     = tci_loc inst
                                  , rwi_name    = tci_name inst
                                  , rwi_swapped = True
                                  }
           ; return (alphaTy,
                     mkTyConApp con cargs `mkTransCoercion` mkTyVarTy cotv,
                     thisRewriteFam : concat args_eqss,
                     unionVarSets args_skolemss `extendVarSet` alpha)
           }           -- adding new unflatten var inst

      -- data constructor application => flatten subtypes
      -- NB: Special cased for efficiency - could be handled as type application
    go ty@(TyConApp con args)
      | not (isOpenSynTyCon con)   -- don't match oversaturated family apps
      = do { (args', cargs, args_eqss, args_skolemss) <- mapAndUnzip4M go args
           ; if null args_eqss
             then     -- unchanged, keep the old type with folded synonyms
               return (ty, ty, [], emptyVarSet)
             else 
               return (mkTyConApp con args', 
                       mkTyConApp con cargs,
                       concat args_eqss,
                       unionVarSets args_skolemss)
           }

      -- function type => flatten subtypes
      -- NB: Special cased for efficiency - could be handled as type application
    go ty@(FunTy ty_l ty_r)
      = do { (ty_l', co_l, eqs_l, skolems_l) <- go ty_l
           ; (ty_r', co_r, eqs_r, skolems_r) <- go ty_r
           ; if null eqs_l && null eqs_r
             then     -- unchanged, keep the old type with folded synonyms
               return (ty, ty, [], emptyVarSet)
             else 
               return (mkFunTy ty_l' ty_r', 
                       mkFunTy co_l co_r,
                       eqs_l ++ eqs_r, 
                       skolems_l `unionVarSet` skolems_r)
           }

      -- type application => flatten subtypes
    go ty
      | Just (ty_l, ty_r) <- repSplitAppTy_maybe ty
                             -- need to use the smart split as ty may be an
                             -- oversaturated family application
      = do { (ty_l', co_l, eqs_l, skolems_l) <- go ty_l
           ; (ty_r', co_r, eqs_r, skolems_r) <- go ty_r
           ; if null eqs_l && null eqs_r
             then     -- unchanged, keep the old type with folded synonyms
               return (ty, ty, [], emptyVarSet)
             else 
               return (mkAppTy ty_l' ty_r', 
                       mkAppTy co_l co_r, 
                       eqs_l ++ eqs_r, 
                       skolems_l `unionVarSet` skolems_r)
           }

      -- forall type => panic if the body contains a type family
      -- !!!TODO: As long as the family does not contain a quantified variable
      --          we might pull it out, but what if it does contain a quantified
      --          variable???
    go ty@(ForAllTy _ body)
      | null (tyFamInsts body)
      = return (ty, ty, [] , emptyVarSet)
      | otherwise
      = panic "TcTyFuns.flattenType: synonym family in a rank-n type"

      -- we should never see a predicate type
    go (PredTy _)
      = panic "TcTyFuns.flattenType: unexpected PredType"

    go _ = panic "TcTyFuns: suppress bogus warning"

adjustCoercions :: EqInstCo            -- coercion of original equality
                -> Coercion            -- coercion witnessing the left rewrite
                -> Coercion            -- coercion witnessing the right rewrite
                -> (Type, Type)        -- types of flattened equality
                -> [RewriteInst]       -- equalities from flattening
                -> TcM (EqInstCo,      -- coercion for flattened equality
                        [RewriteInst]) -- final equalities from flattening
-- Depending on whether we flattened a local or wanted equality, that equality's
-- coercion and that of the new equalities produced during flattening are
-- adjusted .
adjustCoercions (Left cotv) co1 co2 (ty_l, ty_r) all_eqs
    -- wanted => generate a fresh coercion variable for the flattened equality
  = do { cotv' <- newMetaCoVar ty_l ty_r
       ; writeMetaTyVar cotv $ 
           (co1 `mkTransCoercion` TyVarTy cotv' `mkTransCoercion` co2)
       ; return (Left cotv', all_eqs)
       }

adjustCoercions co@(Right _) _co1 _co2 _eqTys all_eqs
    -- local => turn all new equalities into locals and update (but not zonk)
    --          the skolem
  = do { all_eqs' <- mapM wantedToLocal all_eqs
       ; return (co, all_eqs')
       }

mkDictBind :: Inst                 -- original instance
           -> Bool                 -- is this a wanted contraint?
           -> Coercion             -- coercion witnessing the rewrite
           -> PredType             -- coerced predicate
           -> TcM (Inst,           -- new inst
                   TcDictBinds)    -- binding for coerced dictionary
mkDictBind dict isWanted rewriteCo pred
  = do { dict' <- newDictBndr loc pred
         -- relate the old inst to the new one
         -- target_dict = source_dict `cast` st_co
       ; let (target_dict, source_dict, st_co) 
               | isWanted  = (dict,  dict', mkSymCoercion rewriteCo)
               | otherwise = (dict', dict,  rewriteCo)
                 -- we have
                 --   co :: dict ~ dict'
                 -- hence, if isWanted
                 -- 	  dict  = dict' `cast` sym co
                 --        else
                 -- 	  dict' = dict  `cast` co
             expr      = HsVar $ instToId source_dict
             cast_expr = HsWrap (WpCast st_co) expr
             rhs       = L (instLocSpan loc) cast_expr
             binds     = instToDictBind target_dict rhs
       ; return (dict', binds)
       }
  where
    loc = tci_loc dict

-- gamma ::^l Fam args ~ alpha
-- => gamma ::^w Fam args ~ alpha, with alpha := Fam args & gamma := Fam args
--    (the update of alpha will not be apparent during propagation, as we
--    never follow the indirections of meta variables; it will be revealed
--    when the equality is zonked)
--
--  NB: It's crucial to update *both* alpha and gamma, as gamma may already
--      have escaped into some other coercions during normalisation.
--
wantedToLocal :: RewriteInst -> TcM RewriteInst
wantedToLocal eq@(RewriteFam {rwi_fam   = fam, 
                              rwi_args  = args, 
                              rwi_right = TyVarTy alpha,
                              rwi_co    = Left gamma})
  = do { writeMetaTyVar alpha (mkTyConApp fam args)
       ; writeMetaTyVar gamma (mkTyConApp fam args)
       ; return $ eq {rwi_co = mkGivenCo $ mkTyVarTy gamma}
       }
wantedToLocal _ = panic "TcTyFuns.wantedToLocal"
\end{code}


%************************************************************************
%*									*
		Propagation of equalities
%*									*
%************************************************************************

Apply the propagation rules exhaustively.

\begin{code}
propagate :: [RewriteInst] -> EqConfig -> TcM EqConfig
propagate []       eqCfg = return eqCfg
propagate (eq:eqs) eqCfg
  = do { optEqs <- applyTop eq
       ; case optEqs of

              -- Top applied to 'eq' => retry with new equalities
           Just (eqs2, skolems2) 
             -> propagate (eqs2 ++ eqs) (eqCfg `addSkolems` skolems2)

              -- Top doesn't apply => try subst rules with all other
              --   equalities, after that 'eq' can go into the residual list
           Nothing
             -> do { (eqs', eqCfg') <- applySubstRules eq eqs eqCfg
                   ; propagate eqs' (eqCfg' `addEq` eq)
                   }
   }

applySubstRules :: RewriteInst                    -- currently considered eq
                -> [RewriteInst]                  -- todo eqs list
                -> EqConfig                       -- residual
                -> TcM ([RewriteInst], EqConfig)  -- new todo & residual
applySubstRules eq todoEqs (eqConfig@EqConfig {eqs = resEqs})
  = do { (newEqs_t, unchangedEqs_t, skolems_t) <- mapSubstRules eq todoEqs
       ; (newEqs_r, unchangedEqs_r, skolems_r) <- mapSubstRules eq resEqs
       ; return (newEqs_t ++ newEqs_r ++ unchangedEqs_t,
                 eqConfig {eqs = unchangedEqs_r} 
                   `addSkolems` (skolems_t `unionVarSet` skolems_r))
       }

mapSubstRules :: RewriteInst     -- try substituting this equality
              -> [RewriteInst]   -- into these equalities
              -> TcM ([RewriteInst], [RewriteInst], TyVarSet)
mapSubstRules eq eqs
  = do { (newEqss, unchangedEqss, skolemss) <- mapAndUnzip3M (substRules eq) eqs
       ; return (concat newEqss, concat unchangedEqss, unionVarSets skolemss)
       }
  where
    substRules eq1 eq2
      = do {traceTc $ hang (ptext (sLit "Trying subst rules with"))
                        4 (ppr eq1 $$ ppr eq2)

               -- try the SubstFam rule
           ; optEqs <- applySubstFam eq1 eq2
           ; case optEqs of
               Just (eqs, skolems) -> return (eqs, [], skolems)
               Nothing             -> do 
           {   -- try the SubstVarVar rule
             optEqs <- applySubstVarVar eq1 eq2
           ; case optEqs of
               Just (eqs, skolems) -> return (eqs, [], skolems)
               Nothing             -> do 
           {   -- try the SubstVarFam rule
             optEqs <- applySubstVarFam eq1 eq2
           ; case optEqs of
               Just eq -> return ([eq], [], emptyVarSet)
               Nothing -> return ([], [eq2], emptyVarSet)
                 -- if no rule matches, we return the equlity we tried to
                 -- substitute into unchanged
           }}}
\end{code}

Attempt to apply the Top rule.  The rule is

  co :: F t1..tn ~ t
  =(Top)=>
  co' :: [s1/x1, .., sm/xm]s ~ t with co = g s1..sm |> co'  

where g :: forall x1..xm. F u1..um ~ s and [s1/x1, .., sm/xm]u1 == t1.

Returns Nothing if the rule could not be applied.  Otherwise, the resulting
equality is normalised and a list of the normal equalities is returned.

\begin{code}
applyTop :: RewriteInst -> TcM (Maybe ([RewriteInst], TyVarSet))

applyTop eq@(RewriteFam {rwi_fam = fam, rwi_args = args})
  = do { optTyCo <- tcUnfoldSynFamInst (TyConApp fam args)
       ; case optTyCo of
           Nothing                -> return Nothing
           Just (lhs, rewrite_co) 
             -> do { co' <- mkRightTransEqInstCo co rewrite_co (lhs, rhs)
                   ; eq' <- deriveEqInst eq lhs rhs co'
                   ; liftM Just $ normEqInst eq'
                   }
       }
  where
    co  = rwi_co eq
    rhs = rwi_right eq

applyTop _ = return Nothing
\end{code}

Attempt to apply the SubstFam rule.  The rule is

  co1 :: F t1..tn ~ t  &  co2 :: F t1..tn ~ s
  =(SubstFam)=>
  co1 :: F t1..tn ~ t  &  co2' :: t ~ s with co2 = co1 |> co2'

where co1 may be a wanted only if co2 is a wanted, too.

Returns Nothing if the rule could not be applied.  Otherwise, the equality
co2' is normalised and a list of the normal equalities is returned.  (The
equality co1 is not returned as it remain unaltered.)

\begin{code}
applySubstFam :: RewriteInst 
              -> RewriteInst 
              -> TcM (Maybe ([RewriteInst], TyVarSet))
applySubstFam eq1@(RewriteFam {rwi_fam = fam1, rwi_args = args1})
              eq2@(RewriteFam {rwi_fam = fam2, rwi_args = args2})

    -- rule matches => rewrite
  | fam1 == fam2 && tcEqTypes args1 args2 &&
    (isWantedRewriteInst eq2 || not (isWantedRewriteInst eq1))
  = do { co2' <- mkRightTransEqInstCo co2 co1 (lhs, rhs)
       ; eq2' <- deriveEqInst eq2 lhs rhs co2'
       ; liftM Just $ normEqInst eq2'
       }

    -- rule would match with eq1 and eq2 swapped => put eq2 into todo list
  | fam1 == fam2 && tcEqTypes args1 args2 &&
    (isWantedRewriteInst eq1 || not (isWantedRewriteInst eq2))
  = return $ Just ([eq2], emptyVarSet)

  where
    lhs = rwi_right eq1
    rhs = rwi_right eq2
    co1 = eqInstCoType (rwi_co eq1)
    co2 = rwi_co eq2

applySubstFam _ _ = return Nothing
\end{code}

Attempt to apply the SubstVarVar rule.  The rule is

  co1 :: x ~ t  &  co2 :: x ~ s
  =(SubstVarVar)=>
  co1 :: x ~ t  &  co2' :: t ~ s with co2 = co1 |> co2'

where co1 may be a wanted only if co2 is a wanted, too.

Returns Nothing if the rule could not be applied.  Otherwise, the equality
co2' is normalised and a list of the normal equalities is returned.  (The
equality co1 is not returned as it remain unaltered.)

\begin{code}
applySubstVarVar :: RewriteInst 
                 -> RewriteInst 
                 -> TcM (Maybe ([RewriteInst], TyVarSet))
applySubstVarVar eq1@(RewriteVar {rwi_var = tv1})
                 eq2@(RewriteVar {rwi_var = tv2})

    -- rule matches => rewrite
  | tv1 == tv2 &&
    (isWantedRewriteInst eq2 || not (isWantedRewriteInst eq1))
  = do { co2' <- mkRightTransEqInstCo co2 co1 (lhs, rhs)
       ; eq2' <- deriveEqInst eq2 lhs rhs co2'
       ; liftM Just $ normEqInst eq2'
       }

    -- rule would match with eq1 and eq2 swapped => put eq2 into todo list
  | tv1 == tv2 &&
    (isWantedRewriteInst eq1 || not (isWantedRewriteInst eq2))
  = return $ Just ([eq2], emptyVarSet)

  where
    lhs = rwi_right eq1
    rhs = rwi_right eq2
    co1 = eqInstCoType (rwi_co eq1)
    co2 = rwi_co eq2

applySubstVarVar _ _ = return Nothing
\end{code}

Attempt to apply the SubstVarFam rule.  The rule is

  co1 :: x ~ t  &  co2 :: F s1..sn ~ s
  =(SubstVarFam)=>
  co1 :: x ~ t  &  co2' :: [t/x](F s1..sn) ~ s 
    with co2 = [co1/x](F s1..sn) |> co2'

where x occurs in F s1..sn. (co1 may be local or wanted.)

Returns Nothing if the rule could not be applied.  Otherwise, the equality
co2' is returned.  (The equality co1 is not returned as it remain unaltered.)

\begin{code}
applySubstVarFam :: RewriteInst -> RewriteInst -> TcM (Maybe RewriteInst)

  -- rule matches => rewrite
applySubstVarFam eq1@(RewriteVar {rwi_var = tv1})
                 eq2@(RewriteFam {rwi_fam = fam2, rwi_args = args2})
  | tv1 `elemVarSet` tyVarsOfTypes args2
  = do { let co1Subst = substTyWith [tv1] [co1] (mkTyConApp fam2 args2)
             args2'   = substTysWith [tv1] [rhs1] args2
             lhs2     = mkTyConApp fam2 args2'
       ; co2' <- mkRightTransEqInstCo co2 co1Subst (lhs2, rhs2)
       ; return $ Just (eq2 {rwi_args = args2', rwi_co = co2'})
       }
  where
    rhs1 = rwi_right eq1
    rhs2 = rwi_right eq2
    co1  = eqInstCoType (rwi_co eq1)
    co2  = rwi_co eq2

  -- rule would match with eq1 and eq2 swapped => put eq2 into todo list
applySubstVarFam (RewriteFam {rwi_args = args1})
                 eq2@(RewriteVar {rwi_var = tv2})
  | tv2 `elemVarSet` tyVarsOfTypes args1
  = return $ Just eq2

applySubstVarFam _ _ = return Nothing
\end{code}


%************************************************************************
%*									*
		Finalisation of equalities
%*									*
%************************************************************************

Exhaustive substitution of all variable equalities of the form co :: x ~ t
(both local and wanted) into the left-hand sides of all other equalities.  This
may lead to recursive equalities; i.e., (1) we need to apply the substitution
implied by one variable equality exhaustively before turning to the next and
(2) we need an occurs check.

We also apply the same substitutions to the local and wanted class and IP
dictionaries.

The treatment of flexibles in wanteds is quite subtle.  We absolutely want to
substitute them into right-hand sides of equalities, to avoid getting two
competing instantiations for a type variables; e.g., consider

  F s ~ alpha, alpha ~ t

If we don't substitute `alpha ~ t', we may instantiate t with `F s' instead.
This would be bad as `F s' is less useful, eg, as an argument to a class
constraint.

However, there is no reason why we would want to *substitute* `alpha ~ t' into a
class constraint.  We rather wait until `alpha' is instantiated to `t` and
save the extra dictionary binding that substitution would introduce.
Moreover, we may substitute wanted equalities only into wanted dictionaries.

NB: 
* Given that we apply the substitution corresponding to a single equality
  exhaustively, before turning to the next, and because we eliminate recursive
  equalities, all opportunities for subtitution will have been exhausted after
  we have considered each equality once.

\begin{code}
substitute :: [RewriteInst]       -- equalities
           -> [Inst]              -- local class dictionaries
           -> [Inst]              -- wanted class dictionaries
           -> TcM ([RewriteInst], -- equalities after substitution
                   TcDictBinds,   -- all newly generated dictionary bindings
                   [Inst],        -- local dictionaries after substitution
                   [Inst])        -- wanted dictionaries after substitution
substitute eqs locals wanteds = subst eqs [] emptyBag locals wanteds
  where
    subst [] res binds locals wanteds 
      = return (res, binds, locals, wanteds)

    subst (eq@(RewriteVar {rwi_var = tv, rwi_right = ty, rwi_co = co}):eqs) 
          res binds locals wanteds
      = do { traceTc $ ptext (sLit "TcTyFuns.substitute:") <+> ppr eq

           ; let coSubst = zipOpenTvSubst [tv] [eqInstCoType co]
                 tySubst = zipOpenTvSubst [tv] [ty]
           ; eqs' <- mapM (substEq eq coSubst tySubst) eqs
           ; res' <- mapM (substEq eq coSubst tySubst) res

             -- only susbtitute local equalities into local dictionaries
           ; (lbinds, locals')  <- if not (isWantedCo co)
                                   then 
                                     mapAndUnzipM 
                                       (substDict eq coSubst tySubst False) 
                                       locals
                                   else
                                     return ([], locals)

              -- flexible tvs in wanteds will be instantiated anyway, there is
              -- no need to substitute them into dictionaries
           ; (wbinds, wanteds') <- if not (isMetaTyVar tv && isWantedCo co)
                                   then
                                     mapAndUnzipM 
                                       (substDict eq coSubst tySubst True) 
                                       wanteds
                                   else
                                     return ([], wanteds)

           ; let binds' = unionManyBags $ binds : lbinds ++ wbinds
           ; subst eqs' (eq:res') binds' locals' wanteds'
           }
    subst (eq:eqs) res binds locals wanteds
      = subst eqs (eq:res) binds locals wanteds

      -- We have, co :: tv ~ ty 
      -- => apply [ty/tv] to right-hand side of eq2
      --    (but only if tv actually occurs in the right-hand side of eq2)
    substEq (RewriteVar {rwi_var = tv, rwi_right = ty}) 
            coSubst tySubst eq2
      | tv `elemVarSet` tyVarsOfType (rwi_right eq2)
      = do { let co1Subst = mkSymCoercion $ substTy coSubst (rwi_right eq2)
                 right2'  = substTy tySubst (rwi_right eq2)
                 left2    = case eq2 of
                              RewriteVar {rwi_var = tv2}   -> mkTyVarTy tv2
                              RewriteFam {rwi_fam = fam,
                                          rwi_args = args} ->mkTyConApp fam args
           ; co2' <- mkLeftTransEqInstCo (rwi_co eq2) co1Subst (left2, right2')
           ; case eq2 of
               RewriteVar {rwi_var = tv2} | tv2 `elemVarSet` tyVarsOfType ty
                 -> occurCheckErr left2 right2'
               _ -> return $ eq2 {rwi_right = right2', rwi_co = co2'}
           }

      -- unchanged
    substEq _ _ _ eq2
      = return eq2

      -- We have, co :: tv ~ ty 
      -- => apply [ty/tv] to dictionary predicate
      --    (but only if tv actually occurs in the predicate)
    substDict (RewriteVar {rwi_var = tv}) coSubst tySubst isWanted dict
      | isClassDict dict
      , tv `elemVarSet` tyVarsOfPred (tci_pred dict)
      = do { let co1Subst = PredTy (substPred coSubst (tci_pred dict))
                 pred'    = substPred tySubst (tci_pred dict)
           ; (dict', binds) <- mkDictBind dict isWanted co1Subst pred'
           ; return (binds, dict')
           }

      -- unchanged
    substDict _ _ _ _ dict
      = return (emptyBag, dict)
-- !!!TODO: Still need to substitute into IP constraints.
\end{code}

For any *wanted* variable equality of the form co :: alpha ~ t or co :: a ~
alpha, we instantiate alpha with t or a, respectively, and set co := id.
Return all remaining wanted equalities.  The Boolean result component is True
if at least one instantiation of a flexible that is *not* a skolem from
flattening was performed.

We need to instantiate all flexibles that arose as skolems during flattening
of wanteds before we instantiate any other flexibles. Consider F delta ~
alpha, F alpha ~ delta, where alpha is a skolem and delta a free flexible. We
need to produce F (F delta) ~ delta (and not F (F alpha) ~ alpha). Otherwise,
we may wrongly claim to having performed an improvement, which can lead to
non-termination of the combined class-family solver.

\begin{code}
instantiateAndExtract :: [RewriteInst] -> Bool -> TyVarSet -> TcM ([Inst], Bool)
instantiateAndExtract eqs localsEmpty skolems
  = do { traceTc $ hang (ptext (sLit "instantiateAndExtract:"))
                     4 (ppr eqs $$ ppr skolems)
           -- start by *only* instantiating skolem flexibles from flattening
       ; unflat_wanteds <- liftM catMaybes $ 
                             mapM (inst (`elemVarSet` skolems)) wanteds
           -- only afterwards instantiate free flexibles
       ; residuals <- liftM catMaybes $ mapM (inst (const True)) unflat_wanteds
       ; let improvement = length residuals < length unflat_wanteds
       ; residuals' <- mapM rewriteInstToInst residuals
       ; return (residuals', improvement)
       }
  where
    wanteds      = filter (isWantedCo . rwi_co) eqs
    checkingMode = length eqs > length wanteds || not localsEmpty
                     -- no local equalities or dicts => checking mode

        -- co :: alpha ~ t or co :: a ~ alpha
    inst mayInst eq@(RewriteVar {rwi_var = tv1, rwi_right = ty2, rwi_co = co})
      = do { flexi_tv1       <- isFlexible mayInst tv1
           ; maybe_flexi_tv2 <- isFlexibleTy mayInst ty2
           ; case (flexi_tv1, maybe_flexi_tv2) of
               (True, _) 
                 -> -- co :: alpha ~ t
                    doInst (rwi_swapped eq) tv1 ty2 co eq
               (False, Just tv2) 
                 -> -- co :: a ~ alpha                  
                    doInst (not $ rwi_swapped eq) tv2 (mkTyVarTy tv1) co eq
               _ -> return $ Just eq
           }

        -- co :: F args ~ alpha, and we are in checking mode (ie, no locals)
    inst mayInst eq@(RewriteFam {rwi_fam = fam, rwi_args = args, 
                                 rwi_right = ty2, rwi_co = co})
      | Just tv2 <- tcGetTyVar_maybe ty2
      , isMetaTyVar tv2
      , mayInst tv2 && (checkingMode || tv2 `elemVarSet` skolems)
                        -- !!!FIXME: this is too liberal, even if tv2 is in 
                        -- skolems we shouldn't instantiate if tvs occurs 
                        -- in other equalities that may propagate it into the
                        -- environment
      = doInst (not $ rwi_swapped eq) tv2 (mkTyConApp fam args) co eq

    inst _mayInst eq = return $ Just eq

    -- tv is a meta var and not filled
    isFlexible mayInst tv
      | isMetaTyVar tv && mayInst tv = liftM isFlexi $ readMetaTyVar tv
      | otherwise                    = return False

    -- type is a tv that is a meta var and not filled
    isFlexibleTy mayInst ty
      | Just tv <- tcGetTyVar_maybe ty = do {flexi <- isFlexible mayInst tv
                                            ; if flexi then return $ Just tv 
                                                       else return Nothing
                                            }
      | otherwise                      = return Nothing

    doInst _swapped _tv _ty (Right ty) _eq 
      = pprPanic "TcTyFuns.doInst: local eq: " (ppr ty)
    doInst swapped tv ty (Left cotv) eq
      = do { lookupTV <- lookupTcTyVar tv
           ; uMeta swapped tv lookupTV ty cotv
           }
      where
        -- meta variable has been filled already
        -- => keep the equality
        uMeta _swapped tv (IndirectTv fill_ty) ty _cotv
          = do { traceTc $ 
                   ptext (sLit "flexible") <+> ppr tv <+>
                   ptext (sLit "already filled with") <+> ppr fill_ty <+>
                   ptext (sLit "meant to fill with") <+> ppr ty
               ; return $ Just eq
               }

        -- type variable meets type variable
        -- => check that tv2 hasn't been updated yet and choose which to update
        uMeta swapped tv1 (DoneTv details1) (TyVarTy tv2) cotv
          | tv1 == tv2
          = panic "TcTyFuns.uMeta: normalisation shouldn't allow x ~ x"

          | otherwise
          = do { lookupTV2 <- lookupTcTyVar tv2
               ; case lookupTV2 of
                   IndirectTv ty   -> 
                     uMeta swapped tv1 (DoneTv details1) ty cotv
                   DoneTv details2 -> 
                     uMetaVar swapped tv1 details1 tv2 details2 cotv
               }

        ------ Beyond this point we know that ty2 is not a type variable

        -- signature skolem meets non-variable type
        -- => cannot update (retain the equality)!
        uMeta _swapped _tv (DoneTv (MetaTv (SigTv _) _)) _non_tv_ty _cotv
          = return $ Just eq

        -- updatable meta variable meets non-variable type
        -- => occurs check, monotype check, and kinds match check, then update
        uMeta swapped tv (DoneTv (MetaTv _ ref)) non_tv_ty cotv
          = do {   -- occurs + monotype check
               ; mb_ty' <- checkTauTvUpdate tv non_tv_ty    
                             
               ; case mb_ty' of
                   Nothing  -> 
                     -- there may be a family in non_tv_ty due to an unzonked,
                     -- but updated skolem for a local equality
                     return $ Just eq
                   Just ty' ->
                     do { checkUpdateMeta swapped tv ref ty'  -- update meta var
                        ; writeMetaTyVar cotv ty'             -- update co var
                        ; return Nothing
                        }
               }

        uMeta _ _ _ _ _ = panic "TcTyFuns.uMeta"

        -- uMetaVar: unify two type variables
        -- meta variable meets skolem 
        -- => just update
        uMetaVar swapped tv1 (MetaTv _ ref) tv2 (SkolemTv _) cotv
          = do { checkUpdateMeta swapped tv1 ref (mkTyVarTy tv2)
               ; writeMetaTyVar cotv (mkTyVarTy tv2)
               ; return Nothing
               }

        -- meta variable meets meta variable 
        -- => be clever about which of the two to update 
        --   (from TcUnify.uUnfilledVars minus boxy stuff)
        uMetaVar swapped tv1 (MetaTv info1 ref1) tv2 (MetaTv info2 ref2) cotv
          = do { case (info1, info2) of
                   -- Avoid SigTvs if poss
                   (SigTv _, _      ) | k1_sub_k2 -> update_tv2
                   (_,       SigTv _) | k2_sub_k1 -> update_tv1

                   (_,   _) | k1_sub_k2 -> if k2_sub_k1 && 
                                              nicer_to_update_tv1
                                           then update_tv1  -- Same kinds
                                           else update_tv2
                            | k2_sub_k1 -> update_tv1
                            | otherwise -> kind_err
              -- Update the variable with least kind info
              -- See notes on type inference in Kind.lhs
              -- The "nicer to" part only applies if the two kinds are the same,
              -- so we can choose which to do.

               ; writeMetaTyVar cotv (mkTyVarTy tv2)
               ; return Nothing
               }
          where
                -- Kinds should be guaranteed ok at this point
            update_tv1 = updateMeta tv1 ref1 (mkTyVarTy tv2)
            update_tv2 = updateMeta tv2 ref2 (mkTyVarTy tv1)

            kind_err = addErrCtxtM (unifyKindCtxt swapped tv1 (mkTyVarTy tv2)) $
                       unifyKindMisMatch k1 k2

            k1 = tyVarKind tv1
            k2 = tyVarKind tv2
            k1_sub_k2 = k1 `isSubKind` k2
            k2_sub_k1 = k2 `isSubKind` k1

            nicer_to_update_tv1 = isSystemName (Var.varName tv1)
                -- Try to update sys-y type variables in preference to ones
                -- gotten (say) by instantiating a polymorphic function with
                -- a user-written type sig 

        uMetaVar _ _ _ _ _ _ = panic "uMetaVar"
\end{code}


%************************************************************************
%*									*
\section{Errors}
%*									*
%************************************************************************

The infamous couldn't match expected type soandso against inferred type
somethingdifferent message.

\begin{code}
eqInstMisMatch :: Inst -> TcM a
eqInstMisMatch inst
  = ASSERT( isEqInst inst )
    setErrCtxt ctxt $ failWithMisMatch ty_act ty_exp
  where
    (ty_act, ty_exp) = eqInstTys inst
    InstLoc _ _ ctxt = instLoc   inst

-----------------------
failWithMisMatch :: TcType -> TcType -> TcM a
-- Generate the message when two types fail to match,
-- going to some trouble to make it helpful.
-- The argument order is: actual type, expected type
failWithMisMatch ty_act ty_exp
  = do	{ env0 <- tcInitTidyEnv
        ; ty_exp <- zonkTcType ty_exp
        ; ty_act <- zonkTcType ty_act
        ; failWithTcM (misMatchMsg env0 (ty_act, ty_exp))
	}

misMatchMsg :: TidyEnv -> (TcType, TcType) -> (TidyEnv, SDoc)
misMatchMsg env0 (ty_act, ty_exp)
  = let (env1, pp_exp, extra_exp) = ppr_ty env0 ty_exp
	(env2, pp_act, extra_act) = ppr_ty env1 ty_act
        msg = sep [sep [ptext (sLit "Couldn't match expected type") <+> pp_exp, 
			nest 7 $
                              ptext (sLit "against inferred type") <+> pp_act],
		   nest 2 (extra_exp $$ extra_act)]
    in
    (env2, msg)

  where
    ppr_ty :: TidyEnv -> TcType -> (TidyEnv, SDoc, SDoc)
    ppr_ty env ty
      = let (env1, tidy_ty) = tidyOpenType env ty
    	    (env2, extra)  = ppr_extra env1 tidy_ty
    	in
	(env2, quotes (ppr tidy_ty), extra)

    -- (ppr_extra env ty) shows extra info about 'ty'
    ppr_extra :: TidyEnv -> Type -> (TidyEnv, SDoc)
    ppr_extra env (TyVarTy tv)
      | isTcTyVar tv && (isSkolemTyVar tv || isSigTyVar tv) && not (isUnk tv)
      = (env1, pprSkolTvBinding tv1)
      where
        (env1, tv1) = tidySkolemTyVar env tv

    ppr_extra env _ty = (env, empty)		-- Normal case
\end{code}

Warn of loopy local equalities that were dropped.

\begin{code}
warnDroppingLoopyEquality :: TcType -> TcType -> TcM ()
warnDroppingLoopyEquality ty1 ty2 
  = do { env0 <- tcInitTidyEnv
       ; ty1 <- zonkTcType ty1
       ; ty2 <- zonkTcType ty2
       ; let (env1 , tidy_ty1) = tidyOpenType env0 ty1
	     (_env2, tidy_ty2) = tidyOpenType env1 ty2
       ; addWarnTc $ hang (ptext (sLit "Dropping loopy given equality"))
		       2 (quotes (ppr tidy_ty1 <+> text "~" <+> ppr tidy_ty2))
       }
\end{code}