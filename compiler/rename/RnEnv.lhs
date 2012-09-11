\%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-2006
%
\section[RnEnv]{Environment manipulation for the renamer monad}

\begin{code}
module RnEnv ( 
	newTopSrcBinder, lookupFamInstDeclBndr,
	lookupLocatedTopBndrRn, lookupTopBndrRn,
	lookupLocatedOccRn, lookupOccRn, 
	lookupLocatedGlobalOccRn, lookupGlobalOccRn,
	lookupLocalDataTcNames, lookupSrcOcc_maybe,
	lookupSigOccRn,
	lookupFixityRn, lookupTyFixityRn, 
	lookupInstDeclBndr, lookupRecordBndr, lookupConstructorFields,
	lookupSyntaxName, lookupSyntaxTable, lookupImportedName,
	lookupGreRn, lookupGreLocalRn, lookupGreRn_maybe,
	getLookupOccRn,

	newLocalsRn, newIPNameRn,
	bindLocalNames, bindLocalNamesFV, 
	MiniFixityEnv, emptyFsEnv, extendFsEnv, lookupFsEnv,
	bindLocalNamesFV_WithFixities,
	bindLocatedLocalsFV, bindLocatedLocalsRn,
	bindSigTyVarsFV, bindPatSigTyVars, bindPatSigTyVarsFV,
	bindTyVarsRn, extendTyVarEnvFVRn,

	checkDupRdrNames, checkDupNames, checkShadowedNames, 
	checkDupAndShadowedRdrNames,
	mapFvRn, mapFvRnCPS,
	warnUnusedMatches, warnUnusedModules, warnUnusedImports, 
	warnUnusedTopBinds, warnUnusedLocalBinds,
	dataTcOccs, unknownNameErr, perhapsForallMsg
    ) where

#include "HsVersions.h"

import LoadIface	( loadInterfaceForName, loadSrcInterface )
import IfaceEnv		( lookupOrig, newGlobalBinder, newIPName )
import HsSyn
import RdrHsSyn		( extractHsTyRdrTyVars )
import RdrName
import HscTypes		( availNames, ModIface(..), FixItem(..), lookupFixity)
import TcEnv		( tcLookupDataCon, isBrackStage )
import TcRnMonad
import Name		( Name, nameIsLocalOrFrom, mkInternalName, isWiredInName,
			  nameSrcLoc, nameSrcSpan, nameOccName, nameModule, isExternalName )
import NameSet
import NameEnv
import LazyUniqFM
import DataCon		( dataConFieldLabels )
import OccName
import Module		( Module, ModuleName )
import PrelNames	( mkUnboundName, rOOT_MAIN, iNTERACTIVE, 
			  consDataConKey, hasKey, forall_tv_RDR )
import UniqSupply
import BasicTypes	( IPName, mapIPName, Fixity )
import ErrUtils		( Message )
import SrcLoc
import Outputable
import Util
import Maybes
import ListSetOps	( removeDups )
import List		( nubBy )
import DynFlags
import FastString
import Control.Monad
\end{code}

\begin{code}
-- XXX
thenM :: Monad a => a b -> (b -> a c) -> a c
thenM = (>>=)

thenM_ :: Monad a => a b -> a c -> a c
thenM_ = (>>)

returnM :: Monad m => a -> m a
returnM = return

mappM :: (Monad m) => (a -> m b) -> [a] -> m [b]
mappM = mapM

mappM_ :: (Monad m) => (a -> m b) -> [a] -> m ()
mappM_ = mapM_

checkM :: Monad m => Bool -> m () -> m ()
checkM = unless
\end{code}

%*********************************************************
%*							*
		Source-code binders
%*							*
%*********************************************************

\begin{code}
newTopSrcBinder :: Module -> Located RdrName -> RnM Name
newTopSrcBinder this_mod (L loc rdr_name)
  | Just name <- isExact_maybe rdr_name
  =	-- This is here to catch 
	--   (a) Exact-name binders created by Template Haskell
	--   (b) The PrelBase defn of (say) [] and similar, for which
	--	 the parser reads the special syntax and returns an Exact RdrName
   	-- We are at a binding site for the name, so check first that it 
	-- the current module is the correct one; otherwise GHC can get
	-- very confused indeed. This test rejects code like
	--	data T = (,) Int Int
	-- unless we are in GHC.Tup
    ASSERT2( isExternalName name,  ppr name )
    do	{ checkM (this_mod == nameModule name)
	         (addErrAt loc (badOrigBinding rdr_name))
	; return name }


  | Just (rdr_mod, rdr_occ) <- isOrig_maybe rdr_name
  = do	{ checkM (rdr_mod == this_mod || rdr_mod == rOOT_MAIN)
	         (addErrAt loc (badOrigBinding rdr_name))
	-- When reading External Core we get Orig names as binders, 
	-- but they should agree with the module gotten from the monad
	--
	-- We can get built-in syntax showing up here too, sadly.  If you type
	--	data T = (,,,)
	-- the constructor is parsed as a type, and then RdrHsSyn.tyConToDataCon 
	-- uses setRdrNameSpace to make it into a data constructors.  At that point
	-- the nice Exact name for the TyCon gets swizzled to an Orig name.
	-- Hence the badOrigBinding error message.
	--
	-- Except for the ":Main.main = ..." definition inserted into 
	-- the Main module; ugh!

	-- Because of this latter case, we call newGlobalBinder with a module from 
	-- the RdrName, not from the environment.  In principle, it'd be fine to 
	-- have an arbitrary mixture of external core definitions in a single module,
	-- (apart from module-initialisation issues, perhaps).
	; newGlobalBinder rdr_mod rdr_occ loc }
		--TODO, should pass the whole span

  | otherwise
  = do	{ checkM (not (isQual rdr_name))
	         (addErrAt loc (badQualBndrErr rdr_name))
	 	-- Binders should not be qualified; if they are, and with a different
		-- module name, we we get a confusing "M.T is not in scope" error later

	; stage <- getStage
	; if isBrackStage stage then
	        -- We are inside a TH bracket, so make an *Internal* name
		-- See Note [Top-level Names in Template Haskell decl quotes] in RnNames
	     do { uniq <- newUnique
	        ; return (mkInternalName uniq (rdrNameOcc rdr_name) loc) } 
	  else	
	  	-- Normal case
	     newGlobalBinder this_mod (rdrNameOcc rdr_name) loc }
\end{code}

%*********************************************************
%*							*
	Source code occurrences
%*							*
%*********************************************************

Looking up a name in the RnEnv.

\begin{code}
lookupTopBndrRn :: RdrName -> RnM Name
lookupTopBndrRn n = do nopt <- lookupTopBndrRn_maybe n
                       case nopt of 
                         Just n' -> return n'
                         Nothing -> do traceRn $ text "lookupTopBndrRn"
                                       unboundName n

lookupLocatedTopBndrRn :: Located RdrName -> RnM (Located Name)
lookupLocatedTopBndrRn = wrapLocM lookupTopBndrRn

lookupTopBndrRn_maybe :: RdrName -> RnM (Maybe Name)
-- Look up a top-level source-code binder.   We may be looking up an unqualified 'f',
-- and there may be several imported 'f's too, which must not confuse us.
-- For example, this is OK:
--	import Foo( f )
--	infix 9 f	-- The 'f' here does not need to be qualified
--	f x = x		-- Nor here, of course
-- So we have to filter out the non-local ones.
--
-- A separate function (importsFromLocalDecls) reports duplicate top level
-- decls, so here it's safe just to choose an arbitrary one.
--
-- There should never be a qualified name in a binding position in Haskell,
-- but there can be if we have read in an external-Core file.
-- The Haskell parser checks for the illegal qualified name in Haskell 
-- source files, so we don't need to do so here.

lookupTopBndrRn_maybe rdr_name
  | Just name <- isExact_maybe rdr_name
  = returnM (Just name)

  | Just (rdr_mod, rdr_occ) <- isOrig_maybe rdr_name	
	-- This deals with the case of derived bindings, where
	-- we don't bother to call newTopSrcBinder first
	-- We assume there is no "parent" name
  = do	{ loc <- getSrcSpanM
        ; n <- newGlobalBinder rdr_mod rdr_occ loc 
        ; return (Just n)}

  | otherwise
  = do	{ mb_gre <- lookupGreLocalRn rdr_name
	; case mb_gre of
		Nothing  -> returnM Nothing
		Just gre -> returnM (Just $ gre_name gre) }
	      

-----------------------------------------------
lookupInstDeclBndr :: Name -> Located RdrName -> RnM (Located Name)
-- This is called on the method name on the left-hand side of an 
-- instance declaration binding. eg.  instance Functor T where
--                                       fmap = ...
--                                       ^^^^ called on this
-- Regardless of how many unqualified fmaps are in scope, we want
-- the one that comes from the Functor class.
--
-- Furthermore, note that we take no account of whether the 
-- name is only in scope qualified.  I.e. even if method op is
-- in scope as M.op, we still allow plain 'op' on the LHS of
-- an instance decl
lookupInstDeclBndr cls rdr = lookup_located_sub_bndr is_op doc rdr
  where
    doc = ptext (sLit "method of class") <+> quotes (ppr cls)
    is_op (GRE {gre_par = ParentIs n}) = n == cls
    is_op _                            = False

-----------------------------------------------
lookupRecordBndr :: Maybe (Located Name) -> Located RdrName -> RnM (Located Name)
-- Used for record construction and pattern matching
-- When the -fdisambiguate-record-fields flag is on, take account of the
-- constructor name to disambiguate which field to use; it's just the
-- same as for instance decls
lookupRecordBndr Nothing rdr_name
  = lookupLocatedGlobalOccRn rdr_name
lookupRecordBndr (Just (L _ data_con)) rdr_name
  = do 	{ flag_on <- doptM Opt_DisambiguateRecordFields
	; if not flag_on 
          then lookupLocatedGlobalOccRn rdr_name
	  else do {
	  fields <- lookupConstructorFields data_con
	; let is_field gre = gre_name gre `elem` fields
	; lookup_located_sub_bndr is_field doc rdr_name
	}}
   where
     doc = ptext (sLit "field of constructor") <+> quotes (ppr data_con)


lookupConstructorFields :: Name -> RnM [Name]
-- Look up the fields of a given constructor
--   *	For constructors from this module, use the record field env,
--	which is itself gathered from the (as yet un-typechecked)
--	data type decls
-- 
--    *	For constructors from imported modules, use the *type* environment
--	since imported modles are already compiled, the info is conveniently
--	right there

lookupConstructorFields con_name
  = do	{ this_mod <- getModule
	; if nameIsLocalOrFrom this_mod con_name then
	  do { field_env <- getRecFieldEnv
	     ; return (lookupNameEnv field_env con_name `orElse` []) }
	  else 
	  do { con <- tcLookupDataCon con_name
	     ; return (dataConFieldLabels con) } }

-----------------------------------------------
lookup_located_sub_bndr :: (GlobalRdrElt -> Bool)
			-> SDoc -> Located RdrName
			-> RnM (Located Name)
lookup_located_sub_bndr is_good doc rdr_name
  = wrapLocM (lookup_sub_bndr is_good doc) rdr_name

lookup_sub_bndr :: (GlobalRdrElt -> Bool) -> SDoc -> RdrName -> RnM Name
lookup_sub_bndr is_good doc rdr_name
  | isUnqual rdr_name	-- Find all the things the rdr-name maps to
  = do	{		-- and pick the one with the right parent name
	; env <- getGlobalRdrEnv
	; case filter is_good (lookupGlobalRdrEnv env (rdrNameOcc rdr_name)) of
		-- NB: lookupGlobalRdrEnv, not lookupGRE_RdrName!
		--     The latter does pickGREs, but we want to allow 'x'
		--     even if only 'M.x' is in scope
	    [gre] -> return (gre_name gre)
	    []    -> do { addErr (unknownSubordinateErr doc rdr_name)
			; traceRn (text "RnEnv.lookup_sub_bndr" <+> ppr rdr_name)
			; return (mkUnboundName rdr_name) }
	    gres  -> do { addNameClashErrRn rdr_name gres
			; return (gre_name (head gres)) }
	}

  | otherwise	-- Occurs in derived instances, where we just
		-- refer directly to the right method
  = ASSERT2( not (isQual rdr_name), ppr rdr_name )
	  -- NB: qualified names are rejected by the parser
    lookupImportedName rdr_name

newIPNameRn :: IPName RdrName -> TcRnIf m n (IPName Name)
newIPNameRn ip_rdr = newIPName (mapIPName rdrNameOcc ip_rdr)

-- Looking up family names in type instances is a subtle affair.  The family
-- may be imported, in which case we need to lookup the occurence of a global
-- name.  Alternatively, the family may be in the same binding group (and in
-- fact in a declaration processed later), and we need to create a new top
-- source binder.
--
-- So, also this is strictly speaking an occurence, we cannot raise an error
-- message yet for instances without a family declaration.  This will happen
-- during renaming the type instance declaration in RnSource.rnTyClDecl.
--
lookupFamInstDeclBndr :: Module -> Located RdrName -> RnM Name
lookupFamInstDeclBndr mod lrdr_name@(L _ rdr_name)
  = do { mb_gre <- lookupGreRn_maybe rdr_name
       ; case mb_gre of
           Just gre -> returnM (gre_name gre)
	   Nothing  -> newTopSrcBinder mod lrdr_name }

--------------------------------------------------
--		Occurrences
--------------------------------------------------

getLookupOccRn :: RnM (Name -> Maybe Name)
getLookupOccRn
  = getLocalRdrEnv			`thenM` \ local_env ->
    return (lookupLocalRdrOcc local_env . nameOccName)

lookupLocatedOccRn :: Located RdrName -> RnM (Located Name)
lookupLocatedOccRn = wrapLocM lookupOccRn

-- lookupOccRn looks up an occurrence of a RdrName
lookupOccRn :: RdrName -> RnM Name
lookupOccRn rdr_name
  = getLocalRdrEnv			`thenM` \ local_env ->
    case lookupLocalRdrEnv local_env rdr_name of
	  Just name -> returnM name
	  Nothing   -> lookupGlobalOccRn rdr_name

lookupLocatedGlobalOccRn :: Located RdrName -> RnM (Located Name)
lookupLocatedGlobalOccRn = wrapLocM lookupGlobalOccRn

lookupGlobalOccRn :: RdrName -> RnM Name
-- lookupGlobalOccRn is like lookupOccRn, except that it looks in the global 
-- environment.  It's used only for
--	record field names
--	class op names in class and instance decls

lookupGlobalOccRn rdr_name
  | not (isSrcRdrName rdr_name)
  = lookupImportedName rdr_name	

  | otherwise
  = do
  	-- First look up the name in the normal environment.
   mb_gre <- lookupGreRn_maybe rdr_name
   case mb_gre of {
	Just gre -> returnM (gre_name gre) ;
	Nothing   -> do

	-- We allow qualified names on the command line to refer to 
	--  *any* name exported by any module in scope, just as if 
	-- there was an "import qualified M" declaration for every 
	-- module.
   allow_qual <- doptM Opt_ImplicitImportQualified
   mod <- getModule
               -- This test is not expensive,
               -- and only happens for failed lookups
   if isQual rdr_name && allow_qual && mod == iNTERACTIVE
      then lookupQualifiedName rdr_name
      else unboundName rdr_name
  }

lookupImportedName :: RdrName -> TcRnIf m n Name
-- Lookup the occurrence of an imported name
-- The RdrName is *always* qualified or Exact
-- Treat it as an original name, and conjure up the Name
-- Usually it's Exact or Orig, but it can be Qual if it
--	comes from an hi-boot file.  (This minor infelicity is 
--	just to reduce duplication in the parser.)
lookupImportedName rdr_name
  | Just n <- isExact_maybe rdr_name 
	-- This happens in derived code
  = returnM n

	-- Always Orig, even when reading a .hi-boot file
  | Just (rdr_mod, rdr_occ) <- isOrig_maybe rdr_name
  = lookupOrig rdr_mod rdr_occ

  | otherwise
  = pprPanic "RnEnv.lookupImportedName" (ppr rdr_name)

unboundName :: RdrName -> RnM Name
unboundName rdr_name 
  = do	{ addErr (unknownNameErr rdr_name)
	; env <- getGlobalRdrEnv;
	; traceRn (vcat [unknownNameErr rdr_name, 
			 ptext (sLit "Global envt is:"),
			 nest 3 (pprGlobalRdrEnv env)])
	; returnM (mkUnboundName rdr_name) }

--------------------------------------------------
--	Lookup in the Global RdrEnv of the module
--------------------------------------------------

lookupSrcOcc_maybe :: RdrName -> RnM (Maybe Name)
-- No filter function; does not report an error on failure
lookupSrcOcc_maybe rdr_name
  = do	{ mb_gre <- lookupGreRn_maybe rdr_name
	; case mb_gre of
		Nothing  -> returnM Nothing
		Just gre -> returnM (Just (gre_name gre)) }
	
-------------------------
lookupGreRn_maybe :: RdrName -> RnM (Maybe GlobalRdrElt)
-- Just look up the RdrName in the GlobalRdrEnv
lookupGreRn_maybe rdr_name 
  = lookupGreRn_help rdr_name (lookupGRE_RdrName rdr_name)

lookupGreRn :: RdrName -> RnM GlobalRdrElt
-- If not found, add error message, and return a fake GRE
lookupGreRn rdr_name 
  = do	{ mb_gre <- lookupGreRn_maybe rdr_name
	; case mb_gre of {
	    Just gre -> return gre ;
	    Nothing  -> do
	{ traceRn $ text "lookupGreRn"
	; name <- unboundName rdr_name
	; return (GRE { gre_name = name, gre_par = NoParent,
		        gre_prov = LocalDef }) }}}

lookupGreLocalRn :: RdrName -> RnM (Maybe GlobalRdrElt)
-- Similar, but restricted to locally-defined things
lookupGreLocalRn rdr_name 
  = lookupGreRn_help rdr_name lookup_fn
  where
    lookup_fn env = filter isLocalGRE (lookupGRE_RdrName rdr_name env)

lookupGreRn_help :: RdrName			-- Only used in error message
		 -> (GlobalRdrEnv -> [GlobalRdrElt])	-- Lookup function
		 -> RnM (Maybe GlobalRdrElt)
-- Checks for exactly one match; reports deprecations
-- Returns Nothing, without error, if too few
lookupGreRn_help rdr_name lookup 
  = do	{ env <- getGlobalRdrEnv
	; case lookup env of
	    []	  -> returnM Nothing
	    [gre] -> returnM (Just gre)
	    gres  -> do { addNameClashErrRn rdr_name gres
			; returnM (Just (head gres)) } }

------------------------------
--	GHCi support
------------------------------

-- A qualified name on the command line can refer to any module at all: we
-- try to load the interface if we don't already have it.
lookupQualifiedName :: RdrName -> RnM Name
lookupQualifiedName rdr_name
  | Just (mod,occ) <- isQual_maybe rdr_name
   -- Note: we want to behave as we would for a source file import here,
   -- and respect hiddenness of modules/packages, hence loadSrcInterface.
   = loadSrcInterface doc mod False Nothing	`thenM` \ iface ->

   case  [ (mod,occ) | 
	   (mod,avails) <- mi_exports iface,
    	   avail	<- avails,
    	   name 	<- availNames avail,
    	   name == occ ] of
      ((mod,occ):ns) -> ASSERT (null ns) 
			lookupOrig mod occ
      _ -> unboundName rdr_name

  | otherwise
  = pprPanic "RnEnv.lookupQualifiedName" (ppr rdr_name)
  where
    doc = ptext (sLit "Need to find") <+> ppr rdr_name
\end{code}

lookupSigOccRn is used for type signatures and pragmas
Is this valid?
  module A
	import M( f )
	f :: Int -> Int
	f x = x
It's clear that the 'f' in the signature must refer to A.f
The Haskell98 report does not stipulate this, but it will!
So we must treat the 'f' in the signature in the same way
as the binding occurrence of 'f', using lookupBndrRn

However, consider this case:
	import M( f )
	f :: Int -> Int
	g x = x
We don't want to say 'f' is out of scope; instead, we want to
return the imported 'f', so that later on the reanamer will
correctly report "misplaced type sig".

\begin{code}
lookupSigOccRn :: Maybe NameSet	   -- Just ns => source file; these are the binders
				   -- 	 	 in the same group
				   -- Nothing => hs-boot file; signatures without 
				   -- 		 binders are expected
	       -> Sig RdrName
	       -> Located RdrName -> RnM (Located Name)
lookupSigOccRn mb_bound_names sig
  = wrapLocM $ \ rdr_name -> 
    do { mb_name <- lookupBindGroupOcc mb_bound_names (hsSigDoc sig) rdr_name
       ; case mb_name of
	   Left err   -> do { addErr err; return (mkUnboundName rdr_name) }
	   Right name -> return name }

lookupBindGroupOcc :: Maybe NameSet  -- Just ns => source file; these are the binders
				     -- 	 	 in the same group
				     -- Nothing => hs-boot file; signatures without 
				     -- 		 binders are expected
	           -> SDoc
	           -> RdrName -> RnM (Either Message Name)
-- Looks up the RdrName, expecting it to resolve to one of the 
-- bound names passed in.  If not, return an appropriate error message
lookupBindGroupOcc mb_bound_names what rdr_name
  = do	{ local_env <- getLocalRdrEnv
	; case lookupLocalRdrEnv local_env rdr_name of 
  	    Just n  -> check_local_name n
  	    Nothing -> do	-- Not defined in a nested scope

        { env <- getGlobalRdrEnv 
  	; let gres = lookupGlobalRdrEnv env (rdrNameOcc rdr_name)
	; case (filter isLocalGRE gres) of
	    (gre:_) -> check_local_name (gre_name gre)
			-- If there is more than one local GRE for the 
			-- same OccName, that will be reported separately
	    [] | null gres -> bale_out_with empty
	       | otherwise -> bale_out_with import_msg
  	}}
    where
      check_local_name name 	-- The name is in scope, and not imported
  	  = case mb_bound_names of
  		  Just bound_names | not (name `elemNameSet` bound_names)
				   -> bale_out_with local_msg
	 	  _other -> return (Right name)

      bale_out_with msg 
  	= return (Left (sep [ ptext (sLit "The") <+> what
  				<+> ptext (sLit "for") <+> quotes (ppr rdr_name)
  			   , nest 2 $ ptext (sLit "lacks an accompanying binding")]
  		       $$ nest 2 msg))

      local_msg = parens $ ptext (sLit "The")  <+> what <+> ptext (sLit "must be given where")
  			   <+> quotes (ppr rdr_name) <+> ptext (sLit "is declared")

      import_msg = parens $ ptext (sLit "You cannot give a") <+> what
    			  <+> ptext (sLit "for an imported value")

---------------
lookupLocalDataTcNames :: NameSet -> SDoc -> RdrName -> RnM [Name]
-- GHC extension: look up both the tycon and data con 
-- for con-like things
-- Complain if neither is in scope
lookupLocalDataTcNames bound_names what rdr_name
  | Just n <- isExact_maybe rdr_name	
	-- Special case for (:), which doesn't get into the GlobalRdrEnv
  = return [n]	-- For this we don't need to try the tycon too
  | otherwise
  = do	{ mb_gres <- mapM (lookupBindGroupOcc (Just bound_names) what)
			  (dataTcOccs rdr_name)
	; let (errs, names) = splitEithers mb_gres
	; when (null names) (addErr (head errs))	-- Bleat about one only
	; return names }

dataTcOccs :: RdrName -> [RdrName]
-- If the input is a data constructor, return both it and a type
-- constructor.  This is useful when we aren't sure which we are
-- looking at.
dataTcOccs rdr_name
  | Just n <- isExact_maybe rdr_name		-- Ghastly special case
  , n `hasKey` consDataConKey = [rdr_name]	-- see note below
  | isDataOcc occ 	      = [rdr_name, rdr_name_tc]
  | otherwise 	  	      = [rdr_name]
  where    
    occ 	= rdrNameOcc rdr_name
    rdr_name_tc = setRdrNameSpace rdr_name tcName

-- If the user typed "[]" or "(,,)", we'll generate an Exact RdrName,
-- and setRdrNameSpace generates an Orig, which is fine
-- But it's not fine for (:), because there *is* no corresponding type
-- constructor.  If we generate an Orig tycon for GHC.Base.(:), it'll
-- appear to be in scope (because Orig's simply allocate a new name-cache
-- entry) and then we get an error when we use dataTcOccs in 
-- TcRnDriver.tcRnGetInfo.  Large sigh.
\end{code}


%*********************************************************
%*							*
		Fixities
%*							*
%*********************************************************

\begin{code}
--------------------------------
type FastStringEnv a = UniqFM a		-- Keyed by FastString


emptyFsEnv  :: FastStringEnv a
lookupFsEnv :: FastStringEnv a -> FastString -> Maybe a
extendFsEnv :: FastStringEnv a -> FastString -> a -> FastStringEnv a

emptyFsEnv  = emptyUFM
lookupFsEnv = lookupUFM
extendFsEnv = addToUFM

--------------------------------
type MiniFixityEnv = FastStringEnv (Located Fixity)
	-- Mini fixity env for the names we're about 
	-- to bind, in a single binding group
	--
	-- It is keyed by the *FastString*, not the *OccName*, because
	-- the single fixity decl	infix 3 T
	-- affects both the data constructor T and the type constrctor T
	--
	-- We keep the location so that if we find
	-- a duplicate, we can report it sensibly

--------------------------------
-- Used for nested fixity decls to bind names along with their fixities.
-- the fixities are given as a UFM from an OccName's FastString to a fixity decl
-- Also check for unused binders
bindLocalNamesFV_WithFixities :: [Name]
			      -> MiniFixityEnv
			      -> RnM (a, FreeVars) -> RnM (a, FreeVars)
bindLocalNamesFV_WithFixities names fixities thing_inside
  = bindLocalNamesFV names $
    extendFixityEnv boundFixities $ 
    thing_inside
  where
    -- find the names that have fixity decls
    boundFixities = foldr 
                        (\ name -> \ acc -> 
                         -- check whether this name has a fixity decl
                          case lookupFsEnv fixities (occNameFS (nameOccName name)) of
                               Just (L _ fix) -> (name, FixItem (nameOccName name) fix) : acc
                               Nothing -> acc) [] names
    -- bind the names; extend the fixity env; do the thing inside
\end{code}

--------------------------------
lookupFixity is a bit strange.  

* Nested local fixity decls are put in the local fixity env, which we
  find with getFixtyEnv

* Imported fixities are found in the HIT or PIT

* Top-level fixity decls in this module may be for Names that are
    either  Global	   (constructors, class operations)
    or 	    Local/Exported (everything else)
  (See notes with RnNames.getLocalDeclBinders for why we have this split.)
  We put them all in the local fixity environment

\begin{code}
lookupFixityRn :: Name -> RnM Fixity
lookupFixityRn name
  = getModule				`thenM` \ this_mod -> 
    if nameIsLocalOrFrom this_mod name
    then do	-- It's defined in this module
      local_fix_env <- getFixityEnv		
      traceRn (text "lookupFixityRn: looking up name in local environment:" <+> 
               vcat [ppr name, ppr local_fix_env])
      return $ lookupFixity local_fix_env name
    else	-- It's imported
      -- For imported names, we have to get their fixities by doing a
      -- loadInterfaceForName, and consulting the Ifaces that comes back
      -- from that, because the interface file for the Name might not
      -- have been loaded yet.  Why not?  Suppose you import module A,
      -- which exports a function 'f', thus;
      --        module CurrentModule where
      --	  import A( f )
      -- 	module A( f ) where
      --	  import B( f )
      -- Then B isn't loaded right away (after all, it's possible that
      -- nothing from B will be used).  When we come across a use of
      -- 'f', we need to know its fixity, and it's then, and only
      -- then, that we load B.hi.  That is what's happening here.
      --
      -- loadInterfaceForName will find B.hi even if B is a hidden module,
      -- and that's what we want.
        loadInterfaceForName doc name	`thenM` \ iface -> do {
          traceRn (text "lookupFixityRn: looking up name in iface cache and found:" <+> 
                   vcat [ppr name, ppr $ mi_fix_fn iface (nameOccName name)]);
	   returnM (mi_fix_fn iface (nameOccName name))
                                                           }
  where
    doc = ptext (sLit "Checking fixity for") <+> ppr name

---------------
lookupTyFixityRn :: Located Name -> RnM Fixity
lookupTyFixityRn (L _ n) = lookupFixityRn n

\end{code}

%************************************************************************
%*									*
			Rebindable names
	Dealing with rebindable syntax is driven by the 
	Opt_NoImplicitPrelude dynamic flag.

	In "deriving" code we don't want to use rebindable syntax
	so we switch off the flag locally

%*									*
%************************************************************************

Haskell 98 says that when you say "3" you get the "fromInteger" from the
Standard Prelude, regardless of what is in scope.   However, to experiment
with having a language that is less coupled to the standard prelude, we're
trying a non-standard extension that instead gives you whatever "Prelude.fromInteger"
happens to be in scope.  Then you can
	import Prelude ()
	import MyPrelude as Prelude
to get the desired effect.

At the moment this just happens for
  * fromInteger, fromRational on literals (in expressions and patterns)
  * negate (in expressions)
  * minus  (arising from n+k patterns)
  * "do" notation

We store the relevant Name in the HsSyn tree, in 
  * HsIntegral/HsFractional/HsIsString
  * NegApp
  * NPlusKPat
  * HsDo
respectively.  Initially, we just store the "standard" name (PrelNames.fromIntegralName,
fromRationalName etc), but the renamer changes this to the appropriate user
name if Opt_NoImplicitPrelude is on.  That is what lookupSyntaxName does.

We treat the orignal (standard) names as free-vars too, because the type checker
checks the type of the user thing against the type of the standard thing.

\begin{code}
lookupSyntaxName :: Name 				-- The standard name
	         -> RnM (SyntaxExpr Name, FreeVars)	-- Possibly a non-standard name
lookupSyntaxName std_name
  = doptM Opt_ImplicitPrelude		`thenM` \ implicit_prelude -> 
    if implicit_prelude then normal_case
    else
	-- Get the similarly named thing from the local environment
    lookupOccRn (mkRdrUnqual (nameOccName std_name)) `thenM` \ usr_name ->
    returnM (HsVar usr_name, unitFV usr_name)
  where
    normal_case = returnM (HsVar std_name, emptyFVs)

lookupSyntaxTable :: [Name]				-- Standard names
		  -> RnM (SyntaxTable Name, FreeVars)	-- See comments with HsExpr.ReboundNames
lookupSyntaxTable std_names
  = doptM Opt_ImplicitPrelude		`thenM` \ implicit_prelude -> 
    if implicit_prelude then normal_case 
    else
    	-- Get the similarly named thing from the local environment
    mappM (lookupOccRn . mkRdrUnqual . nameOccName) std_names 	`thenM` \ usr_names ->

    returnM (std_names `zip` map HsVar usr_names, mkFVs usr_names)
  where
    normal_case = returnM (std_names `zip` map HsVar std_names, emptyFVs)
\end{code}


%*********************************************************
%*							*
\subsection{Binding}
%*							*
%*********************************************************

\begin{code}
newLocalsRn :: [Located RdrName] -> RnM [Name]
newLocalsRn rdr_names_w_loc
  = newUniqueSupply 		`thenM` \ us ->
    returnM (zipWith mk rdr_names_w_loc (uniqsFromSupply us))
  where
    mk (L loc rdr_name) uniq
	| Just name <- isExact_maybe rdr_name = name
		-- This happens in code generated by Template Haskell 
	| otherwise = ASSERT2( isUnqual rdr_name, ppr rdr_name )
			-- We only bind unqualified names here
			-- lookupRdrEnv doesn't even attempt to look up a qualified RdrName
		      mkInternalName uniq (rdrNameOcc rdr_name) loc

---------------------
checkDupAndShadowedRdrNames :: SDoc -> [Located RdrName] -> RnM ()
checkDupAndShadowedRdrNames doc loc_rdr_names
  = do	{ checkDupRdrNames doc loc_rdr_names
	; envs <- getRdrEnvs
	; checkShadowedNames doc envs 
		[(loc,rdrNameOcc rdr) | L loc rdr <- loc_rdr_names] }

---------------------
bindLocatedLocalsRn :: SDoc	-- Documentation string for error message
	   	        -> [Located RdrName]
	    	    -> ([Name] -> RnM a)
	    	    -> RnM a
bindLocatedLocalsRn doc_str rdr_names_w_loc enclosed_scope
  = checkDupAndShadowedRdrNames doc_str rdr_names_w_loc	`thenM_`

	-- Make fresh Names and extend the environment
    newLocalsRn rdr_names_w_loc		`thenM` \names ->
    bindLocalNames names (enclosed_scope names)

bindLocalNames :: [Name] -> RnM a -> RnM a
bindLocalNames names enclosed_scope
  = getLocalRdrEnv 		`thenM` \ name_env ->
    setLocalRdrEnv (extendLocalRdrEnv name_env names)
		    enclosed_scope

bindLocalNamesFV :: [Name] -> RnM (a, FreeVars) -> RnM (a, FreeVars)
bindLocalNamesFV names enclosed_scope
  = do	{ (result, fvs) <- bindLocalNames names enclosed_scope
	; returnM (result, delListFromNameSet fvs names) }


-------------------------------------
	-- binLocalsFVRn is the same as bindLocalsRn
	-- except that it deals with free vars
bindLocatedLocalsFV :: SDoc -> [Located RdrName] 
                    -> ([Name] -> RnM (a,FreeVars)) -> RnM (a, FreeVars)
bindLocatedLocalsFV doc rdr_names enclosed_scope
  = bindLocatedLocalsRn doc rdr_names	$ \ names ->
    enclosed_scope names		`thenM` \ (thing, fvs) ->
    returnM (thing, delListFromNameSet fvs names)

-------------------------------------
bindTyVarsRn :: SDoc -> [LHsTyVarBndr RdrName]
	      -> ([LHsTyVarBndr Name] -> RnM a)
	      -> RnM a
-- Haskell-98 binding of type variables; e.g. within a data type decl
bindTyVarsRn doc_str tyvar_names enclosed_scope
  = let
	located_tyvars = hsLTyVarLocNames tyvar_names
    in
    bindLocatedLocalsRn doc_str located_tyvars	$ \ names ->
    enclosed_scope (zipWith replace tyvar_names names)
    where 
	replace (L loc n1) n2 = L loc (replaceTyVarName n1 n2)

bindPatSigTyVars :: [LHsType RdrName] -> ([Name] -> RnM a) -> RnM a
  -- Find the type variables in the pattern type 
  -- signatures that must be brought into scope
bindPatSigTyVars tys thing_inside
  = do 	{ scoped_tyvars <- doptM Opt_ScopedTypeVariables
	; if not scoped_tyvars then 
		thing_inside []
	  else 
    do 	{ name_env <- getLocalRdrEnv
	; let locd_tvs  = [ tv | ty <- tys
			       , tv <- extractHsTyRdrTyVars ty
			       , not (unLoc tv `elemLocalRdrEnv` name_env) ]
	      nubbed_tvs = nubBy eqLocated locd_tvs
		-- The 'nub' is important.  For example:
		--	f (x :: t) (y :: t) = ....
		-- We don't want to complain about binding t twice!

	; bindLocatedLocalsRn doc_sig nubbed_tvs thing_inside }}
  where
    doc_sig = text "In a pattern type-signature"

bindPatSigTyVarsFV :: [LHsType RdrName]
		   -> RnM (a, FreeVars)
	  	   -> RnM (a, FreeVars)
bindPatSigTyVarsFV tys thing_inside
  = bindPatSigTyVars tys	$ \ tvs ->
    thing_inside		`thenM` \ (result,fvs) ->
    returnM (result, fvs `delListFromNameSet` tvs)

bindSigTyVarsFV :: [Name]
		-> RnM (a, FreeVars)
	  	-> RnM (a, FreeVars)
bindSigTyVarsFV tvs thing_inside
  = do	{ scoped_tyvars <- doptM Opt_ScopedTypeVariables
	; if not scoped_tyvars then 
		thing_inside 
	  else
		bindLocalNamesFV tvs thing_inside }

extendTyVarEnvFVRn :: [Name] -> RnM (a, FreeVars) -> RnM (a, FreeVars)
	-- This function is used only in rnSourceDecl on InstDecl
extendTyVarEnvFVRn tyvars thing_inside = bindLocalNamesFV tyvars thing_inside

-------------------------------------
checkDupRdrNames :: SDoc
	         -> [Located RdrName]
	         -> RnM ()
checkDupRdrNames doc_str rdr_names_w_loc
  = 	-- Check for duplicated names in a binding group
    mappM_ (dupNamesErr getLoc doc_str) dups
  where
    (_, dups) = removeDups (\n1 n2 -> unLoc n1 `compare` unLoc n2) rdr_names_w_loc

checkDupNames :: SDoc
	      -> [Name]
	      -> RnM ()
checkDupNames doc_str names
  = 	-- Check for duplicated names in a binding group
    mappM_ (dupNamesErr nameSrcSpan doc_str) dups
  where
    (_, dups) = removeDups (\n1 n2 -> nameOccName n1 `compare` nameOccName n2) names

-------------------------------------
checkShadowedNames :: SDoc -> (GlobalRdrEnv, LocalRdrEnv) -> [(SrcSpan,OccName)] -> RnM ()
checkShadowedNames doc_str (global_env,local_env) loc_rdr_names
  = ifOptM Opt_WarnNameShadowing $ 
    do	{ traceRn (text "shadow" <+> ppr loc_rdr_names)
	; mappM_ check_shadow loc_rdr_names }
  where
    check_shadow (loc, occ)
	| Just n <- mb_local = complain [ptext (sLit "bound at") <+> ppr (nameSrcLoc n)]
	| not (null gres)    = complain (map pprNameProvenance gres)
	| otherwise	     = return ()
	where
	  complain pp_locs = addWarnAt loc (shadowedNameWarn doc_str occ pp_locs)
	  mb_local = lookupLocalRdrOcc local_env occ
          gres     = lookupGRE_RdrName (mkRdrUnqual occ) global_env
		-- Make an Unqualified RdrName and look that up, so that
		-- we don't find any GREs that are in scope qualified-only
\end{code}


%************************************************************************
%*									*
\subsection{Free variable manipulation}
%*									*
%************************************************************************

\begin{code}
-- A useful utility
mapFvRn :: (a -> RnM (b, FreeVars)) -> [a] -> RnM ([b], FreeVars)
mapFvRn f xs = do stuff <- mappM f xs
                  case unzip stuff of
                      (ys, fvs_s) -> returnM (ys, plusFVs fvs_s)

-- because some of the rename functions are CPSed:
-- maps the function across the list from left to right; 
-- collects all the free vars into one set
mapFvRnCPS :: (a  -> (b   -> RnM c) -> RnM c) 
           -> [a] -> ([b] -> RnM c) -> RnM c

mapFvRnCPS _ []     cont = cont []
mapFvRnCPS f (x:xs) cont = f x 		   $ \ x' -> 
                           mapFvRnCPS f xs $ \ xs' ->
                           cont (x':xs')
\end{code}


%************************************************************************
%*									*
\subsection{Envt utility functions}
%*									*
%************************************************************************

\begin{code}
warnUnusedModules :: [(ModuleName,SrcSpan)] -> RnM ()
warnUnusedModules mods
  = ifOptM Opt_WarnUnusedImports (mappM_ bleat mods)
  where
    bleat (mod,loc) = addWarnAt loc (mk_warn mod)
    mk_warn m = vcat [ptext (sLit "Module") <+> quotes (ppr m)
			<+> text "is imported, but nothing from it is used,",
		      nest 2 (ptext (sLit "except perhaps instances visible in") 
			<+> quotes (ppr m)),
		      ptext (sLit "To suppress this warning, use:") 
			<+> ptext (sLit "import") <+> ppr m <> parens empty ]


warnUnusedImports, warnUnusedTopBinds :: [GlobalRdrElt] -> RnM ()
warnUnusedImports gres  = ifOptM Opt_WarnUnusedImports (warnUnusedGREs gres)
warnUnusedTopBinds gres = ifOptM Opt_WarnUnusedBinds   (warnUnusedGREs gres)

warnUnusedLocalBinds, warnUnusedMatches :: [Name] -> FreeVars -> RnM ()
warnUnusedLocalBinds = check_unused Opt_WarnUnusedBinds
warnUnusedMatches    = check_unused Opt_WarnUnusedMatches

check_unused :: DynFlag -> [Name] -> FreeVars -> RnM ()
check_unused flag bound_names used_names
 = ifOptM flag (warnUnusedLocals (filterOut (`elemNameSet` used_names) bound_names))

-------------------------
--	Helpers
warnUnusedGREs :: [GlobalRdrElt] -> RnM ()
warnUnusedGREs gres 
 = warnUnusedBinds [(n,p) | GRE {gre_name = n, gre_prov = p} <- gres]

warnUnusedLocals :: [Name] -> RnM ()
warnUnusedLocals names
 = warnUnusedBinds [(n,LocalDef) | n<-names]

warnUnusedBinds :: [(Name,Provenance)] -> RnM ()
warnUnusedBinds names  = mappM_ warnUnusedName (filter reportable names)
 where reportable (name,_) 
	| isWiredInName name = False	-- Don't report unused wired-in names
					-- Otherwise we get a zillion warnings
					-- from Data.Tuple
	| otherwise = reportIfUnused (nameOccName name)

-------------------------

warnUnusedName :: (Name, Provenance) -> RnM ()
warnUnusedName (name, LocalDef)
  = addUnusedWarning name (srcLocSpan (nameSrcLoc name)) 
		     (ptext (sLit "Defined but not used"))

warnUnusedName (name, Imported is)
  = mapM_ warn is
  where
    warn spec = addUnusedWarning name span msg
	where
	   span = importSpecLoc spec
	   pp_mod = quotes (ppr (importSpecModule spec))
	   msg = ptext (sLit "Imported from") <+> pp_mod <+> ptext (sLit "but not used")

addUnusedWarning :: Name -> SrcSpan -> SDoc -> RnM ()
addUnusedWarning name span msg
  = addWarnAt span $
    sep [msg <> colon, 
	 nest 2 $ pprNonVarNameSpace (occNameSpace (nameOccName name))
			<+> quotes (ppr name)]
\end{code}

\begin{code}
addNameClashErrRn :: RdrName -> [GlobalRdrElt] -> RnM ()
addNameClashErrRn rdr_name names
  = addErr (vcat [ptext (sLit "Ambiguous occurrence") <+> quotes (ppr rdr_name),
		  ptext (sLit "It could refer to") <+> vcat (msg1 : msgs)])
  where
    (np1:nps) = names
    msg1 = ptext  (sLit "either") <+> mk_ref np1
    msgs = [ptext (sLit "    or") <+> mk_ref np | np <- nps]
    mk_ref gre = quotes (ppr (gre_name gre)) <> comma <+> pprNameProvenance gre

shadowedNameWarn :: SDoc -> OccName -> [SDoc] -> SDoc
shadowedNameWarn doc occ shadowed_locs
  = sep [ptext (sLit "This binding for") <+> quotes (ppr occ)
	    <+> ptext (sLit "shadows the existing binding") <> plural shadowed_locs,
	 nest 2 (vcat shadowed_locs)]
    $$ doc

unknownNameErr :: RdrName -> SDoc
unknownNameErr rdr_name
  = vcat [ hang (ptext (sLit "Not in scope:")) 
	      2 (pprNonVarNameSpace (occNameSpace (rdrNameOcc rdr_name))
			  <+> quotes (ppr rdr_name))
	 , extra ]
  where
    extra | rdr_name == forall_tv_RDR = perhapsForallMsg
	  | otherwise 		      = empty

perhapsForallMsg :: SDoc
perhapsForallMsg 
  = vcat [ ptext (sLit "Perhaps you intended to use -XRankNTypes or similar flag")
	 , ptext (sLit "to enable explicit-forall syntax: forall <tvs>. <type>")]

unknownSubordinateErr :: SDoc -> RdrName -> SDoc
unknownSubordinateErr doc op	-- Doc is "method of class" or 
				-- "field of constructor"
  = quotes (ppr op) <+> ptext (sLit "is not a (visible)") <+> doc

badOrigBinding :: RdrName -> SDoc
badOrigBinding name
  = ptext (sLit "Illegal binding of built-in syntax:") <+> ppr (rdrNameOcc name)
	-- The rdrNameOcc is because we don't want to print Prelude.(,)

dupNamesErr :: Outputable n => (n -> SrcSpan) -> SDoc -> [n] -> RnM ()
dupNamesErr get_loc descriptor names
  = addErrAt big_loc $
    vcat [ptext (sLit "Conflicting definitions for") <+> quotes (ppr (head names)),
	  locations, descriptor]
  where
    locs      = map get_loc names
    big_loc   = foldr1 combineSrcSpans locs
    one_line  = isOneLineSpan big_loc
    locations | one_line  = empty 
	      | otherwise = ptext (sLit "Bound at:") <+> 
			    vcat (map ppr (sortLe (<=) locs))

badQualBndrErr :: RdrName -> SDoc
badQualBndrErr rdr_name
  = ptext (sLit "Qualified name in binding position:") <+> ppr rdr_name
\end{code}
