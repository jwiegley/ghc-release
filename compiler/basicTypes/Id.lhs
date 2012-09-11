%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%
\section[Id]{@Ids@: Value and constructor identifiers}

\begin{code}
-- |
-- #name_types#
-- GHC uses several kinds of name internally:
--
-- * 'OccName.OccName': see "OccName#name_types"
--
-- * 'RdrName.RdrName': see "RdrName#name_types"
--
-- * 'Name.Name': see "Name#name_types"
--
-- * 'Id.Id' represents names that not only have a 'Name.Name' but also a 'TypeRep.Type' and some additional
--   details (a 'IdInfo.IdInfo' and one of 'Var.LocalIdDetails' or 'IdInfo.GlobalIdDetails') that
--   are added, modified and inspected by various compiler passes. These 'Var.Var' names may either 
--   be global or local, see "Var#globalvslocal"
--
-- * 'Var.Var': see "Var#name_types"
module Id (
        -- * The main types
	Id, DictId,

	-- ** Simple construction
	mkGlobalId, mkVanillaGlobal, mkVanillaGlobalWithInfo,
	mkLocalId, mkLocalIdWithInfo, mkExportedLocalId,
	mkSysLocal, mkSysLocalM, mkUserLocal, mkUserLocalM,
	mkTemplateLocals, mkTemplateLocalsNum, mkTemplateLocal,
	mkWorkerId, 

	-- ** Taking an Id apart
	idName, idType, idUnique, idInfo, idDetails,
	isId, idPrimRep,
	recordSelectorFieldLabel,

	-- ** Modifying an Id
	setIdName, setIdUnique, Id.setIdType, 
	setIdExported, setIdNotExported, 
	globaliseId, localiseId, 
	setIdInfo, lazySetIdInfo, modifyIdInfo, maybeModifyIdInfo,
	zapLamIdInfo, zapDemandIdInfo, zapFragileIdInfo, transferPolyIdInfo,
	

	-- ** Predicates on Ids
	isImplicitId, isDeadBinder, isDictId, isStrictId,
	isExportedId, isLocalId, isGlobalId,
	isRecordSelector, isNaughtyRecordSelector,
	isClassOpId_maybe, isDFunId,
	isPrimOpId, isPrimOpId_maybe, 
	isFCallId, isFCallId_maybe,
	isDataConWorkId, isDataConWorkId_maybe, isDataConId_maybe, idDataCon,
        isConLikeId, isBottomingId, idIsFrom,
        isTickBoxOp, isTickBoxOp_maybe,
	hasNoBinding, 

	-- ** Inline pragma stuff
	idInlinePragma, setInlinePragma, modifyInlinePragma,
        idInlineActivation, setInlineActivation, idRuleMatchInfo,

	-- ** One-shot lambdas
	isOneShotBndr, isOneShotLambda, isStateHackType,
	setOneShotLambda, clearOneShotLambda,

	-- ** Reading 'IdInfo' fields
	idArity, 
	idNewDemandInfo, idNewDemandInfo_maybe,
	idNewStrictness, idNewStrictness_maybe, 
	idWorkerInfo,
	idUnfolding,
	idSpecialisation, idCoreRules, idHasRules,
	idCafInfo,
	idLBVarInfo,
	idOccInfo,

#ifdef OLD_STRICTNESS
	idDemandInfo, 
	idStrictness, 
	idCprInfo,
#endif

	-- ** Writing 'IdInfo' fields
	setIdUnfolding,
	setIdArity,
	setIdNewDemandInfo, 
	setIdNewStrictness, zapIdNewStrictness,
	setIdWorkerInfo,
	setIdSpecialisation,
	setIdCafInfo,
	setIdOccInfo, zapIdOccInfo,

#ifdef OLD_STRICTNESS
	setIdStrictness, 
	setIdDemandInfo, 
	setIdCprInfo,
#endif
    ) where

#include "HsVersions.h"

import CoreSyn ( CoreRule, Unfolding )

import IdInfo
import BasicTypes

-- Imported and re-exported 
import Var( Var, Id, DictId,
            idInfo, idDetails, globaliseId,
            isId, isLocalId, isGlobalId, isExportedId )
import qualified Var

import TyCon
import Type
import TcType
import TysPrim
#ifdef OLD_STRICTNESS
import qualified Demand
#endif
import DataCon
import NewDemand
import Name
import Module
import Class
import PrimOp
import ForeignCall
import Maybes
import SrcLoc
import Outputable
import Unique
import UniqSupply
import FastString
import Util( count )
import StaticFlags

-- infixl so you can say (id `set` a `set` b)
infixl 	1 `setIdUnfolding`,
	  `setIdArity`,
	  `setIdNewDemandInfo`,
	  `setIdNewStrictness`,
	  `setIdWorkerInfo`,
	  `setIdSpecialisation`,
	  `setInlinePragma`,
	  `idCafInfo`
#ifdef OLD_STRICTNESS
	  ,`idCprInfo`
	  ,`setIdStrictness`
	  ,`setIdDemandInfo`
#endif
\end{code}

%************************************************************************
%*									*
\subsection{Basic Id manipulation}
%*									*
%************************************************************************

\begin{code}
idName   :: Id -> Name
idName    = Var.varName

idUnique :: Id -> Unique
idUnique  = Var.varUnique

idType   :: Id -> Kind
idType    = Var.varType

idPrimRep :: Id -> PrimRep
idPrimRep id = typePrimRep (idType id)

setIdName :: Id -> Name -> Id
setIdName = Var.setVarName

setIdUnique :: Id -> Unique -> Id
setIdUnique = Var.setVarUnique

-- | Not only does this set the 'Id' 'Type', it also evaluates the type to try and
-- reduce space usage
setIdType :: Id -> Type -> Id
setIdType id ty = seqType ty `seq` Var.setVarType id ty

setIdExported :: Id -> Id
setIdExported = Var.setIdExported

setIdNotExported :: Id -> Id
setIdNotExported = Var.setIdNotExported

localiseId :: Id -> Id
-- Make an with the same unique and type as the 
-- incoming Id, but with an *Internal* Name and *LocalId* flavour
localiseId id 
  | isLocalId id && isInternalName name
  = id
  | otherwise
  = mkLocalIdWithInfo (localiseName name) (idType id) (idInfo id)
  where
    name = idName id

lazySetIdInfo :: Id -> IdInfo -> Id
lazySetIdInfo = Var.lazySetIdInfo

setIdInfo :: Id -> IdInfo -> Id
setIdInfo id info = seqIdInfo info `seq` (lazySetIdInfo id info)
        -- Try to avoid spack leaks by seq'ing

modifyIdInfo :: (IdInfo -> IdInfo) -> Id -> Id
modifyIdInfo fn id = setIdInfo id (fn (idInfo id))

-- maybeModifyIdInfo tries to avoid unnecesary thrashing
maybeModifyIdInfo :: Maybe IdInfo -> Id -> Id
maybeModifyIdInfo (Just new_info) id = lazySetIdInfo id new_info
maybeModifyIdInfo Nothing	  id = id
\end{code}

%************************************************************************
%*									*
\subsection{Simple Id construction}
%*									*
%************************************************************************

Absolutely all Ids are made by mkId.  It is just like Var.mkId,
but in addition it pins free-tyvar-info onto the Id's type, 
where it can easily be found.

Note [Free type variables]
~~~~~~~~~~~~~~~~~~~~~~~~~~
At one time we cached the free type variables of the type of an Id
at the root of the type in a TyNote.  The idea was to avoid repeating
the free-type-variable calculation.  But it turned out to slow down
the compiler overall. I don't quite know why; perhaps finding free
type variables of an Id isn't all that common whereas applying a 
substitution (which changes the free type variables) is more common.
Anyway, we removed it in March 2008.

\begin{code}
-- | For an explanation of global vs. local 'Id's, see "Var#globalvslocal"
mkGlobalId :: IdDetails -> Name -> Type -> IdInfo -> Id
mkGlobalId = Var.mkGlobalVar

-- | Make a global 'Id' without any extra information at all
mkVanillaGlobal :: Name -> Type -> Id
mkVanillaGlobal name ty = mkVanillaGlobalWithInfo name ty vanillaIdInfo

-- | Make a global 'Id' with no global information but some generic 'IdInfo'
mkVanillaGlobalWithInfo :: Name -> Type -> IdInfo -> Id
mkVanillaGlobalWithInfo = mkGlobalId VanillaId


-- | For an explanation of global vs. local 'Id's, see "Var#globalvslocal"
mkLocalId :: Name -> Type -> Id
mkLocalId name ty = mkLocalIdWithInfo name ty vanillaIdInfo

mkLocalIdWithInfo :: Name -> Type -> IdInfo -> Id
mkLocalIdWithInfo name ty info = Var.mkLocalVar VanillaId name ty info
	-- Note [Free type variables]

-- | Create a local 'Id' that is marked as exported. 
-- This prevents things attached to it from being removed as dead code.
mkExportedLocalId :: Name -> Type -> Id
mkExportedLocalId name ty = Var.mkExportedLocalVar VanillaId name ty vanillaIdInfo
	-- Note [Free type variables]


-- | Create a system local 'Id'. These are local 'Id's (see "Var#globalvslocal") 
-- that are created by the compiler out of thin air
mkSysLocal :: FastString -> Unique -> Type -> Id
mkSysLocal fs uniq ty = mkLocalId (mkSystemVarName uniq fs) ty

mkSysLocalM :: MonadUnique m => FastString -> Type -> m Id
mkSysLocalM fs ty = getUniqueM >>= (\uniq -> return (mkSysLocal fs uniq ty))


-- | Create a user local 'Id'. These are local 'Id's (see "Var#globalvslocal") with a name and location that the user might recognize
mkUserLocal :: OccName -> Unique -> Type -> SrcSpan -> Id
mkUserLocal occ uniq ty loc = mkLocalId (mkInternalName uniq occ loc) ty

mkUserLocalM :: MonadUnique m => OccName -> Type -> SrcSpan -> m Id
mkUserLocalM occ ty loc = getUniqueM >>= (\uniq -> return (mkUserLocal occ uniq ty loc))

\end{code}

Make some local @Ids@ for a template @CoreExpr@.  These have bogus
@Uniques@, but that's OK because the templates are supposed to be
instantiated before use.
 
\begin{code}
-- | Workers get local names. "CoreTidy" will externalise these if necessary
mkWorkerId :: Unique -> Id -> Type -> Id
mkWorkerId uniq unwrkr ty
  = mkLocalId wkr_name ty
  where
    wkr_name = mkInternalName uniq (mkWorkerOcc (getOccName unwrkr)) (getSrcSpan unwrkr)

-- | Create a /template local/: a family of system local 'Id's in bijection with @Int@s, typically used in unfoldings
mkTemplateLocal :: Int -> Type -> Id
mkTemplateLocal i ty = mkSysLocal (fsLit "tpl") (mkBuiltinUnique i) ty

-- | Create a template local for a series of types
mkTemplateLocals :: [Type] -> [Id]
mkTemplateLocals = mkTemplateLocalsNum 1

-- | Create a template local for a series of type, but start from a specified template local
mkTemplateLocalsNum :: Int -> [Type] -> [Id]
mkTemplateLocalsNum n tys = zipWith mkTemplateLocal [n..] tys
\end{code}


%************************************************************************
%*									*
\subsection{Special Ids}
%*									*
%************************************************************************

\begin{code}
-- | If the 'Id' is that for a record selector, extract the 'sel_tycon' and label. Panic otherwise
recordSelectorFieldLabel :: Id -> (TyCon, FieldLabel)
recordSelectorFieldLabel id
  = case Var.idDetails id of
        RecSelId { sel_tycon = tycon } -> (tycon, idName id)
        _ -> panic "recordSelectorFieldLabel"

isRecordSelector        :: Id -> Bool
isNaughtyRecordSelector :: Id -> Bool
isPrimOpId              :: Id -> Bool
isFCallId               :: Id -> Bool
isDataConWorkId         :: Id -> Bool
isDFunId                :: Id -> Bool

isClassOpId_maybe       :: Id -> Maybe Class
isPrimOpId_maybe        :: Id -> Maybe PrimOp
isFCallId_maybe         :: Id -> Maybe ForeignCall
isDataConWorkId_maybe   :: Id -> Maybe DataCon

isRecordSelector id = case Var.idDetails id of
                        RecSelId {}  -> True
                        _               -> False

isNaughtyRecordSelector id = case Var.idDetails id of
                        RecSelId { sel_naughty = n } -> n
                        _                               -> False

isClassOpId_maybe id = case Var.idDetails id of
			ClassOpId cls -> Just cls
			_other        -> Nothing

isPrimOpId id = case Var.idDetails id of
                        PrimOpId _ -> True
                        _          -> False

isDFunId id = case Var.idDetails id of
                        DFunId -> True
                        _      -> False

isPrimOpId_maybe id = case Var.idDetails id of
                        PrimOpId op -> Just op
                        _           -> Nothing

isFCallId id = case Var.idDetails id of
                        FCallId _ -> True
                        _         -> False

isFCallId_maybe id = case Var.idDetails id of
                        FCallId call -> Just call
                        _            -> Nothing

isDataConWorkId id = case Var.idDetails id of
                        DataConWorkId _ -> True
                        _               -> False

isDataConWorkId_maybe id = case Var.idDetails id of
                        DataConWorkId con -> Just con
                        _                 -> Nothing

isDataConId_maybe :: Id -> Maybe DataCon
isDataConId_maybe id = case Var.idDetails id of
                         DataConWorkId con -> Just con
                         DataConWrapId con -> Just con
                         _                 -> Nothing

idDataCon :: Id -> DataCon
-- ^ Get from either the worker or the wrapper 'Id' to the 'DataCon'. Currently used only in the desugarer.
--
-- INVARIANT: @idDataCon (dataConWrapId d) = d@: remember, 'dataConWrapId' can return either the wrapper or the worker
idDataCon id = isDataConId_maybe id `orElse` pprPanic "idDataCon" (ppr id)


isDictId :: Id -> Bool
isDictId id = isDictTy (idType id)

hasNoBinding :: Id -> Bool
-- ^ Returns @True@ of an 'Id' which may not have a
-- binding, even though it is defined in this module.

-- Data constructor workers used to be things of this kind, but
-- they aren't any more.  Instead, we inject a binding for 
-- them at the CorePrep stage. 
-- EXCEPT: unboxed tuples, which definitely have no binding
hasNoBinding id = case Var.idDetails id of
			PrimOpId _  	 -> True	-- See Note [Primop wrappers]
			FCallId _   	 -> True
			DataConWorkId dc -> isUnboxedTupleCon dc
			_                -> False

isImplicitId :: Id -> Bool
-- ^ 'isImplicitId' tells whether an 'Id's info is implied by other
-- declarations, so we don't need to put its signature in an interface
-- file, even if it's mentioned in some other interface unfolding.
isImplicitId id
  = case Var.idDetails id of
        FCallId _       -> True
	ClassOpId _     -> True
        PrimOpId _      -> True
        DataConWorkId _ -> True
	DataConWrapId _ -> True
		-- These are are implied by their type or class decl;
		-- remember that all type and class decls appear in the interface file.
		-- The dfun id is not an implicit Id; it must *not* be omitted, because 
		-- it carries version info for the instance decl
        _               -> False

idIsFrom :: Module -> Id -> Bool
idIsFrom mod id = nameIsLocalOrFrom mod (idName id)
\end{code}

Note [Primop wrappers]
~~~~~~~~~~~~~~~~~~~~~~
Currently hasNoBinding claims that PrimOpIds don't have a curried
function definition.  But actually they do, in GHC.PrimopWrappers,
which is auto-generated from prelude/primops.txt.pp.  So actually, hasNoBinding
could return 'False' for PrimOpIds.

But we'd need to add something in CoreToStg to swizzle any unsaturated
applications of GHC.Prim.plusInt# to GHC.PrimopWrappers.plusInt#.

Nota Bene: GHC.PrimopWrappers is needed *regardless*, because it's
used by GHCi, which does not implement primops direct at all.



\begin{code}
isDeadBinder :: Id -> Bool
isDeadBinder bndr | isId bndr = isDeadOcc (idOccInfo bndr)
		  | otherwise = False	-- TyVars count as not dead
\end{code}

\begin{code}
isTickBoxOp :: Id -> Bool
isTickBoxOp id = 
  case Var.idDetails id of
    TickBoxOpId _    -> True
    _                -> False

isTickBoxOp_maybe :: Id -> Maybe TickBoxOp
isTickBoxOp_maybe id = 
  case Var.idDetails id of
    TickBoxOpId tick -> Just tick
    _                -> Nothing
\end{code}

%************************************************************************
%*									*
\subsection{IdInfo stuff}
%*									*
%************************************************************************

\begin{code}
	---------------------------------
	-- ARITY
idArity :: Id -> Arity
idArity id = arityInfo (idInfo id)

setIdArity :: Id -> Arity -> Id
setIdArity id arity = modifyIdInfo (`setArityInfo` arity) id

#ifdef OLD_STRICTNESS
	---------------------------------
	-- (OLD) STRICTNESS 
idStrictness :: Id -> StrictnessInfo
idStrictness id = strictnessInfo (idInfo id)

setIdStrictness :: Id -> StrictnessInfo -> Id
setIdStrictness id strict_info = modifyIdInfo (`setStrictnessInfo` strict_info) id
#endif

-- | Returns true if an application to n args would diverge
isBottomingId :: Id -> Bool
isBottomingId id = isBottomingSig (idNewStrictness id)

idNewStrictness_maybe :: Id -> Maybe StrictSig
idNewStrictness :: Id -> StrictSig

idNewStrictness_maybe id = newStrictnessInfo (idInfo id)
idNewStrictness       id = idNewStrictness_maybe id `orElse` topSig

setIdNewStrictness :: Id -> StrictSig -> Id
setIdNewStrictness id sig = modifyIdInfo (`setNewStrictnessInfo` Just sig) id

zapIdNewStrictness :: Id -> Id
zapIdNewStrictness id = modifyIdInfo (`setNewStrictnessInfo` Nothing) id

-- | This predicate says whether the 'Id' has a strict demand placed on it or
-- has a type such that it can always be evaluated strictly (e.g., an
-- unlifted type, but see the comment for 'isStrictType').  We need to
-- check separately whether the 'Id' has a so-called \"strict type\" because if
-- the demand for the given @id@ hasn't been computed yet but @id@ has a strict
-- type, we still want @isStrictId id@ to be @True@.
isStrictId :: Id -> Bool
isStrictId id
  = ASSERT2( isId id, text "isStrictId: not an id: " <+> ppr id )
           (isStrictDmd (idNewDemandInfo id)) || 
           (isStrictType (idType id))

	---------------------------------
	-- WORKER ID
idWorkerInfo :: Id -> WorkerInfo
idWorkerInfo id = workerInfo (idInfo id)

setIdWorkerInfo :: Id -> WorkerInfo -> Id
setIdWorkerInfo id work_info = modifyIdInfo (`setWorkerInfo` work_info) id

	---------------------------------
	-- UNFOLDING
idUnfolding :: Id -> Unfolding
idUnfolding id = unfoldingInfo (idInfo id)

setIdUnfolding :: Id -> Unfolding -> Id
setIdUnfolding id unfolding = modifyIdInfo (`setUnfoldingInfo` unfolding) id

#ifdef OLD_STRICTNESS
	---------------------------------
	-- (OLD) DEMAND
idDemandInfo :: Id -> Demand.Demand
idDemandInfo id = demandInfo (idInfo id)

setIdDemandInfo :: Id -> Demand.Demand -> Id
setIdDemandInfo id demand_info = modifyIdInfo (`setDemandInfo` demand_info) id
#endif

idNewDemandInfo_maybe :: Id -> Maybe NewDemand.Demand
idNewDemandInfo       :: Id -> NewDemand.Demand

idNewDemandInfo_maybe id = newDemandInfo (idInfo id)
idNewDemandInfo       id = newDemandInfo (idInfo id) `orElse` NewDemand.topDmd

setIdNewDemandInfo :: Id -> NewDemand.Demand -> Id
setIdNewDemandInfo id dmd = modifyIdInfo (`setNewDemandInfo` Just dmd) id

	---------------------------------
	-- SPECIALISATION
idSpecialisation :: Id -> SpecInfo
idSpecialisation id = specInfo (idInfo id)

idCoreRules :: Id -> [CoreRule]
idCoreRules id = specInfoRules (idSpecialisation id)

idHasRules :: Id -> Bool
idHasRules id = not (isEmptySpecInfo (idSpecialisation id))

setIdSpecialisation :: Id -> SpecInfo -> Id
setIdSpecialisation id spec_info = modifyIdInfo (`setSpecInfo` spec_info) id

	---------------------------------
	-- CAF INFO
idCafInfo :: Id -> CafInfo
#ifdef OLD_STRICTNESS
idCafInfo id = case cgInfo (idInfo id) of
		  NoCgInfo -> pprPanic "idCafInfo" (ppr id)
		  info     -> cgCafInfo info
#else
idCafInfo id = cafInfo (idInfo id)
#endif

setIdCafInfo :: Id -> CafInfo -> Id
setIdCafInfo id caf_info = modifyIdInfo (`setCafInfo` caf_info) id

	---------------------------------
	-- CPR INFO
#ifdef OLD_STRICTNESS
idCprInfo :: Id -> CprInfo
idCprInfo id = cprInfo (idInfo id)

setIdCprInfo :: Id -> CprInfo -> Id
setIdCprInfo id cpr_info = modifyIdInfo (`setCprInfo` cpr_info) id
#endif

	---------------------------------
	-- Occcurrence INFO
idOccInfo :: Id -> OccInfo
idOccInfo id = occInfo (idInfo id)

setIdOccInfo :: Id -> OccInfo -> Id
setIdOccInfo id occ_info = modifyIdInfo (`setOccInfo` occ_info) id

zapIdOccInfo :: Id -> Id
zapIdOccInfo b = b `setIdOccInfo` NoOccInfo
\end{code}


	---------------------------------
	-- INLINING
The inline pragma tells us to be very keen to inline this Id, but it's still
OK not to if optimisation is switched off.

\begin{code}
idInlinePragma :: Id -> InlinePragma
idInlinePragma id = inlinePragInfo (idInfo id)

setInlinePragma :: Id -> InlinePragma -> Id
setInlinePragma id prag = modifyIdInfo (`setInlinePragInfo` prag) id

modifyInlinePragma :: Id -> (InlinePragma -> InlinePragma) -> Id
modifyInlinePragma id fn = modifyIdInfo (\info -> info `setInlinePragInfo` (fn (inlinePragInfo info))) id

idInlineActivation :: Id -> Activation
idInlineActivation id = inlinePragmaActivation (idInlinePragma id)

setInlineActivation :: Id -> Activation -> Id
setInlineActivation id act = modifyInlinePragma id (\(InlinePragma _ match_info) -> InlinePragma act match_info)

idRuleMatchInfo :: Id -> RuleMatchInfo
idRuleMatchInfo id = inlinePragmaRuleMatchInfo (idInlinePragma id)

isConLikeId :: Id -> Bool
isConLikeId id = isDataConWorkId id || isConLike (idRuleMatchInfo id)
\end{code}


	---------------------------------
	-- ONE-SHOT LAMBDAS
\begin{code}
idLBVarInfo :: Id -> LBVarInfo
idLBVarInfo id = lbvarInfo (idInfo id)

-- | Returns whether the lambda associated with the 'Id' is certainly applied at most once
-- OR we are applying the \"state hack\" which makes it appear as if theis is the case for
-- lambdas used in @IO@. You should prefer using this over 'isOneShotLambda'
isOneShotBndr :: Id -> Bool
-- This one is the "business end", called externally.
-- Its main purpose is to encapsulate the Horrible State Hack
isOneShotBndr id = isOneShotLambda id || isStateHackType (idType id)

-- | Should we apply the state hack to values of this 'Type'?
isStateHackType :: Type -> Bool
isStateHackType ty
  | opt_NoStateHack 
  = False
  | otherwise
  = case splitTyConApp_maybe ty of
	Just (tycon,_) -> tycon == statePrimTyCon
        _              -> False
	-- This is a gross hack.  It claims that 
	-- every function over realWorldStatePrimTy is a one-shot
	-- function.  This is pretty true in practice, and makes a big
	-- difference.  For example, consider
	--	a `thenST` \ r -> ...E...
	-- The early full laziness pass, if it doesn't know that r is one-shot
	-- will pull out E (let's say it doesn't mention r) to give
	--	let lvl = E in a `thenST` \ r -> ...lvl...
	-- When `thenST` gets inlined, we end up with
	--	let lvl = E in \s -> case a s of (r, s') -> ...lvl...
	-- and we don't re-inline E.
	--
	-- It would be better to spot that r was one-shot to start with, but
	-- I don't want to rely on that.
	--
	-- Another good example is in fill_in in PrelPack.lhs.  We should be able to
	-- spot that fill_in has arity 2 (and when Keith is done, we will) but we can't yet.


-- | Returns whether the lambda associated with the 'Id' is certainly applied at most once.
-- You probably want to use 'isOneShotBndr' instead
isOneShotLambda :: Id -> Bool
isOneShotLambda id = case idLBVarInfo id of
                       IsOneShotLambda  -> True
                       NoLBVarInfo      -> False

setOneShotLambda :: Id -> Id
setOneShotLambda id = modifyIdInfo (`setLBVarInfo` IsOneShotLambda) id

clearOneShotLambda :: Id -> Id
clearOneShotLambda id 
  | isOneShotLambda id = modifyIdInfo (`setLBVarInfo` NoLBVarInfo) id
  | otherwise	       = id			

-- The OneShotLambda functions simply fiddle with the IdInfo flag
-- But watch out: this may change the type of something else
--	f = \x -> e
-- If we change the one-shot-ness of x, f's type changes
\end{code}

\begin{code}
zapInfo :: (IdInfo -> Maybe IdInfo) -> Id -> Id
zapInfo zapper id = maybeModifyIdInfo (zapper (idInfo id)) id

zapLamIdInfo :: Id -> Id
zapLamIdInfo = zapInfo zapLamInfo

zapDemandIdInfo :: Id -> Id
zapDemandIdInfo = zapInfo zapDemandInfo

zapFragileIdInfo :: Id -> Id
zapFragileIdInfo = zapInfo zapFragileInfo 
\end{code}

Note [transferPolyIdInfo]
~~~~~~~~~~~~~~~~~~~~~~~~~
Suppose we have

   f = /\a. let g = rhs in ...

where g has interesting strictness information.  Then if we float thus

   g' = /\a. rhs
   f = /\a. ...[g' a/g]

we *do not* want to lose g's
  * strictness information
  * arity 
  * inline pragma (though that is bit more debatable)

It's simple to retain strictness and arity, but not so simple to retain
  * worker info
  * rules
so we simply discard those.  Sooner or later this may bite us.

This transfer is used in two places: 
	FloatOut (long-distance let-floating)
	SimplUtils.abstractFloats (short-distance let-floating)

If we abstract wrt one or more *value* binders, we must modify the 
arity and strictness info before transferring it.  E.g. 
      f = \x. e
-->
      g' = \y. \x. e
      + substitute (g' y) for g
Notice that g' has an arity one more than the original g

\begin{code}
transferPolyIdInfo :: Id	-- Original Id
		   -> [Var]	-- Abstract wrt these variables
		   -> Id	-- New Id
		   -> Id
transferPolyIdInfo old_id abstract_wrt new_id
  = modifyIdInfo transfer new_id
  where
    arity_increase = count isId abstract_wrt	-- Arity increases by the
    		     	   			-- number of value binders

    old_info 	    = idInfo old_id
    old_arity       = arityInfo old_info
    old_inline_prag = inlinePragInfo old_info
    new_arity       = old_arity + arity_increase
    old_strictness  = newStrictnessInfo old_info
    new_strictness  = fmap (increaseStrictSigArity arity_increase) old_strictness

    transfer new_info = new_info `setNewStrictnessInfo` new_strictness
			         `setArityInfo` new_arity
 			         `setInlinePragInfo` old_inline_prag
\end{code}
