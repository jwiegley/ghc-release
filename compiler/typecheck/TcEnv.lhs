%
% (c) The University of Glasgow 2006
%

\begin{code}
module TcEnv(
	TyThing(..), TcTyThing(..), TcId,

	-- Instance environment, and InstInfo type
	InstInfo(..), iDFunId, pprInstInfo, pprInstInfoDetails,
	simpleInstInfoClsTy, simpleInstInfoTy, simpleInstInfoTyCon, 
	InstBindings(..),

	-- Global environment
	tcExtendGlobalEnv, setGlobalTypeEnv,
	tcExtendGlobalValEnv,
	tcLookupLocatedGlobal,	tcLookupGlobal, 
	tcLookupField, tcLookupTyCon, tcLookupClass, tcLookupDataCon,
	tcLookupLocatedGlobalId, tcLookupLocatedTyCon,
	tcLookupLocatedClass, tcLookupFamInst,
	
	-- Local environment
	tcExtendKindEnv, tcExtendKindEnvTvs,
	tcExtendTyVarEnv, tcExtendTyVarEnv2, 
	tcExtendGhciEnv,
	tcExtendIdEnv, tcExtendIdEnv1, tcExtendIdEnv2, 
	tcLookup, tcLookupLocated, tcLookupLocalIds, 
	tcLookupId, tcLookupTyVar, getScopedTyVarBinds,
	lclEnvElts, getInLocalScope, findGlobals, 
	wrongThingErr, pprBinders,

	tcExtendRecEnv,    	-- For knot-tying

	-- Rules
 	tcExtendRules,

	-- Global type variables
	tcGetGlobalTyVars,

	-- Template Haskell stuff
	checkWellStaged, spliceOK, bracketOK, tcMetaTy, thLevel, 
	topIdLvl, thTopLevelId, thRnBrack, isBrackStage,

	-- New Ids
	newLocalName, newDFunName, newFamInstTyConName, 
	mkStableIdFromString, mkStableIdFromName
  ) where

#include "HsVersions.h"

import HsSyn
import TcIface
import IfaceEnv
import TcRnMonad
import TcMType
import TcType
-- import TcSuspension
import qualified Type
import Id
import Var
import VarSet
import VarEnv
import RdrName
import InstEnv
import FamInstEnv
import DataCon
import TyCon
import TypeRep
import Class
import Name
import NameEnv
import OccName
import HscTypes
import SrcLoc
import Outputable
import Maybes
import Unique
import FastString
\end{code}


%************************************************************************
%*									*
%*			tcLookupGlobal					*
%*									*
%************************************************************************

Using the Located versions (eg. tcLookupLocatedGlobal) is preferred,
unless you know that the SrcSpan in the monad is already set to the
span of the Name.

\begin{code}
tcLookupLocatedGlobal :: Located Name -> TcM TyThing
-- c.f. IfaceEnvEnv.tcIfaceGlobal
tcLookupLocatedGlobal name
  = addLocM tcLookupGlobal name

tcLookupGlobal :: Name -> TcM TyThing
-- The Name is almost always an ExternalName, but not always
-- In GHCi, we may make command-line bindings (ghci> let x = True)
-- that bind a GlobalId, but with an InternalName
tcLookupGlobal name
  = do	{ env <- getGblEnv
	
		-- Try local envt
	; case lookupNameEnv (tcg_type_env env) name of { 
		Just thing -> return thing ;
		Nothing	   -> do 
	 
		-- Try global envt
	{ hsc_env <- getTopEnv
        ; mb_thing <- liftIO (lookupTypeHscEnv hsc_env name)
	; case mb_thing of  {
	    Just thing -> return thing ;
	    Nothing    -> do

		-- Should it have been in the local envt?
	{ case nameModule_maybe name of
		Nothing -> notFound name env -- Internal names can happen in GHCi

		Just mod | mod == tcg_mod env 	-- Names from this module 
			 -> notFound name env -- should be in tcg_type_env
			 | otherwise
		         -> tcImportDecl name	-- Go find it in an interface
	}}}}}

tcLookupField :: Name -> TcM Id		-- Returns the selector Id
tcLookupField name = do
    thing <- tcLookup name	-- Note [Record field lookup]
    case thing of
	AGlobal (AnId id) -> return id
	thing -> wrongThingErr "field name" thing name

{- Note [Record field lookup]
   ~~~~~~~~~~~~~~~~~~~~~~~~~~
You might think we should have tcLookupGlobal here, since record fields
are always top level.  But consider
	f = e { f = True }
Then the renamer (which does not keep track of what is a record selector
and what is not) will rename the definition thus
	f_7 = e { f_7 = True }
Now the type checker will find f_7 in the *local* type environment, not
the global one. It's wrong, of course, but we want to report a tidy
error, not in TcEnv.notFound.  -}

tcLookupDataCon :: Name -> TcM DataCon
tcLookupDataCon name = do
    thing <- tcLookupGlobal name
    case thing of
	ADataCon con -> return con
	_            -> wrongThingErr "data constructor" (AGlobal thing) name

tcLookupClass :: Name -> TcM Class
tcLookupClass name = do
    thing <- tcLookupGlobal name
    case thing of
	AClass cls -> return cls
	_          -> wrongThingErr "class" (AGlobal thing) name

tcLookupTyCon :: Name -> TcM TyCon
tcLookupTyCon name = do
    thing <- tcLookupGlobal name
    case thing of
	ATyCon tc -> return tc
	_         -> wrongThingErr "type constructor" (AGlobal thing) name

tcLookupLocatedGlobalId :: Located Name -> TcM Id
tcLookupLocatedGlobalId = addLocM tcLookupId

tcLookupLocatedClass :: Located Name -> TcM Class
tcLookupLocatedClass = addLocM tcLookupClass

tcLookupLocatedTyCon :: Located Name -> TcM TyCon
tcLookupLocatedTyCon = addLocM tcLookupTyCon

-- Look up the instance tycon of a family instance.
--
-- The match must be unique - ie, match exactly one instance - but the 
-- type arguments used for matching may be more specific than those of 
-- the family instance declaration.
--
-- Return the instance tycon and its type instance.  For example, if we have
--
--  tcLookupFamInst 'T' '[Int]' yields (':R42T', 'Int')
--
-- then we have a coercion (ie, type instance of family instance coercion)
--
--  :Co:R42T Int :: T [Int] ~ :R42T Int
--
-- which implies that :R42T was declared as 'data instance T [a]'.
--
tcLookupFamInst :: TyCon -> [Type] -> TcM (Maybe (TyCon, [Type]))
tcLookupFamInst tycon tys
  | not (isOpenTyCon tycon)
  = return Nothing
  | otherwise
  = do { env <- getGblEnv
       ; eps <- getEps
       ; let instEnv = (eps_fam_inst_env eps, tcg_fam_inst_env env)
       ; case lookupFamInstEnv instEnv tycon tys of
	   [(fam_inst, rep_tys)] -> return $ Just (famInstTyCon fam_inst, 
                                                   rep_tys)
	   _                     -> return Nothing
       }
\end{code}

%************************************************************************
%*									*
		Extending the global environment
%*									*
%************************************************************************


\begin{code}
setGlobalTypeEnv :: TcGblEnv -> TypeEnv -> TcM TcGblEnv
-- Use this to update the global type env 
-- It updates both  * the normal tcg_type_env field
-- 	   	    * the tcg_type_env_var field seen by interface files
setGlobalTypeEnv tcg_env new_type_env
  = do  {     -- Sync the type-envt variable seen by interface files
    	   writeMutVar (tcg_type_env_var tcg_env) new_type_env
	 ; return (tcg_env { tcg_type_env = new_type_env }) }

tcExtendGlobalEnv :: [TyThing] -> TcM r -> TcM r
  -- Given a mixture of Ids, TyCons, Classes, all from the
  -- module being compiled, extend the global environment
tcExtendGlobalEnv things thing_inside
   = do	{ tcg_env <- getGblEnv
	; let ge'  = extendTypeEnvList (tcg_type_env tcg_env) things
	; tcg_env' <- setGlobalTypeEnv tcg_env ge'
	; setGblEnv tcg_env' thing_inside }

tcExtendGlobalValEnv :: [Id] -> TcM a -> TcM a
  -- Same deal as tcExtendGlobalEnv, but for Ids
tcExtendGlobalValEnv ids thing_inside 
  = tcExtendGlobalEnv [AnId id | id <- ids] thing_inside

tcExtendRecEnv :: [(Name,TyThing)] -> TcM r -> TcM r
-- Extend the global environments for the type/class knot tying game
-- Just like tcExtendGlobalEnv, except the argument is a list of pairs
tcExtendRecEnv gbl_stuff thing_inside
 = do  { tcg_env <- getGblEnv
       ; let ge' = extendNameEnvList (tcg_type_env tcg_env) gbl_stuff 
       ; tcg_env' <- setGlobalTypeEnv tcg_env ge'
       ; setGblEnv tcg_env' thing_inside }
\end{code}


%************************************************************************
%*									*
\subsection{The local environment}
%*									*
%************************************************************************

\begin{code}
tcLookupLocated :: Located Name -> TcM TcTyThing
tcLookupLocated = addLocM tcLookup

tcLookup :: Name -> TcM TcTyThing
tcLookup name = do
    local_env <- getLclEnv
    case lookupNameEnv (tcl_env local_env) name of
	Just thing -> return thing
	Nothing    -> AGlobal <$> tcLookupGlobal name

tcLookupTyVar :: Name -> TcM TcTyVar
tcLookupTyVar name = do
    thing <- tcLookup name
    case thing of
	ATyVar _ ty -> return (tcGetTyVar "tcLookupTyVar" ty)
	_           -> pprPanic "tcLookupTyVar" (ppr name)

tcLookupId :: Name -> TcM Id
-- Used when we aren't interested in the binding level, nor refinement. 
-- The "no refinement" part means that we return the un-refined Id regardless
-- 
-- The Id is never a DataCon. (Why does that matter? see TcExpr.tcId)
tcLookupId name = do
    thing <- tcLookup name
    case thing of
        ATcId { tct_id = id} -> return id
        AGlobal (AnId id)    -> return id
        _                    -> pprPanic "tcLookupId" (ppr name)

tcLookupLocalIds :: [Name] -> TcM [TcId]
-- We expect the variables to all be bound, and all at
-- the same level as the lookup.  Only used in one place...
tcLookupLocalIds ns = do
    env <- getLclEnv
    return (map (lookup (tcl_env env) (thLevel (tcl_th_ctxt env))) ns)
  where
    lookup lenv lvl name 
	= case lookupNameEnv lenv name of
		Just (ATcId { tct_id = id, tct_level = lvl1 }) 
			-> ASSERT( lvl == lvl1 ) id
		_ -> pprPanic "tcLookupLocalIds" (ppr name)

lclEnvElts :: TcLclEnv -> [TcTyThing]
lclEnvElts env = nameEnvElts (tcl_env env)

getInLocalScope :: TcM (Name -> Bool)
  -- Ids only
getInLocalScope = do
    env <- getLclEnv
    let lcl_env = tcl_env env
    return (`elemNameEnv` lcl_env)
\end{code}

\begin{code}
tcExtendKindEnv :: [(Name, TcKind)] -> TcM r -> TcM r
tcExtendKindEnv things thing_inside
  = updLclEnv upd thing_inside
  where
    upd lcl_env = lcl_env { tcl_env = extend (tcl_env lcl_env) }
    extend env  = extendNameEnvList env [(n, AThing k) | (n,k) <- things]

tcExtendKindEnvTvs :: [LHsTyVarBndr Name] -> TcM r -> TcM r
tcExtendKindEnvTvs bndrs thing_inside
  = updLclEnv upd thing_inside
  where
    upd lcl_env = lcl_env { tcl_env = extend (tcl_env lcl_env) }
    extend env  = extendNameEnvList env pairs
    pairs       = [(n, AThing k) | L _ (KindedTyVar n k) <- bndrs]

tcExtendTyVarEnv :: [TyVar] -> TcM r -> TcM r
tcExtendTyVarEnv tvs thing_inside
  = tcExtendTyVarEnv2 [(tyVarName tv, mkTyVarTy tv) | tv <- tvs] thing_inside

tcExtendTyVarEnv2 :: [(Name,TcType)] -> TcM r -> TcM r
tcExtendTyVarEnv2 binds thing_inside = do
    env@(TcLclEnv {tcl_env = le,
                   tcl_tyvars = gtvs,
                   tcl_rdr = rdr_env}) <- getLclEnv
    let
	rdr_env'   = extendLocalRdrEnv rdr_env (map fst binds)
	new_tv_set = tcTyVarsOfTypes (map snd binds)
 	le'        = extendNameEnvList le [(name, ATyVar name ty) | (name, ty) <- binds]

	-- It's important to add the in-scope tyvars to the global tyvar set
	-- as well.  Consider
	--	f (_::r) = let g y = y::r in ...
	-- Here, g mustn't be generalised.  This is also important during
	-- class and instance decls, when we mustn't generalise the class tyvars
	-- when typechecking the methods.
    gtvs' <- tc_extend_gtvs gtvs new_tv_set
    setLclEnv (env {tcl_env = le', tcl_tyvars = gtvs', tcl_rdr = rdr_env'}) thing_inside

getScopedTyVarBinds :: TcM [(Name, TcType)]
getScopedTyVarBinds
  = do	{ lcl_env <- getLclEnv
	; return [(name, ty) | ATyVar name ty <- nameEnvElts (tcl_env lcl_env)] }
\end{code}


\begin{code}
tcExtendIdEnv :: [TcId] -> TcM a -> TcM a
tcExtendIdEnv ids thing_inside = tcExtendIdEnv2 [(idName id, id) | id <- ids] thing_inside

tcExtendIdEnv1 :: Name -> TcId -> TcM a -> TcM a
tcExtendIdEnv1 name id thing_inside = tcExtendIdEnv2 [(name,id)] thing_inside

tcExtendIdEnv2 :: [(Name,TcId)] -> TcM a -> TcM a
-- Invariant: the TcIds are fully zonked (see tcExtendIdEnv above)
tcExtendIdEnv2 names_w_ids thing_inside
  = do	{ env <- getLclEnv
	; tc_extend_local_id_env env (thLevel (tcl_th_ctxt env)) names_w_ids thing_inside }

tcExtendGhciEnv :: [TcId] -> TcM a -> TcM a
-- Used to bind Ids for GHCi identifiers bound earlier in the user interaction
-- Note especially that we bind them at TH level 'impLevel'.  That's because it's
-- OK to use a variable bound earlier in the interaction in a splice, becuase
-- GHCi has already compiled it to bytecode
tcExtendGhciEnv ids thing_inside
  = do	{ env <- getLclEnv
	; tc_extend_local_id_env env impLevel [(idName id, id) | id <- ids] thing_inside }

tc_extend_local_id_env		-- This is the guy who does the work
	:: TcLclEnv
	-> ThLevel
	-> [(Name,TcId)]
	-> TcM a -> TcM a
-- Invariant: the TcIds are fully zonked. Reasons:
--	(a) The kinds of the forall'd type variables are defaulted
--	    (see Kind.defaultKind, done in zonkQuantifiedTyVar)
--	(b) There are no via-Indirect occurrences of the bound variables
--	    in the types, because instantiation does not look through such things
--	(c) The call to tyVarsOfTypes is ok without looking through refs

tc_extend_local_id_env env th_lvl names_w_ids thing_inside
  = do	{ traceTc (text "env2")
	; traceTc (text "env3" <+> ppr extra_env)
	; gtvs' <- tc_extend_gtvs (tcl_tyvars env) extra_global_tyvars
	; let env' = env {tcl_env = le', tcl_tyvars = gtvs', tcl_rdr = rdr_env'}
	; setLclEnv env' thing_inside }
  where
    extra_global_tyvars = tcTyVarsOfTypes [idType id | (_,id) <- names_w_ids]
    extra_env	    = [ (name, ATcId { tct_id = id, 
    				       tct_level = th_lvl,
    				       tct_type = id_ty, 
    				       tct_co = case isRefineableTy id_ty of
						  (True,_) -> Unrefineable
						  (_,True) -> Rigid idHsWrapper
						  _        -> Wobbly})
    		      | (name,id) <- names_w_ids, let id_ty = idType id]
    le'		    = extendNameEnvList (tcl_env env) extra_env
    rdr_env'	    = extendLocalRdrEnv (tcl_rdr env) [name | (name,_) <- names_w_ids]
\end{code}


\begin{code}
-----------------------
-- findGlobals looks at the value environment and finds values
-- whose types mention the offending type variable.  It has to be 
-- careful to zonk the Id's type first, so it has to be in the monad.
-- We must be careful to pass it a zonked type variable, too.

findGlobals :: TcTyVarSet
            -> TidyEnv 
            -> TcM (TidyEnv, [SDoc])

findGlobals tvs tidy_env = do
    lcl_env <- getLclEnv
    go tidy_env [] (lclEnvElts lcl_env)
  where
    go tidy_env acc [] = return (tidy_env, acc)
    go tidy_env acc (thing : things) = do
        (tidy_env1, maybe_doc) <- find_thing ignore_it tidy_env thing
	case maybe_doc of
	  Just d  -> go tidy_env1 (d:acc) things
	  Nothing -> go tidy_env1 acc     things

    ignore_it ty = tvs `disjointVarSet` tyVarsOfType ty

-----------------------
find_thing :: (TcType -> Bool) -> TidyEnv -> TcTyThing
           -> TcM (TidyEnv, Maybe SDoc)
find_thing ignore_it tidy_env (ATcId { tct_id = id }) = do
    id_ty <- zonkTcType  (idType id)
    if ignore_it id_ty then
	return (tidy_env, Nothing)
     else let
	(tidy_env', tidy_ty) = tidyOpenType tidy_env id_ty
	msg = sep [ppr id <+> dcolon <+> ppr tidy_ty, 
		   nest 2 (parens (ptext (sLit "bound at") <+>
			 	   ppr (getSrcLoc id)))]
     in
      return (tidy_env', Just msg)

find_thing ignore_it tidy_env (ATyVar tv ty) = do
    tv_ty <- zonkTcType ty
    if ignore_it tv_ty then
	return (tidy_env, Nothing)
     else let
	-- The name tv is scoped, so we don't need to tidy it
	(tidy_env1, tidy_ty) = tidyOpenType  tidy_env tv_ty
	msg = sep [ptext (sLit "Scoped type variable") <+> quotes (ppr tv) <+> eq_stuff, nest 2 bound_at]

	eq_stuff | Just tv' <- Type.getTyVar_maybe tv_ty, 
		   getOccName tv == getOccName tv' = empty
		 | otherwise = equals <+> ppr tidy_ty
		-- It's ok to use Type.getTyVar_maybe because ty is zonked by now
	bound_at = parens $ ptext (sLit "bound at:") <+> ppr (getSrcLoc tv)
     in
       return (tidy_env1, Just msg)

find_thing _ _ thing = pprPanic "find_thing" (ppr thing)
\end{code}

%************************************************************************
%*									*
\subsection{The global tyvars}
%*									*
%************************************************************************

\begin{code}
tc_extend_gtvs :: IORef VarSet -> VarSet -> TcM (IORef VarSet)
tc_extend_gtvs gtvs extra_global_tvs = do
    global_tvs <- readMutVar gtvs
    newMutVar (global_tvs `unionVarSet` extra_global_tvs)
\end{code}

@tcGetGlobalTyVars@ returns a fully-zonked set of tyvars free in the environment.
To improve subsequent calls to the same function it writes the zonked set back into
the environment.

\begin{code}
tcGetGlobalTyVars :: TcM TcTyVarSet
tcGetGlobalTyVars = do
    (TcLclEnv {tcl_tyvars = gtv_var}) <- getLclEnv
    gbl_tvs  <- readMutVar gtv_var
    gbl_tvs' <- zonkTcTyVarsAndFV (varSetElems gbl_tvs)
    writeMutVar gtv_var gbl_tvs'
    return gbl_tvs'
\end{code}


%************************************************************************
%*									*
\subsection{Rules}
%*									*
%************************************************************************

\begin{code}
tcExtendRules :: [LRuleDecl Id] -> TcM a -> TcM a
	-- Just pop the new rules into the EPS and envt resp
	-- All the rules come from an interface file, not soruce
	-- Nevertheless, some may be for this module, if we read
	-- its interface instead of its source code
tcExtendRules lcl_rules thing_inside
 = do { env <- getGblEnv
      ; let
	  env' = env { tcg_rules = lcl_rules ++ tcg_rules env }
      ; setGblEnv env' thing_inside }
\end{code}


%************************************************************************
%*									*
		Meta level
%*									*
%************************************************************************

\begin{code}
instance Outputable ThStage where
   ppr Comp	     = text "Comp"
   ppr (Brack l _ _) = text "Brack" <+> int l
   ppr (Splice l)    = text "Splice" <+> int l


thLevel :: ThStage -> ThLevel
thLevel Comp	      = topLevel
thLevel (Splice l)    = l
thLevel (Brack l _ _) = l


checkWellStaged :: SDoc		-- What the stage check is for
		-> ThLevel 	-- Binding level (increases inside brackets)
	        -> ThStage	-- Use stage
		-> TcM ()	-- Fail if badly staged, adding an error
checkWellStaged pp_thing bind_lvl use_stage
  | use_lvl >= bind_lvl 	-- OK! Used later than bound
  = return ()			-- E.g.  \x -> [| $(f x) |]

  | bind_lvl == topLevel	-- GHC restriction on top level splices
  = failWithTc $ 
    sep [ptext (sLit "GHC stage restriction:") <+>  pp_thing,
	 nest 2 (ptext (sLit "is used in a top-level splice, and must be imported, not defined locally"))]

  | otherwise			-- Badly staged
  = failWithTc $ 		-- E.g.  \x -> $(f x)
    ptext (sLit "Stage error:") <+> pp_thing <+> 
	hsep   [ptext (sLit "is bound at stage") <+> ppr bind_lvl,
		ptext (sLit "but used at stage") <+> ppr use_lvl]
  where
    use_lvl = thLevel use_stage


topIdLvl :: Id -> ThLevel
-- Globals may either be imported, or may be from an earlier "chunk" 
-- (separated by declaration splices) of this module.  The former
--  *can* be used inside a top-level splice, but the latter cannot.
-- Hence we give the former impLevel, but the latter topLevel
-- E.g. this is bad:
--	x = [| foo |]
--	$( f x )
-- By the time we are prcessing the $(f x), the binding for "x" 
-- will be in the global env, not the local one.
topIdLvl id | isLocalId id = topLevel
	    | otherwise    = impLevel

-- Indicates the legal transitions on bracket( [| |] ).
bracketOK :: ThStage -> Maybe ThLevel
bracketOK (Brack _ _ _) = Nothing	-- Bracket illegal inside a bracket
bracketOK stage         = Just (thLevel stage + 1)

-- Indicates the legal transitions on splice($).
spliceOK :: ThStage -> Maybe ThLevel
spliceOK (Splice _) = Nothing	-- Splice illegal inside splice
spliceOK stage      = Just (thLevel stage - 1)

tcMetaTy :: Name -> TcM Type
-- Given the name of a Template Haskell data type, 
-- return the type
-- E.g. given the name "Expr" return the type "Expr"
tcMetaTy tc_name = do
    t <- tcLookupTyCon tc_name
    return (mkTyConApp t [])

thRnBrack :: ThStage
-- Used *only* to indicate that we are inside a TH bracket during renaming
-- Tested by TcEnv.isBrackStage
-- See Note [Top-level Names in Template Haskell decl quotes]
thRnBrack = Brack (panic "thRnBrack1") (panic "thRnBrack2") (panic "thRnBrack3") 

isBrackStage :: ThStage -> Bool
isBrackStage (Brack {}) = True
isBrackStage _other     = False

thTopLevelId :: Id -> Bool
-- See Note [What is a top-level Id?] in TcSplice
thTopLevelId id = isGlobalId id || isExternalName (idName id)
\end{code}


%************************************************************************
%*									*
\subsection{The InstInfo type}
%*									*
%************************************************************************

The InstInfo type summarises the information in an instance declaration

    instance c => k (t tvs) where b

It is used just for *local* instance decls (not ones from interface files).
But local instance decls includes
	- derived ones
	- generic ones
as well as explicit user written ones.

\begin{code}
data InstInfo a
  = InstInfo {
      iSpec  :: Instance,		-- Includes the dfun id.  Its forall'd type 
      iBinds :: InstBindings a		-- variables scope over the stuff in InstBindings!
    }

iDFunId :: InstInfo a -> DFunId
iDFunId info = instanceDFunId (iSpec info)

data InstBindings a
  = VanillaInst 		-- The normal case
	(LHsBinds a)		-- Bindings for the instance methods
	[LSig a]		-- User pragmas recorded for generating 
				-- specialised instances

  | NewTypeDerived              -- Used for deriving instances of newtypes, where the
				-- witness dictionary is identical to the argument 
				-- dictionary.  Hence no bindings, no pragmas.

pprInstInfo :: InstInfo a -> SDoc
pprInstInfo info = vcat [ptext (sLit "InstInfo:") <+> ppr (idType (iDFunId info))]

pprInstInfoDetails :: OutputableBndr a => InstInfo a -> SDoc
pprInstInfoDetails info = pprInstInfo info $$ nest 2 (details (iBinds info))
  where
    details (VanillaInst b _) = pprLHsBinds b
    details NewTypeDerived    = text "Derived from the representation type"

simpleInstInfoClsTy :: InstInfo a -> (Class, Type)
simpleInstInfoClsTy info = case instanceHead (iSpec info) of
                           (_, _, cls, [ty]) -> (cls, ty)
                           _ -> panic "simpleInstInfoClsTy"

simpleInstInfoTy :: InstInfo a -> Type
simpleInstInfoTy info = snd (simpleInstInfoClsTy info)

simpleInstInfoTyCon :: InstInfo a -> TyCon
  -- Gets the type constructor for a simple instance declaration,
  -- i.e. one of the form 	instance (...) => C (T a b c) where ...
simpleInstInfoTyCon inst = tcTyConAppTyCon (simpleInstInfoTy inst)
\end{code}

Make a name for the dict fun for an instance decl.  It's an *external*
name, like otber top-level names, and hence must be made with newGlobalBinder.

\begin{code}
newDFunName :: Class -> [Type] -> SrcSpan -> TcM Name
newDFunName clas (ty:_) loc
  = do	{ index   <- nextDFunIndex
	; is_boot <- tcIsHsBoot
	; mod     <- getModule
	; let info_string = occNameString (getOccName clas) ++ 
			    occNameString (getDFunTyKey ty)
	      dfun_occ = mkDFunOcc info_string is_boot index

	; newGlobalBinder mod dfun_occ loc }

newDFunName clas [] loc = pprPanic "newDFunName" (ppr clas <+> ppr loc)
\end{code}

Make a name for the representation tycon of a family instance.  It's an
*external* name, like otber top-level names, and hence must be made with
newGlobalBinder.

\begin{code}
newFamInstTyConName :: Name -> SrcSpan -> TcM Name
newFamInstTyConName tc_name loc
  = do	{ index <- nextDFunIndex
	; mod   <- getModule
	; let occ = nameOccName tc_name
	; newGlobalBinder mod (mkInstTyTcOcc index occ) loc }
\end{code}

Stable names used for foreign exports and annotations.
For stable names, the name must be unique (see #1533).  If the
same thing has several stable Ids based on it, the
top-level bindings generated must not have the same name.
Hence we create an External name (doesn't change), and we
append a Unique to the string right here.

\begin{code}
mkStableIdFromString :: String -> Type -> SrcSpan -> (OccName -> OccName) -> TcM TcId
mkStableIdFromString str sig_ty loc occ_wrapper = do
    uniq <- newUnique
    mod <- getModule
    let uniq_str = showSDoc (pprUnique uniq) :: String
        occ = mkVarOcc (str ++ '_' : uniq_str) :: OccName
        gnm = mkExternalName uniq mod (occ_wrapper occ) loc :: Name
	id  = mkExportedLocalId gnm sig_ty :: Id
    return id

mkStableIdFromName :: Name -> Type -> SrcSpan -> (OccName -> OccName) -> TcM TcId
mkStableIdFromName nm = mkStableIdFromString (getOccString nm)
\end{code}

%************************************************************************
%*									*
\subsection{Errors}
%*									*
%************************************************************************

\begin{code}
pprBinders :: [Name] -> SDoc
-- Used in error messages
-- Use quotes for a single one; they look a bit "busy" for several
pprBinders [bndr] = quotes (ppr bndr)
pprBinders bndrs  = pprWithCommas ppr bndrs

notFound :: Name -> TcGblEnv -> TcM TyThing
notFound name env
  = failWithTc (vcat[ptext (sLit "GHC internal error:") <+> quotes (ppr name) <+> 
                     ptext (sLit "is not in scope during type checking, but it passed the renamer"),
                     ptext (sLit "tcg_type_env of environment:") <+> ppr (tcg_type_env env)]
                    )

wrongThingErr :: String -> TcTyThing -> Name -> TcM a
wrongThingErr expected thing name
  = failWithTc (pprTcTyThingCategory thing <+> quotes (ppr name) <+> 
		ptext (sLit "used as a") <+> text expected)
\end{code}
