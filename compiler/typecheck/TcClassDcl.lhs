%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

Typechecking class declarations

\begin{code}
module TcClassDcl ( tcClassSigs, tcClassDecl2, 
		    findMethodBind, tcInstanceMethodBody, 
		    mkGenericDefMethBind, getGenericInstances, mkDefMethRdrName,
		    tcAddDeclCtxt, badMethodErr, badATErr, omittedATWarn
		  ) where

#include "HsVersions.h"

import HsSyn
import RnHsSyn
import RnExpr
import RnEnv
import Inst
import InstEnv
import TcEnv
import TcBinds
import TcSimplify
import TcHsType
import TcMType
import TcType
import TcRnMonad
import Generics
import Class
import TyCon
import MkId
import Id
import Name
import Var
import NameEnv
import NameSet
import RdrName
import Outputable
import PrelNames
import DynFlags
import ErrUtils
import Util
import ListSetOps
import SrcLoc
import Maybes
import BasicTypes
import Bag
import FastString

import Control.Monad
import Data.List
\end{code}


Dictionary handling
~~~~~~~~~~~~~~~~~~~
Every class implicitly declares a new data type, corresponding to dictionaries
of that class. So, for example:

	class (D a) => C a where
	  op1 :: a -> a
	  op2 :: forall b. Ord b => a -> b -> b

would implicitly declare

	data CDict a = CDict (D a)	
			     (a -> a)
			     (forall b. Ord b => a -> b -> b)

(We could use a record decl, but that means changing more of the existing apparatus.
One step at at time!)

For classes with just one superclass+method, we use a newtype decl instead:

	class C a where
	  op :: forallb. a -> b -> b

generates

	newtype CDict a = CDict (forall b. a -> b -> b)

Now DictTy in Type is just a form of type synomym: 
	DictTy c t = TyConTy CDict `AppTy` t

Death to "ExpandingDicts".


%************************************************************************
%*									*
		Type-checking the class op signatures
%*									*
%************************************************************************

\begin{code}
tcClassSigs :: Name	    		-- Name of the class
	    -> [LSig Name]
	    -> LHsBinds Name
	    -> TcM [TcMethInfo]

type TcMethInfo = (Name, DefMeth, Type)	-- A temporary intermediate, to communicate 
					-- between tcClassSigs and buildClass
tcClassSigs clas sigs def_methods
  = do { dm_env <- checkDefaultBinds clas op_names def_methods
       ; mapM (tcClassSig dm_env) op_sigs }
  where
    op_sigs  = [sig | sig@(L _ (TypeSig _ _))       <- sigs]
    op_names = [n   |     (L _ (TypeSig (L _ n) _)) <- op_sigs]


checkDefaultBinds :: Name -> [Name] -> LHsBinds Name -> TcM (NameEnv Bool)
  -- Check default bindings
  -- 	a) must be for a class op for this class
  --	b) must be all generic or all non-generic
  -- and return a mapping from class-op to Bool
  --	where True <=> it's a generic default method
checkDefaultBinds clas ops binds
  = do dm_infos <- mapM (addLocM (checkDefaultBind clas ops)) (bagToList binds)
       return (mkNameEnv dm_infos)

checkDefaultBind :: Name -> [Name] -> HsBindLR Name Name -> TcM (Name, Bool)
checkDefaultBind clas ops (FunBind {fun_id = L _ op, fun_matches = MatchGroup matches _ })
  = do {  	-- Check that the op is from this class
	checkTc (op `elem` ops) (badMethodErr clas op)

   	-- Check that all the defns ar generic, or none are
    ;	checkTc (all_generic || none_generic) (mixedGenericErr op)

    ;	return (op, all_generic)
    }
  where
    n_generic    = count (isJust . maybeGenericMatch) matches
    none_generic = n_generic == 0
    all_generic  = matches `lengthIs` n_generic
checkDefaultBind _ _ b = pprPanic "checkDefaultBind" (ppr b)


tcClassSig :: NameEnv Bool		-- Info about default methods; 
	   -> LSig Name
	   -> TcM TcMethInfo

tcClassSig dm_env (L loc (TypeSig (L _ op_name) op_hs_ty))
  = setSrcSpan loc $ do
    { op_ty <- tcHsKindedType op_hs_ty	-- Class tyvars already in scope
    ; let dm = case lookupNameEnv dm_env op_name of
		Nothing    -> NoDefMeth
		Just False -> DefMeth
		Just True  -> GenDefMeth
    ; return (op_name, dm, op_ty) }
tcClassSig _ s = pprPanic "tcClassSig" (ppr s)
\end{code}


%************************************************************************
%*									*
		Class Declarations
%*									*
%************************************************************************

\begin{code}
tcClassDecl2 :: LTyClDecl Name		-- The class declaration
	     -> TcM (LHsBinds Id, [Id])

tcClassDecl2 (L loc (ClassDecl {tcdLName = class_name, tcdSigs = sigs, 
				tcdMeths = default_binds}))
  = recoverM (return (emptyLHsBinds, []))	$
    setSrcSpan loc		   		$
    do  { clas <- tcLookupLocatedClass class_name

	-- We make a separate binding for each default method.
	-- At one time I used a single AbsBinds for all of them, thus
	-- AbsBind [d] [dm1, dm2, dm3] { dm1 = ...; dm2 = ...; dm3 = ... }
	-- But that desugars into
	--	ds = \d -> (..., ..., ...)
	--	dm1 = \d -> case ds d of (a,b,c) -> a
	-- And since ds is big, it doesn't get inlined, so we don't get good
	-- default methods.  Better to make separate AbsBinds for each
	; let
	      (tyvars, _, _, op_items) = classBigSig clas
	      rigid_info  = ClsSkol clas
	      prag_fn	  = mkPragFun sigs
	      sig_fn	  = mkTcSigFun sigs
	      clas_tyvars = tcSkolSigTyVars rigid_info tyvars
	      pred  	  = mkClassPred clas (mkTyVarTys clas_tyvars)
	; inst_loc <- getInstLoc (SigOrigin rigid_info)
	; this_dict <- newDictBndr inst_loc pred

	; let tc_dm = tcDefMeth rigid_info clas clas_tyvars [pred] 
				this_dict default_binds
	      			sig_fn prag_fn
	      	-- tc_dm is called only for a sel_id
	      	-- that has a binding in default_binds

	      dm_sel_ids  = [sel_id | (sel_id, DefMeth) <- op_items]
	      -- Generate code for polymorphic default methods only (hence DefMeth)
	      -- (Generic default methods have turned into instance decls by now.)
	      -- This is incompatible with Hugs, which expects a polymorphic 
	      -- default method for every class op, regardless of whether or not 
	      -- the programmer supplied an explicit default decl for the class.  
	      -- (If necessary we can fix that, but we don't have a convenient Id to hand.)

	; (defm_binds, dm_ids) <- tcExtendTyVarEnv clas_tyvars  $
			          mapAndUnzipM tc_dm dm_sel_ids

	; return (unionManyBags defm_binds, dm_ids) }

tcClassDecl2 d = pprPanic "tcClassDecl2" (ppr d)
    
tcDefMeth :: SkolemInfo -> Class -> [TyVar] -> ThetaType -> Inst -> LHsBinds Name
          -> TcSigFun -> TcPragFun -> Id
          -> TcM (LHsBinds Id, Id)
tcDefMeth rigid_info clas tyvars theta this_dict binds_in sig_fn prag_fn sel_id
  = do	{ let sel_name = idName sel_id
	; local_dm_name <- newLocalName sel_name
	; let meth_bind = findMethodBind sel_name local_dm_name binds_in
			  `orElse` pprPanic "tcDefMeth" (ppr sel_id)
		-- We only call tcDefMeth on selectors for which 
		-- there is a binding in binds_in

	      meth_sig_fn  _ = sig_fn sel_name
	      meth_prag_fn _ = prag_fn sel_name

	; (top_dm_id, bind) <- tcInstanceMethodBody rigid_info
			   clas tyvars [this_dict] theta (mkTyVarTys tyvars)
			   Nothing sel_id
			   local_dm_name
			   meth_sig_fn meth_prag_fn
			   meth_bind

	; return (bind, top_dm_id) }

mkDefMethRdrName :: Name -> RdrName
mkDefMethRdrName sel_name = mkDerivedRdrName sel_name mkDefaultMethodOcc

---------------------------
-- The renamer just puts the selector ID as the binder in the method binding
-- but we must use the method name; so we substitute it here.  Crude but simple.
findMethodBind	:: Name -> Name 	-- Selector and method name
          	-> LHsBinds Name 	-- A group of bindings
		-> Maybe (LHsBind Name)	-- The binding, with meth_name replacing sel_name
findMethodBind sel_name meth_name binds
  = foldlBag mplus Nothing (mapBag f binds)
  where 
	f (L loc1 bind@(FunBind { fun_id = L loc2 op_name }))
	         | op_name == sel_name
		 = Just (L loc1 (bind { fun_id = L loc2 meth_name }))
	f _other = Nothing

---------------
tcInstanceMethodBody :: SkolemInfo -> Class -> [TcTyVar] -> [Inst]
	 	     -> TcThetaType -> [TcType]
		     -> Maybe (Inst, LHsBind Id) -> Id
		     -> Name		-- The local method name
          	     -> TcSigFun -> TcPragFun -> LHsBind Name 
          	     -> TcM (Id, LHsBinds Id)
tcInstanceMethodBody rigid_info clas tyvars dfun_dicts theta inst_tys
		     mb_this_bind sel_id  local_meth_name
		     sig_fn prag_fn bind@(L loc _)
  = do	{ let (sel_tyvars,sel_rho) = tcSplitForAllTys (idType sel_id)
	      rho_ty = ASSERT( length sel_tyvars == length inst_tys )
		       substTyWith sel_tyvars inst_tys sel_rho

	      (first_pred, local_meth_ty) = tcSplitPredFunTy_maybe rho_ty
			`orElse` pprPanic "tcInstanceMethod" (ppr sel_id)

	      local_meth_id = mkLocalId local_meth_name local_meth_ty
	      meth_ty 	    = mkSigmaTy tyvars theta local_meth_ty
	      sel_name	    = idName sel_id

		      -- The first predicate should be of form (C a b)
		      -- where C is the class in question
	; MASSERT( case getClassPredTys_maybe first_pred of
			{ Just (clas1, _tys) -> clas == clas1 ; Nothing -> False } )

		-- Typecheck the binding, first extending the envt
		-- so that when tcInstSig looks up the local_meth_id to find
		-- its signature, we'll find it in the environment
	; ((tc_bind, _), lie) <- getLIE $
		tcExtendIdEnv [local_meth_id] $
	        tcPolyBinds TopLevel sig_fn prag_fn 
			    NonRecursive NonRecursive
			    (unitBag bind)

	; meth_id <- case rigid_info of
		       ClsSkol _ -> do { dm_name <- lookupTopBndrRn (mkDefMethRdrName sel_name)
				       ; return (mkDefaultMethodId dm_name meth_ty) }
		       _other    -> do { meth_name <- newLocalName sel_name
				       ; return (mkLocalId meth_name meth_ty) }
    	
	; let (avails, this_dict_bind) 
		= case mb_this_bind of
		    Nothing	      -> (dfun_dicts, emptyBag)
		    Just (this, bind) -> (this : dfun_dicts, unitBag bind)

	; inst_loc <- getInstLoc (SigOrigin rigid_info)
	; lie_binds <- tcSimplifyCheck inst_loc tyvars avails lie

	; let full_bind = L loc $ 
			  AbsBinds tyvars dfun_lam_vars
     				  [(tyvars, meth_id, local_meth_id, [])]
				  (this_dict_bind `unionBags` lie_binds 
				   `unionBags` tc_bind)

	      dfun_lam_vars = map instToVar dfun_dicts	-- Includes equalities

        ; return (meth_id, unitBag full_bind) } 
\end{code}

Note [Polymorphic methods]
~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider
    class Foo a where
	op :: forall b. Ord b => a -> b -> b -> b
    instance Foo c => Foo [c] where
        op = e

When typechecking the binding 'op = e', we'll have a meth_id for op
whose type is
      op :: forall c. Foo c => forall b. Ord b => [c] -> b -> b -> b

So tcPolyBinds must be capable of dealing with nested polytypes; 
and so it is. See TcBinds.tcMonoBinds (with type-sig case).

Note [Silly default-method bind]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
When we pass the default method binding to the type checker, it must
look like    op2 = e
not  	     $dmop2 = e
otherwise the "$dm" stuff comes out error messages.  But we want the
"$dm" to come out in the interface file.  So we typecheck the former,
and wrap it in a let, thus
	  $dmop2 = let op2 = e in op2
This makes the error messages right.


%************************************************************************
%*									*
	Extracting generic instance declaration from class declarations
%*									*
%************************************************************************

@getGenericInstances@ extracts the generic instance declarations from a class
declaration.  For exmaple

	class C a where
	  op :: a -> a
	
	  op{ x+y } (Inl v)   = ...
	  op{ x+y } (Inr v)   = ...
	  op{ x*y } (v :*: w) = ...
	  op{ 1   } Unit      = ...

gives rise to the instance declarations

	instance C (x+y) where
	  op (Inl v)   = ...
	  op (Inr v)   = ...
	
	instance C (x*y) where
	  op (v :*: w) = ...

	instance C 1 where
	  op Unit      = ...


\begin{code}
mkGenericDefMethBind :: Class -> [Type] -> Id -> Name -> TcM (LHsBind Name)
mkGenericDefMethBind clas inst_tys sel_id meth_name
  = 	-- A generic default method
    	-- If the method is defined generically, we can only do the job if the
	-- instance declaration is for a single-parameter type class with
	-- a type constructor applied to type arguments in the instance decl
	-- 	(checkTc, so False provokes the error)
    do	{ checkTc (isJust maybe_tycon)
	 	  (badGenericInstance sel_id (notSimple inst_tys))
	; checkTc (tyConHasGenerics tycon)
	   	  (badGenericInstance sel_id (notGeneric tycon))

	; dflags <- getDOpts
	; liftIO (dumpIfSet_dyn dflags Opt_D_dump_deriv "Filling in method body"
		   (vcat [ppr clas <+> ppr inst_tys,
			  nest 2 (ppr sel_id <+> equals <+> ppr rhs)]))

		-- Rename it before returning it
	; (rn_rhs, _) <- rnLExpr rhs
        ; return (noLoc $ mkFunBind (noLoc meth_name) [mkSimpleMatch [] rn_rhs]) }
  where
    rhs = mkGenericRhs sel_id clas_tyvar tycon

	  -- The tycon is only used in the generic case, and in that
	  -- case we require that the instance decl is for a single-parameter
	  -- type class with type variable arguments:
	  --	instance (...) => C (T a b)
    clas_tyvar  = ASSERT (not (null (classTyVars clas))) head (classTyVars clas)
    Just tycon	= maybe_tycon
    maybe_tycon = case inst_tys of 
			[ty] -> case tcSplitTyConApp_maybe ty of
				  Just (tycon, arg_tys) | all tcIsTyVarTy arg_tys -> Just tycon
				  _    						  -> Nothing
			_ -> Nothing


---------------------------
getGenericInstances :: [LTyClDecl Name] -> TcM [InstInfo Name] 
getGenericInstances class_decls
  = do	{ gen_inst_infos <- mapM (addLocM get_generics) class_decls
	; let { gen_inst_info = concat gen_inst_infos }

	-- Return right away if there is no generic stuff
	; if null gen_inst_info then return []
	  else do 

	-- Otherwise print it out
	{ dflags <- getDOpts
	; liftIO (dumpIfSet_dyn dflags Opt_D_dump_deriv "Generic instances"
	         (vcat (map pprInstInfoDetails gen_inst_info)))	
	; return gen_inst_info }}

get_generics :: TyClDecl Name -> TcM [InstInfo Name]
get_generics decl@(ClassDecl {tcdLName = class_name, tcdMeths = def_methods})
  | null generic_binds
  = return [] -- The comon case: no generic default methods

  | otherwise	-- A source class decl with generic default methods
  = recoverM (return [])                                $
    tcAddDeclCtxt decl                                  $ do
    clas <- tcLookupLocatedClass class_name

	-- Group by type, and
	-- make an InstInfo out of each group
    let
	groups = groupWith listToBag generic_binds

    inst_infos <- mapM (mkGenericInstance clas) groups

	-- Check that there is only one InstInfo for each type constructor
  	-- The main way this can fail is if you write
	--	f {| a+b |} ... = ...
	--	f {| x+y |} ... = ...
	-- Then at this point we'll have an InstInfo for each
	--
	-- The class should be unary, which is why simpleInstInfoTyCon should be ok
    let
	tc_inst_infos :: [(TyCon, InstInfo Name)]
	tc_inst_infos = [(simpleInstInfoTyCon i, i) | i <- inst_infos]

	bad_groups = [group | group <- equivClassesByUniq get_uniq tc_inst_infos,
			      group `lengthExceeds` 1]
	get_uniq (tc,_) = getUnique tc

    mapM_ (addErrTc . dupGenericInsts) bad_groups

	-- Check that there is an InstInfo for each generic type constructor
    let
	missing = genericTyConNames `minusList` [tyConName tc | (tc,_) <- tc_inst_infos]

    checkTc (null missing) (missingGenericInstances missing)

    return inst_infos
  where
    generic_binds :: [(HsType Name, LHsBind Name)]
    generic_binds = getGenericBinds def_methods
get_generics decl = pprPanic "get_generics" (ppr decl)


---------------------------------
getGenericBinds :: LHsBinds Name -> [(HsType Name, LHsBind Name)]
  -- Takes a group of method bindings, finds the generic ones, and returns
  -- them in finite map indexed by the type parameter in the definition.
getGenericBinds binds = concat (map getGenericBind (bagToList binds))

getGenericBind :: LHsBindLR Name Name -> [(HsType Name, LHsBindLR Name Name)]
getGenericBind (L loc bind@(FunBind { fun_matches = MatchGroup matches ty }))
  = groupWith wrap (mapCatMaybes maybeGenericMatch matches)
  where
    wrap ms = L loc (bind { fun_matches = MatchGroup ms ty })
getGenericBind _
  = []

groupWith :: ([a] -> b) -> [(HsType Name, a)] -> [(HsType Name, b)]
groupWith _  [] 	 = []
groupWith op ((t,v):prs) = (t, op (v:vs)) : groupWith op rest
    where
      vs              = map snd this
      (this,rest)     = partition same_t prs
      same_t (t', _v) = t `eqPatType` t'

eqPatLType :: LHsType Name -> LHsType Name -> Bool
eqPatLType t1 t2 = unLoc t1 `eqPatType` unLoc t2

eqPatType :: HsType Name -> HsType Name -> Bool
-- A very simple equality function, only for 
-- type patterns in generic function definitions.
eqPatType (HsTyVar v1)       (HsTyVar v2)    	= v1==v2
eqPatType (HsAppTy s1 t1)    (HsAppTy s2 t2) 	= s1 `eqPatLType` s2 && t1 `eqPatLType` t2
eqPatType (HsOpTy s1 op1 t1) (HsOpTy s2 op2 t2) = s1 `eqPatLType` s2 && t1 `eqPatLType` t2 && unLoc op1 == unLoc op2
eqPatType (HsNumTy n1)	     (HsNumTy n2)	= n1 == n2
eqPatType (HsParTy t1)	     t2			= unLoc t1 `eqPatType` t2
eqPatType t1		     (HsParTy t2)	= t1 `eqPatType` unLoc t2
eqPatType _ _ = False

---------------------------------
mkGenericInstance :: Class
		  -> (HsType Name, LHsBinds Name)
		  -> TcM (InstInfo Name)

mkGenericInstance clas (hs_ty, binds) = do
  -- Make a generic instance declaration
  -- For example:	instance (C a, C b) => C (a+b) where { binds }

	-- Extract the universally quantified type variables
	-- and wrap them as forall'd tyvars, so that kind inference
	-- works in the standard way
    let
	sig_tvs = map (noLoc.UserTyVar) (nameSetToList (extractHsTyVars (noLoc hs_ty)))
	hs_forall_ty = noLoc $ mkExplicitHsForAllTy sig_tvs (noLoc []) (noLoc hs_ty)

	-- Type-check the instance type, and check its form
    forall_inst_ty <- tcHsSigType GenPatCtxt hs_forall_ty
    let
	(tyvars, inst_ty) = tcSplitForAllTys forall_inst_ty

    checkTc (validGenericInstanceType inst_ty)
            (badGenericInstanceType binds)

	-- Make the dictionary function.
    span <- getSrcSpanM
    overlap_flag <- getOverlapFlag
    dfun_name <- newDFunName clas [inst_ty] span
    let
	inst_theta = [mkClassPred clas [mkTyVarTy tv] | tv <- tyvars]
	dfun_id    = mkDictFunId dfun_name tyvars inst_theta clas [inst_ty]
	ispec	   = mkLocalInstance dfun_id overlap_flag

    return (InstInfo { iSpec = ispec, iBinds = VanillaInst binds [] False })
\end{code}


%************************************************************************
%*									*
		Error messages
%*									*
%************************************************************************

\begin{code}
tcAddDeclCtxt :: TyClDecl Name -> TcM a -> TcM a
tcAddDeclCtxt decl thing_inside
  = addErrCtxt ctxt thing_inside
  where
     thing | isClassDecl decl  = "class"
	   | isTypeDecl decl   = "type synonym" ++ maybeInst
	   | isDataDecl decl   = if tcdND decl == NewType 
				 then "newtype" ++ maybeInst
				 else "data type" ++ maybeInst
	   | isFamilyDecl decl = "family"
	   | otherwise         = panic "tcAddDeclCtxt/thing"

     maybeInst | isFamInstDecl decl = " instance"
	       | otherwise          = ""

     ctxt = hsep [ptext (sLit "In the"), text thing, 
		  ptext (sLit "declaration for"), quotes (ppr (tcdName decl))]

badMethodErr :: Outputable a => a -> Name -> SDoc
badMethodErr clas op
  = hsep [ptext (sLit "Class"), quotes (ppr clas), 
	  ptext (sLit "does not have a method"), quotes (ppr op)]

badATErr :: Class -> Name -> SDoc
badATErr clas at
  = hsep [ptext (sLit "Class"), quotes (ppr clas), 
	  ptext (sLit "does not have an associated type"), quotes (ppr at)]

omittedATWarn :: Name -> SDoc
omittedATWarn at
  = ptext (sLit "No explicit AT declaration for") <+> quotes (ppr at)

badGenericInstance :: Var -> SDoc -> SDoc
badGenericInstance sel_id because
  = sep [ptext (sLit "Can't derive generic code for") <+> quotes (ppr sel_id),
	 because]

notSimple :: [Type] -> SDoc
notSimple inst_tys
  = vcat [ptext (sLit "because the instance type(s)"), 
	  nest 2 (ppr inst_tys),
	  ptext (sLit "is not a simple type of form (T a1 ... an)")]

notGeneric :: TyCon -> SDoc
notGeneric tycon
  = vcat [ptext (sLit "because the instance type constructor") <+> quotes (ppr tycon) <+> 
	  ptext (sLit "was not compiled with -XGenerics")]

badGenericInstanceType :: LHsBinds Name -> SDoc
badGenericInstanceType binds
  = vcat [ptext (sLit "Illegal type pattern in the generic bindings"),
	  nest 4 (ppr binds)]

missingGenericInstances :: [Name] -> SDoc
missingGenericInstances missing
  = ptext (sLit "Missing type patterns for") <+> pprQuotedList missing
	  
dupGenericInsts :: [(TyCon, InstInfo a)] -> SDoc
dupGenericInsts tc_inst_infos
  = vcat [ptext (sLit "More than one type pattern for a single generic type constructor:"),
	  nest 4 (vcat (map ppr_inst_ty tc_inst_infos)),
	  ptext (sLit "All the type patterns for a generic type constructor must be identical")
    ]
  where 
    ppr_inst_ty (_,inst) = ppr (simpleInstInfoTy inst)

mixedGenericErr :: Name -> SDoc
mixedGenericErr op
  = ptext (sLit "Can't mix generic and non-generic equations for class method") <+> quotes (ppr op)
\end{code}
