%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

\begin{code}
module BuildTyCl (
	buildSynTyCon, buildAlgTyCon, buildDataCon,
	buildClass,
	mkAbstractTyConRhs, mkOpenDataTyConRhs, 
	mkNewTyConRhs, mkDataTyConRhs 
    ) where

#include "HsVersions.h"

import IfaceEnv

import DataCon
import Var
import VarSet
import BasicTypes
import Name
import OccName
import MkId
import Class
import TyCon
import Type
import Coercion

import TcRnMonad
import Util		( count )
import Outputable

import Data.List
\end{code}
	

\begin{code}
------------------------------------------------------
buildSynTyCon :: Name -> [TyVar] 
              -> SynTyConRhs 
	      -> Kind			-- Kind of the RHS
	      -> Maybe (TyCon, [Type])  -- family instance if applicable
              -> TcRnIf m n TyCon

buildSynTyCon tc_name tvs rhs@(OpenSynTyCon {}) rhs_kind _
  = let
      kind = mkArrowKinds (map tyVarKind tvs) rhs_kind
    in
    return $ mkSynTyCon tc_name kind tvs rhs NoParentTyCon
    
buildSynTyCon tc_name tvs rhs@(SynonymTyCon {}) rhs_kind mb_family
  = do { -- We need to tie a knot as the coercion of a data instance depends
	 -- on the instance representation tycon and vice versa.
       ; tycon <- fixM (\ tycon_rec -> do 
	 { parent <- mkParentInfo mb_family tc_name tvs tycon_rec
	 ; let { tycon   = mkSynTyCon tc_name kind tvs rhs parent
	       ; kind    = mkArrowKinds (map tyVarKind tvs) rhs_kind
	       }
         ; return tycon
         })
       ; return tycon 
       }

------------------------------------------------------
buildAlgTyCon :: Name -> [TyVar] 
	      -> ThetaType		-- Stupid theta
	      -> AlgTyConRhs
	      -> RecFlag
	      -> Bool			-- True <=> want generics functions
	      -> Bool			-- True <=> was declared in GADT syntax
	      -> Maybe (TyCon, [Type])  -- family instance if applicable
	      -> TcRnIf m n TyCon

buildAlgTyCon tc_name tvs stupid_theta rhs is_rec want_generics gadt_syn
	      mb_family
  = do { -- We need to tie a knot as the coercion of a data instance depends
	 -- on the instance representation tycon and vice versa.
       ; tycon <- fixM (\ tycon_rec -> do 
	 { parent <- mkParentInfo mb_family tc_name tvs tycon_rec
	 ; let { tycon = mkAlgTyCon tc_name kind tvs stupid_theta rhs
				    fields parent is_rec want_generics gadt_syn
	       ; kind    = mkArrowKinds (map tyVarKind tvs) liftedTypeKind
	       ; fields  = mkTyConSelIds tycon rhs
	       }
         ; return tycon
         })
       ; return tycon 
       }

-- If a family tycon with instance types is given, the current tycon is an
-- instance of that family and we need to
--
-- (1) create a coercion that identifies the family instance type and the
--     representation type from Step (1); ie, it is of the form 
--	   `Co tvs :: F ts :=: R tvs', where `Co' is the name of the coercion,
--	   `F' the family tycon and `R' the (derived) representation tycon,
--	   and
-- (2) produce a `TyConParent' value containing the parent and coercion
--     information.
--
mkParentInfo :: Maybe (TyCon, [Type]) 
             -> Name -> [TyVar] 
             -> TyCon 
             -> TcRnIf m n TyConParent
mkParentInfo Nothing                  _       _   _         =
  return NoParentTyCon
mkParentInfo (Just (family, instTys)) tc_name tvs rep_tycon =
  do { -- Create the coercion
     ; co_tycon_name <- newImplicitBinder tc_name mkInstTyCoOcc
     ; let co_tycon = mkFamInstCoercion co_tycon_name tvs
                                        family instTys rep_tycon
     ; return $ FamilyTyCon family instTys co_tycon
     }
    
------------------------------------------------------
mkAbstractTyConRhs :: AlgTyConRhs
mkAbstractTyConRhs = AbstractTyCon

mkOpenDataTyConRhs :: AlgTyConRhs
mkOpenDataTyConRhs = OpenTyCon Nothing

mkDataTyConRhs :: [DataCon] -> AlgTyConRhs
mkDataTyConRhs cons
  = DataTyCon { data_cons = cons, is_enum = all isNullarySrcDataCon cons }

mkNewTyConRhs :: Name -> TyCon -> DataCon -> TcRnIf m n AlgTyConRhs
-- Monadic because it makes a Name for the coercion TyCon
-- We pass the Name of the parent TyCon, as well as the TyCon itself,
-- because the latter is part of a knot, whereas the former is not.
mkNewTyConRhs tycon_name tycon con 
  = do	{ co_tycon_name <- newImplicitBinder tycon_name mkNewTyCoOcc
	; let co_tycon = mkNewTypeCoercion co_tycon_name tycon etad_tvs etad_rhs
              cocon_maybe | all_coercions || isRecursiveTyCon tycon 
		          = Just co_tycon
                	  | otherwise              
                	  = Nothing
	; traceIf (text "mkNewTyConRhs" <+> ppr cocon_maybe)
	; return (NewTyCon { data_con    = con, 
		       	     nt_rhs      = rhs_ty,
		       	     nt_etad_rhs = (etad_tvs, etad_rhs),
 		       	     nt_co 	 = cocon_maybe } ) }
                             -- Coreview looks through newtypes with a Nothing
                             -- for nt_co, or uses explicit coercions otherwise
  where
        -- If all_coercions is True then we use coercions for all newtypes
        -- otherwise we use coercions for recursive newtypes and look through
        -- non-recursive newtypes
    all_coercions = True
    tvs    = tyConTyVars tycon
    inst_con_ty = applyTys (dataConUserType con) (mkTyVarTys tvs)
    rhs_ty = ASSERT( isFunTy inst_con_ty ) funArgTy inst_con_ty
	-- Instantiate the data con with the 
	-- type variables from the tycon
	-- NB: a newtype DataCon has a type that must look like
	--        forall tvs.  <arg-ty> -> T tvs
	-- Note that we *can't* use dataConInstOrigArgTys here because
	-- the newtype arising from   class Foo a => Bar a where {}
  	-- has a single argument (Foo a) that is a *type class*, so
	-- dataConInstOrigArgTys returns [].

    etad_tvs :: [TyVar]	-- Matched lazily, so that mkNewTypeCoercion can
    etad_rhs :: Type	-- return a TyCon without pulling on rhs_ty
			-- See Note [Tricky iface loop] in LoadIface
    (etad_tvs, etad_rhs) = eta_reduce (reverse tvs) rhs_ty
 
    eta_reduce :: [TyVar]		-- Reversed
	       -> Type			-- Rhs type
	       -> ([TyVar], Type)	-- Eta-reduced version (tyvars in normal order)
    eta_reduce (a:as) ty | Just (fun, arg) <- splitAppTy_maybe ty,
			   Just tv <- getTyVar_maybe arg,
			   tv == a,
			   not (a `elemVarSet` tyVarsOfType fun)
			 = eta_reduce as fun
    eta_reduce tvs ty = (reverse tvs, ty)
				

------------------------------------------------------
buildDataCon :: Name -> Bool
	    -> [StrictnessMark] 
	    -> [Name]			-- Field labels
	    -> [TyVar] -> [TyVar]	-- Univ and ext 
            -> [(TyVar,Type)]           -- Equality spec
	    -> ThetaType		-- Does not include the "stupid theta"
					-- or the GADT equalities
	    -> [Type] -> TyCon
	    -> TcRnIf m n DataCon
-- A wrapper for DataCon.mkDataCon that
--   a) makes the worker Id
--   b) makes the wrapper Id if necessary, including
--	allocating its unique (hence monadic)
buildDataCon src_name declared_infix arg_stricts field_lbls
	     univ_tvs ex_tvs eq_spec ctxt arg_tys tycon
  = do	{ wrap_name <- newImplicitBinder src_name mkDataConWrapperOcc
	; work_name <- newImplicitBinder src_name mkDataConWorkerOcc
	-- This last one takes the name of the data constructor in the source
	-- code, which (for Haskell source anyway) will be in the DataName name
	-- space, and puts it into the VarName name space

	; let
		stupid_ctxt = mkDataConStupidTheta tycon arg_tys univ_tvs
		data_con = mkDataCon src_name declared_infix
				     arg_stricts field_lbls
				     univ_tvs ex_tvs eq_spec ctxt
				     arg_tys tycon
				     stupid_ctxt dc_ids
		dc_ids = mkDataConIds wrap_name work_name data_con

	; return data_con }


-- The stupid context for a data constructor should be limited to
-- the type variables mentioned in the arg_tys
-- ToDo: Or functionally dependent on?  
--	 This whole stupid theta thing is, well, stupid.
mkDataConStupidTheta :: TyCon -> [Type] -> [TyVar] -> [PredType]
mkDataConStupidTheta tycon arg_tys univ_tvs
  | null stupid_theta = []	-- The common case
  | otherwise 	      = filter in_arg_tys stupid_theta
  where
    tc_subst	 = zipTopTvSubst (tyConTyVars tycon) (mkTyVarTys univ_tvs)
    stupid_theta = substTheta tc_subst (tyConStupidTheta tycon)
	-- Start by instantiating the master copy of the 
	-- stupid theta, taken from the TyCon

    arg_tyvars      = tyVarsOfTypes arg_tys
    in_arg_tys pred = not $ isEmptyVarSet $ 
		      tyVarsOfPred pred `intersectVarSet` arg_tyvars

------------------------------------------------------
mkTyConSelIds :: TyCon -> AlgTyConRhs -> [Id]
mkTyConSelIds tycon rhs
  =  [ mkRecordSelId tycon fld 
     | fld <- nub (concatMap dataConFieldLabels (visibleDataCons rhs)) ]
	-- We'll check later that fields with the same name 
	-- from different constructors have the same type.
\end{code}


------------------------------------------------------
\begin{code}
buildClass :: Bool			-- True <=> do not include unfoldings 
					--	    on dict selectors
					-- Used when importing a class without -O
	   -> Name -> [TyVar] -> ThetaType
	   -> [FunDep TyVar]		-- Functional dependencies
	   -> [TyThing]			-- Associated types
	   -> [(Name, DefMeth, Type)]	-- Method info
	   -> RecFlag			-- Info for type constructor
	   -> TcRnIf m n Class

buildClass no_unf class_name tvs sc_theta fds ats sig_stuff tc_isrec
  = do	{ traceIf (text "buildClass")
	; tycon_name <- newImplicitBinder class_name mkClassTyConOcc
	; datacon_name <- newImplicitBinder class_name mkClassDataConOcc
		-- The class name is the 'parent' for this datacon, not its tycon,
		-- because one should import the class to get the binding for 
		-- the datacon

	; fixM (\ rec_clas -> do {	-- Only name generation inside loop

	  let { rec_tycon  = classTyCon rec_clas
	      ; op_tys	   = [ty | (_,_,ty) <- sig_stuff]
	      ; op_items   = [ (mkDictSelId no_unf op_name rec_clas, dm_info)
			     | (op_name, dm_info, _) <- sig_stuff ] }
	  		-- Build the selector id and default method id

	; dict_con <- buildDataCon datacon_name
				   False 	-- Not declared infix
				   (map (const NotMarkedStrict) op_tys)
				   [{- No labelled fields -}]
				   tvs [{- no existentials -}]
                                   [{- No GADT equalities -}] sc_theta 
                                   op_tys
				   rec_tycon

	; let n_value_preds   = count (not . isEqPred) sc_theta
	      all_value_preds = n_value_preds == length sc_theta
	      -- We only make selectors for the *value* superclasses, 
	      -- not equality predicates 

	; sc_sel_names <- mapM  (newImplicitBinder class_name . mkSuperDictSelOcc) 
				[1..n_value_preds]
        ; let sc_sel_ids = [mkDictSelId no_unf sc_name rec_clas | sc_name <- sc_sel_names]
	      -- We number off the Dict superclass selectors, 1, 2, 3 etc so that we 
	      -- can construct names for the selectors. Thus
	      --      class (C a, C b) => D a b where ...
	      -- gives superclass selectors
	      --      D_sc1, D_sc2
	      -- (We used to call them D_C, but now we can have two different
	      --  superclasses both called C!)
	      --
	
	; let use_newtype = (n_value_preds + length sig_stuff == 1) && all_value_preds
		-- Use a newtype if the data constructor has 
		-- 	(a) exactly one value field
		--	(b) no existential or equality-predicate fields
		-- i.e. exactly one operation or superclass taken together
		-- See note [Class newtypes and equality predicates]

	; rhs <- if use_newtype
		 then mkNewTyConRhs tycon_name rec_tycon dict_con
		 else return (mkDataTyConRhs [dict_con])

	; let {	clas_kind = mkArrowKinds (map tyVarKind tvs) liftedTypeKind

 	      ; tycon = mkClassTyCon tycon_name clas_kind tvs
 	                             rhs rec_clas tc_isrec
		-- A class can be recursive, and in the case of newtypes 
		-- this matters.  For example
		-- 	class C a where { op :: C b => a -> b -> Int }
		-- Because C has only one operation, it is represented by
		-- a newtype, and it should be a *recursive* newtype.
		-- [If we don't make it a recursive newtype, we'll expand the
		-- newtype like a synonym, but that will lead to an infinite
		-- type]
	      ; atTyCons = [tycon | ATyCon tycon <- ats]

	      ; result = mkClass class_name tvs fds 
			         sc_theta sc_sel_ids atTyCons
				 op_items tycon
	      }
	; traceIf (text "buildClass" <+> ppr tycon) 
	; return result
	})}
\end{code}

Note [Class newtypes and equality predicates]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider
	class (a ~ F b) => C a b where
	  op :: a -> b

We cannot represent this by a newtype, even though it's not
existential, and there's only one value field, because we do
capture an equality predicate:

	data C a b where
	  MkC :: forall a b. (a ~ F b) => (a->b) -> C a b

We need to access this equality predicate when we get passes a C
dictionary.  See Trac #2238

