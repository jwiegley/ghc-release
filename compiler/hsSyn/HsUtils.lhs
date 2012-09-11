
%
% (c) The University of Glasgow, 1992-2006
%

Here we collect a variety of helper functions that construct or
analyse HsSyn.  All these functions deal with generic HsSyn; functions
which deal with the intantiated versions are located elsewhere:

   Parameterised by	Module
   ----------------     -------------
   RdrName		parser/RdrHsSyn
   Name			rename/RnHsSyn
   Id			typecheck/TcHsSyn	

\begin{code}
module HsUtils(
  -- Terms
  mkHsPar, mkHsApp, mkHsConApp, mkSimpleHsAlt,
  mkSimpleMatch, unguardedGRHSs, unguardedRHS, 
  mkMatchGroup, mkMatch, mkHsLam, mkHsIf,
  mkHsWrap, mkLHsWrap, mkHsWrapCoI, mkLHsWrapCoI,
  coiToHsWrapper, mkHsDictLet,
  mkHsOpApp, mkHsDo, mkHsWrapPat, mkHsWrapPatCoI,

  nlHsTyApp, nlHsVar, nlHsLit, nlHsApp, nlHsApps, nlHsIntLit, nlHsVarApps, 
  nlHsDo, nlHsOpApp, nlHsLam, nlHsPar, nlHsIf, nlHsCase, nlList,
  mkLHsTupleExpr, mkLHsVarTuple, missingTupArg,

  -- Bindigns
  mkFunBind, mkVarBind, mkHsVarBind, mk_easy_FunBind, 

  -- Literals
  mkHsIntegral, mkHsFractional, mkHsIsString, mkHsString, 

  -- Patterns
  mkNPat, mkNPlusKPat, nlVarPat, nlLitPat, nlConVarPat, nlConPat, nlInfixConPat,
  nlNullaryConPat, nlWildConPat, nlWildPat, nlTuplePat, 

  -- Types
  mkHsAppTy, userHsTyVarBndrs,
  nlHsAppTy, nlHsTyVar, nlHsFunTy, nlHsTyConApp, 

  -- Stmts
  mkTransformStmt, mkTransformByStmt, mkExprStmt, mkBindStmt,
  mkGroupUsingStmt, mkGroupByStmt, mkGroupByUsingStmt, 
  emptyRecStmt, mkRecStmt, 

  -- Template Haskell
  unqualSplice, mkHsSpliceTy, mkHsSplice, mkHsQuasiQuote, unqualQuasiQuote,

  -- Flags
  noRebindableInfo, 

  -- Collecting binders
  collectLocalBinders, collectHsValBinders, collectHsBindListBinders,
  collectHsBindsBinders, collectHsBindBinders, collectMethodBinders,
  collectPatBinders, collectPatsBinders,
  collectLStmtsBinders, collectStmtsBinders,
  collectLStmtBinders, collectStmtBinders,
  collectSigTysFromPats, collectSigTysFromPat,

  hsTyClDeclBinders, hsTyClDeclsBinders, 
  hsForeignDeclsBinders, hsGroupBinders
  ) where

import HsDecls
import HsBinds
import HsExpr
import HsPat
import HsTypes	
import HsLit

import RdrName
import Var
import Coercion
import Type
import DataCon
import Name
import NameSet
import BasicTypes
import SrcLoc
import FastString
import Util
import Bag
\end{code}


%************************************************************************
%*									*
	Some useful helpers for constructing syntax
%*									*
%************************************************************************

These functions attempt to construct a not-completely-useless SrcSpan
from their components, compared with the nl* functions below which
just attach noSrcSpan to everything.

\begin{code}
mkHsPar :: LHsExpr id -> LHsExpr id
mkHsPar e = L (getLoc e) (HsPar e)

mkSimpleMatch :: [LPat id] -> LHsExpr id -> LMatch id
mkSimpleMatch pats rhs 
  = L loc $
    Match pats Nothing (unguardedGRHSs rhs)
  where
    loc = case pats of
		[]      -> getLoc rhs
		(pat:_) -> combineSrcSpans (getLoc pat) (getLoc rhs)

unguardedGRHSs :: LHsExpr id -> GRHSs id
unguardedGRHSs rhs = GRHSs (unguardedRHS rhs) emptyLocalBinds

unguardedRHS :: LHsExpr id -> [LGRHS id]
unguardedRHS rhs@(L loc _) = [L loc (GRHS [] rhs)]

mkHsAppTy :: LHsType name -> LHsType name -> LHsType name
mkHsAppTy t1 t2 = addCLoc t1 t2 (HsAppTy t1 t2)

mkHsApp :: LHsExpr name -> LHsExpr name -> LHsExpr name
mkHsApp e1 e2 = addCLoc e1 e2 (HsApp e1 e2)

nlHsTyApp :: name -> [Type] -> LHsExpr name
nlHsTyApp fun_id tys = noLoc (HsWrap (mkWpTyApps tys) (HsVar fun_id))

mkLHsWrap :: HsWrapper -> LHsExpr id -> LHsExpr id
mkLHsWrap co_fn (L loc e) = L loc (mkHsWrap co_fn e)

mkHsWrap :: HsWrapper -> HsExpr id -> HsExpr id
mkHsWrap co_fn e | isIdHsWrapper co_fn = e
		 | otherwise	       = HsWrap co_fn e

mkHsWrapCoI :: CoercionI -> HsExpr id -> HsExpr id
mkHsWrapCoI (IdCo _) e = e
mkHsWrapCoI (ACo co) e = mkHsWrap (WpCast co) e

mkLHsWrapCoI :: CoercionI -> LHsExpr id -> LHsExpr id
mkLHsWrapCoI (IdCo _) e         = e
mkLHsWrapCoI (ACo co) (L loc e) = L loc (mkHsWrap (WpCast co) e)

coiToHsWrapper :: CoercionI -> HsWrapper
coiToHsWrapper (IdCo _) = idHsWrapper
coiToHsWrapper (ACo co) = WpCast co

mkHsWrapPat :: HsWrapper -> Pat id -> Type -> Pat id
mkHsWrapPat co_fn p ty | isIdHsWrapper co_fn = p
		       | otherwise	     = CoPat co_fn p ty

mkHsWrapPatCoI :: CoercionI -> Pat id -> Type -> Pat id
mkHsWrapPatCoI (IdCo _) pat _  = pat
mkHsWrapPatCoI (ACo co) pat ty = CoPat (WpCast co) pat ty

mkHsLam :: [LPat id] -> LHsExpr id -> LHsExpr id
mkHsLam pats body = mkHsPar (L (getLoc body) (HsLam matches))
	where
	  matches = mkMatchGroup [mkSimpleMatch pats body]

mkMatchGroup :: [LMatch id] -> MatchGroup id
mkMatchGroup matches = MatchGroup matches placeHolderType

mkHsDictLet :: TcEvBinds -> LHsExpr Id -> LHsExpr Id
mkHsDictLet ev_binds expr = mkLHsWrap (WpLet ev_binds) expr

mkHsConApp :: DataCon -> [Type] -> [HsExpr Id] -> LHsExpr Id
-- Used for constructing dictionary terms etc, so no locations 
mkHsConApp data_con tys args 
  = foldl mk_app (nlHsTyApp (dataConWrapId data_con) tys) args
  where
    mk_app f a = noLoc (HsApp f (noLoc a))

mkSimpleHsAlt :: LPat id -> LHsExpr id -> LMatch id
-- A simple lambda with a single pattern, no binds, no guards; pre-typechecking
mkSimpleHsAlt pat expr 
  = mkSimpleMatch [pat] expr

-------------------------------
-- These are the bits of syntax that contain rebindable names
-- See RnEnv.lookupSyntaxName

mkHsIntegral   :: Integer -> PostTcType -> HsOverLit id
mkHsFractional :: Rational -> PostTcType -> HsOverLit id
mkHsIsString   :: FastString -> PostTcType -> HsOverLit id
mkHsDo         :: HsStmtContext Name -> [LStmt id] -> LHsExpr id -> HsExpr id

mkNPat      :: HsOverLit id -> Maybe (SyntaxExpr id) -> Pat id
mkNPlusKPat :: Located id -> HsOverLit id -> Pat id

mkTransformStmt   :: [LStmt idL] -> LHsExpr idR                -> StmtLR idL idR
mkTransformByStmt :: [LStmt idL] -> LHsExpr idR -> LHsExpr idR -> StmtLR idL idR

mkExprStmt :: LHsExpr idR -> StmtLR idL idR
mkBindStmt :: LPat idL -> LHsExpr idR -> StmtLR idL idR

emptyRecStmt :: StmtLR idL idR
mkRecStmt    :: [LStmtLR idL idR] -> StmtLR idL idR


mkHsIntegral   i       = OverLit (HsIntegral   i)  noRebindableInfo noSyntaxExpr
mkHsFractional f       = OverLit (HsFractional f)  noRebindableInfo noSyntaxExpr
mkHsIsString   s       = OverLit (HsIsString   s)  noRebindableInfo noSyntaxExpr

noRebindableInfo :: Bool
noRebindableInfo = error "noRebindableInfo" 	-- Just another placeholder; 

mkHsDo ctxt stmts body = HsDo ctxt stmts body placeHolderType

mkHsIf :: LHsExpr id -> LHsExpr id -> LHsExpr id -> HsExpr id
mkHsIf c a b = HsIf (Just noSyntaxExpr) c a b

mkNPat lit neg     = NPat lit neg noSyntaxExpr
mkNPlusKPat id lit = NPlusKPat id lit noSyntaxExpr noSyntaxExpr

mkTransformStmt   stmts usingExpr        = TransformStmt stmts [] usingExpr Nothing
mkTransformByStmt stmts usingExpr byExpr = TransformStmt stmts [] usingExpr (Just byExpr)

mkGroupUsingStmt   :: [LStmt idL]                -> LHsExpr idR -> StmtLR idL idR
mkGroupByStmt      :: [LStmt idL] -> LHsExpr idR                -> StmtLR idL idR
mkGroupByUsingStmt :: [LStmt idL] -> LHsExpr idR -> LHsExpr idR -> StmtLR idL idR

mkGroupUsingStmt   stmts usingExpr        = GroupStmt stmts [] Nothing       (Left usingExpr)    
mkGroupByStmt      stmts byExpr           = GroupStmt stmts [] (Just byExpr) (Right noSyntaxExpr)
mkGroupByUsingStmt stmts byExpr usingExpr = GroupStmt stmts [] (Just byExpr) (Left usingExpr)    

mkExprStmt expr	    = ExprStmt expr noSyntaxExpr placeHolderType
mkBindStmt pat expr = BindStmt pat expr noSyntaxExpr noSyntaxExpr

emptyRecStmt = RecStmt { recS_stmts = [], recS_later_ids = [], recS_rec_ids = []
                       , recS_ret_fn = noSyntaxExpr, recS_mfix_fn = noSyntaxExpr
		       , recS_bind_fn = noSyntaxExpr
                       , recS_rec_rets = [], recS_dicts = emptyTcEvBinds }

mkRecStmt stmts = emptyRecStmt { recS_stmts = stmts }

-------------------------------
--- A useful function for building @OpApps@.  The operator is always a
-- variable, and we don't know the fixity yet.
mkHsOpApp :: LHsExpr id -> id -> LHsExpr id -> HsExpr id
mkHsOpApp e1 op e2 = OpApp e1 (noLoc (HsVar op)) (error "mkOpApp:fixity") e2

mkHsSplice :: LHsExpr RdrName -> HsSplice RdrName
mkHsSplice e = HsSplice unqualSplice e

mkHsSpliceTy :: LHsExpr RdrName -> HsType RdrName
mkHsSpliceTy e = HsSpliceTy (mkHsSplice e) emptyFVs placeHolderKind

unqualSplice :: RdrName
unqualSplice = mkRdrUnqual (mkVarOccFS (fsLit "splice"))
		-- A name (uniquified later) to
		-- identify the splice

mkHsQuasiQuote :: RdrName -> SrcSpan -> FastString -> HsQuasiQuote RdrName
mkHsQuasiQuote quoter span quote = HsQuasiQuote quoter span quote

unqualQuasiQuote :: RdrName
unqualQuasiQuote = mkRdrUnqual (mkVarOccFS (fsLit "quasiquote"))
		-- A name (uniquified later) to
		-- identify the quasi-quote

mkHsString :: String -> HsLit
mkHsString s = HsString (mkFastString s)

-------------
userHsTyVarBndrs :: [Located name] -> [Located (HsTyVarBndr name)]
userHsTyVarBndrs bndrs = [ L loc (UserTyVar v placeHolderKind) | L loc v <- bndrs ]
\end{code}


%************************************************************************
%*									*
	Constructing syntax with no location info
%*									*
%************************************************************************

\begin{code}
nlHsVar :: id -> LHsExpr id
nlHsVar n = noLoc (HsVar n)

nlHsLit :: HsLit -> LHsExpr id
nlHsLit n = noLoc (HsLit n)

nlVarPat :: id -> LPat id
nlVarPat n = noLoc (VarPat n)

nlLitPat :: HsLit -> LPat id
nlLitPat l = noLoc (LitPat l)

nlHsApp :: LHsExpr id -> LHsExpr id -> LHsExpr id
nlHsApp f x = noLoc (HsApp f x)

nlHsIntLit :: Integer -> LHsExpr id
nlHsIntLit n = noLoc (HsLit (HsInt n))

nlHsApps :: id -> [LHsExpr id] -> LHsExpr id
nlHsApps f xs = foldl nlHsApp (nlHsVar f) xs
	     
nlHsVarApps :: id -> [id] -> LHsExpr id
nlHsVarApps f xs = noLoc (foldl mk (HsVar f) (map HsVar xs))
		 where
		   mk f a = HsApp (noLoc f) (noLoc a)

nlConVarPat :: id -> [id] -> LPat id
nlConVarPat con vars = nlConPat con (map nlVarPat vars)

nlInfixConPat :: id -> LPat id -> LPat id -> LPat id
nlInfixConPat con l r = noLoc (ConPatIn (noLoc con) (InfixCon l r))

nlConPat :: id -> [LPat id] -> LPat id
nlConPat con pats = noLoc (ConPatIn (noLoc con) (PrefixCon pats))

nlNullaryConPat :: id -> LPat id
nlNullaryConPat con = noLoc (ConPatIn (noLoc con) (PrefixCon []))

nlWildConPat :: DataCon -> LPat RdrName
nlWildConPat con = noLoc (ConPatIn (noLoc (getRdrName con))
				   (PrefixCon (nOfThem (dataConSourceArity con) nlWildPat)))

nlWildPat :: LPat id
nlWildPat  = noLoc (WildPat placeHolderType)	-- Pre-typechecking

nlHsDo :: HsStmtContext Name -> [LStmt id] -> LHsExpr id -> LHsExpr id
nlHsDo ctxt stmts body = noLoc (mkHsDo ctxt stmts body)

nlHsOpApp :: LHsExpr id -> id -> LHsExpr id -> LHsExpr id
nlHsOpApp e1 op e2 = noLoc (mkHsOpApp e1 op e2)

nlHsLam  :: LMatch id -> LHsExpr id
nlHsPar  :: LHsExpr id -> LHsExpr id
nlHsIf   :: LHsExpr id -> LHsExpr id -> LHsExpr id -> LHsExpr id
nlHsCase :: LHsExpr id -> [LMatch id] -> LHsExpr id
nlList   :: [LHsExpr id] -> LHsExpr id

nlHsLam	match		= noLoc (HsLam (mkMatchGroup [match]))
nlHsPar e		= noLoc (HsPar e)
nlHsIf cond true false	= noLoc (mkHsIf cond true false)
nlHsCase expr matches	= noLoc (HsCase expr (mkMatchGroup matches))
nlList exprs		= noLoc (ExplicitList placeHolderType exprs)

nlHsAppTy :: LHsType name -> LHsType name -> LHsType name
nlHsTyVar :: name                         -> LHsType name
nlHsFunTy :: LHsType name -> LHsType name -> LHsType name

nlHsAppTy f t		= noLoc (HsAppTy f t)
nlHsTyVar x		= noLoc (HsTyVar x)
nlHsFunTy a b		= noLoc (HsFunTy a b)

nlHsTyConApp :: name -> [LHsType name] -> LHsType name
nlHsTyConApp tycon tys  = foldl nlHsAppTy (nlHsTyVar tycon) tys
\end{code}

Tuples.  All these functions are *pre-typechecker* because they lack
types on the tuple.

\begin{code}
mkLHsTupleExpr :: [LHsExpr a] -> LHsExpr a
-- Makes a pre-typechecker boxed tuple, deals with 1 case
mkLHsTupleExpr [e] = e
mkLHsTupleExpr es  = noLoc $ ExplicitTuple (map Present es) Boxed

mkLHsVarTuple :: [a] -> LHsExpr a
mkLHsVarTuple ids  = mkLHsTupleExpr (map nlHsVar ids)

nlTuplePat :: [LPat id] -> Boxity -> LPat id
nlTuplePat pats box = noLoc (TuplePat pats box placeHolderType)

missingTupArg :: HsTupArg a
missingTupArg = Missing placeHolderType
\end{code}

%************************************************************************
%*									*
		Bindings; with a location at the top
%*									*
%************************************************************************

\begin{code}
mkFunBind :: Located id -> [LMatch id] -> HsBind id
-- Not infix, with place holders for coercion and free vars
mkFunBind fn ms = FunBind { fun_id = fn, fun_infix = False, fun_matches = mkMatchGroup ms,
			    fun_co_fn = idHsWrapper, bind_fvs = placeHolderNames,
			    fun_tick = Nothing }


mkHsVarBind :: SrcSpan -> id -> LHsExpr id -> LHsBind id
mkHsVarBind loc var rhs = mk_easy_FunBind loc var [] rhs

mkVarBind :: id -> LHsExpr id -> LHsBind id
mkVarBind var rhs = L (getLoc rhs) $
		    VarBind { var_id = var, var_rhs = rhs, var_inline = False }

------------
mk_easy_FunBind :: SrcSpan -> id -> [LPat id]
		-> LHsExpr id -> LHsBind id

mk_easy_FunBind loc fun pats expr
  = L loc $ mkFunBind (L loc fun) [mkMatch pats expr emptyLocalBinds]

------------
mkMatch :: [LPat id] -> LHsExpr id -> HsLocalBinds id -> LMatch id
mkMatch pats expr binds
  = noLoc (Match (map paren pats) Nothing 
		 (GRHSs (unguardedRHS expr) binds))
  where
    paren lp@(L l p) | hsPatNeedsParens p = L l (ParPat lp) 
		     | otherwise          = lp
\end{code}


%************************************************************************
%*									*
	Collecting binders
%*									*
%************************************************************************

Get all the binders in some HsBindGroups, IN THE ORDER OF APPEARANCE. eg.

...
where
  (x, y) = ...
  f i j  = ...
  [a, b] = ...

it should return [x, y, f, a, b] (remember, order important).

Note [Collect binders only after renaming]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
These functions should only be used on HsSyn *after* the renamer,
to return a [Name] or [Id].  Before renaming the record punning
and wild-card mechanism makes it hard to know what is bound.
So these functions should not be applied to (HsSyn RdrName)

\begin{code}
----------------- Bindings --------------------------
collectLocalBinders :: HsLocalBindsLR idL idR -> [idL]
collectLocalBinders (HsValBinds val_binds) = collectHsValBinders val_binds
collectLocalBinders (HsIPBinds _)   = []
collectLocalBinders EmptyLocalBinds = []

collectHsValBinders :: HsValBindsLR idL idR -> [idL]
collectHsValBinders (ValBindsIn  binds _) = collectHsBindsBinders binds
collectHsValBinders (ValBindsOut binds _) = foldr collect_one [] binds
  where
   collect_one (_,binds) acc = collect_binds binds acc

collectHsBindBinders :: HsBindLR idL idR -> [idL]
collectHsBindBinders b = collect_bind b []

collect_bind :: HsBindLR idL idR -> [idL] -> [idL]
collect_bind (PatBind { pat_lhs = p })    acc = collect_lpat p acc
collect_bind (FunBind { fun_id = L _ f }) acc = f : acc
collect_bind (VarBind { var_id = f })     acc = f : acc
collect_bind (AbsBinds { abs_exports = dbinds, abs_binds = _binds }) acc
  = [dp | (_,dp,_,_) <- dbinds] ++ acc 
	-- ++ foldr collect_bind acc binds
	-- I don't think we want the binders from the nested binds
	-- The only time we collect binders from a typechecked 
	-- binding (hence see AbsBinds) is in zonking in TcHsSyn

collectHsBindsBinders :: LHsBindsLR idL idR -> [idL]
collectHsBindsBinders binds = collect_binds binds []

collectHsBindListBinders :: [LHsBindLR idL idR] -> [idL]
collectHsBindListBinders = foldr (collect_bind . unLoc) []

collect_binds :: LHsBindsLR idL idR -> [idL] -> [idL]
collect_binds binds acc = foldrBag (collect_bind . unLoc) acc binds

collectMethodBinders :: LHsBindsLR RdrName idR -> [Located RdrName]
-- Used exclusively for the bindings of an instance decl which are all FunBinds
collectMethodBinders binds = foldrBag get [] binds
  where
    get (L _ (FunBind { fun_id = f })) fs = f : fs
    get _                              fs = fs	
       -- Someone else complains about non-FunBinds

----------------- Statements --------------------------
collectLStmtsBinders :: [LStmtLR idL idR] -> [idL]
collectLStmtsBinders = concatMap collectLStmtBinders

collectStmtsBinders :: [StmtLR idL idR] -> [idL]
collectStmtsBinders = concatMap collectStmtBinders

collectLStmtBinders :: LStmtLR idL idR -> [idL]
collectLStmtBinders = collectStmtBinders . unLoc

collectStmtBinders :: StmtLR idL idR -> [idL]
  -- Id Binders for a Stmt... [but what about pattern-sig type vars]?
collectStmtBinders (BindStmt pat _ _ _) = collectPatBinders pat
collectStmtBinders (LetStmt binds)      = collectLocalBinders binds
collectStmtBinders (ExprStmt _ _ _)     = []
collectStmtBinders (ParStmt xs)         = collectLStmtsBinders
                                        $ concatMap fst xs
collectStmtBinders (TransformStmt stmts _ _ _)   = collectLStmtsBinders stmts
collectStmtBinders (GroupStmt     stmts _ _ _)   = collectLStmtsBinders stmts
collectStmtBinders (RecStmt { recS_stmts = ss }) = collectLStmtsBinders ss


----------------- Patterns --------------------------
collectPatBinders :: LPat a -> [a]
collectPatBinders pat = collect_lpat pat []

collectPatsBinders :: [LPat a] -> [a]
collectPatsBinders pats = foldr collect_lpat [] pats

-------------
collect_lpat :: LPat name -> [name] -> [name]
collect_lpat (L _ pat) bndrs
  = go pat
  where
    go (VarPat var) 	   	  = var : bndrs
    go (VarPatOut var _) 	  = var : bndrs
	-- See Note [Dictionary binders in ConPatOut]
    go (WildPat _)	      	  = bndrs
    go (LazyPat pat)     	  = collect_lpat pat bndrs
    go (BangPat pat)     	  = collect_lpat pat bndrs
    go (AsPat (L _ a) pat)     	  = a : collect_lpat pat bndrs
    go (ViewPat _ pat _)          = collect_lpat pat bndrs
    go (ParPat  pat)     	  = collect_lpat pat bndrs
				  
    go (ListPat pats _)    	  = foldr collect_lpat bndrs pats
    go (PArrPat pats _)    	  = foldr collect_lpat bndrs pats
    go (TuplePat pats _ _)  	  = foldr collect_lpat bndrs pats
				  
    go (ConPatIn _ ps)            = foldr collect_lpat bndrs (hsConPatArgs ps)
    go (ConPatOut {pat_args=ps})  = foldr collect_lpat bndrs (hsConPatArgs ps)
	-- See Note [Dictionary binders in ConPatOut]
    go (LitPat _)	      	  = bndrs
    go (NPat _ _ _)		  = bndrs
    go (NPlusKPat (L _ n) _ _ _)  = n : bndrs
 				  
    go (SigPatIn pat _)	 	  = collect_lpat pat bndrs
    go (SigPatOut pat _)	  = collect_lpat pat bndrs
    go (QuasiQuotePat _)          = bndrs
    go (TypePat _)                = bndrs
    go (CoPat _ pat _)            = go pat
\end{code}

Note [Dictionary binders in ConPatOut] See also same Note in DsArrows
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Do *not* gather (a) dictionary and (b) dictionary bindings as binders
of a ConPatOut pattern.  For most calls it doesn't matter, because
it's pre-typechecker and there are no ConPatOuts.  But it does matter
more in the desugarer; for example, DsUtils.mkSelectorBinds uses
collectPatBinders.  In a lazy pattern, for example f ~(C x y) = ...,
we want to generate bindings for x,y but not for dictionaries bound by
C.  (The type checker ensures they would not be used.)

Desugaring of arrow case expressions needs these bindings (see DsArrows
and arrowcase1), but SPJ (Jan 2007) says it's safer for it to use its
own pat-binder-collector:

Here's the problem.  Consider

data T a where
   C :: Num a => a -> Int -> T a

f ~(C (n+1) m) = (n,m)

Here, the pattern (C (n+1)) binds a hidden dictionary (d::Num a),
and *also* uses that dictionary to match the (n+1) pattern.  Yet, the
variables bound by the lazy pattern are n,m, *not* the dictionary d.
So in mkSelectorBinds in DsUtils, we want just m,n as the variables bound.

\begin{code}
hsGroupBinders :: HsGroup Name -> [Name]
hsGroupBinders (HsGroup { hs_valds = val_decls, hs_tyclds = tycl_decls,
                          hs_instds = inst_decls, hs_fords = foreign_decls })
-- Collect the binders of a Group
  =  collectHsValBinders val_decls
  ++ hsTyClDeclsBinders tycl_decls inst_decls
  ++ hsForeignDeclsBinders foreign_decls

hsForeignDeclsBinders :: [LForeignDecl Name] -> [Name]
hsForeignDeclsBinders foreign_decls
  = [n | L _ (ForeignImport (L _ n) _ _) <- foreign_decls]

hsTyClDeclsBinders :: [[LTyClDecl Name]] -> [Located (InstDecl Name)] -> [Name]
hsTyClDeclsBinders tycl_decls inst_decls
  = [n | d <- instDeclATs inst_decls ++ concat tycl_decls
       , L _ n <- hsTyClDeclBinders d]

hsTyClDeclBinders :: Eq name => Located (TyClDecl name) -> [Located name]
-- ^ Returns all the /binding/ names of the decl, along with their SrcLocs.
-- The first one is guaranteed to be the name of the decl. For record fields
-- mentioned in multiple constructors, the SrcLoc will be from the first
-- occurence.  We use the equality to filter out duplicate field names

hsTyClDeclBinders (L _ (TyFamily    {tcdLName = name})) = [name]
hsTyClDeclBinders (L _ (TySynonym   {tcdLName = name})) = [name]
hsTyClDeclBinders (L _ (ForeignType {tcdLName = name})) = [name]

hsTyClDeclBinders (L _ (ClassDecl {tcdLName = cls_name, tcdSigs = sigs, tcdATs = ats}))
  = cls_name : 
    concatMap hsTyClDeclBinders ats ++ [n | L _ (TypeSig n _) <- sigs]

hsTyClDeclBinders (L _ (TyData {tcdLName = tc_name, tcdCons = cons}))
  = tc_name : hsConDeclsBinders cons

hsConDeclsBinders :: (Eq name) => [LConDecl name] -> [Located name]
  -- See hsTyClDeclBinders for what this does
  -- The function is boringly complicated because of the records
  -- And since we only have equality, we have to be a little careful
hsConDeclsBinders cons
  = snd (foldl do_one ([], []) cons)
  where
    do_one (flds_seen, acc) (L _ (ConDecl { con_name = lname, con_details = RecCon flds }))
	= (map unLoc new_flds ++ flds_seen, lname : new_flds ++ acc)
	where
	  new_flds = filterOut (\f -> unLoc f `elem` flds_seen) 
			       (map cd_fld_name flds)

    do_one (flds_seen, acc) (L _ (ConDecl { con_name = lname }))
	= (flds_seen, lname:acc)
\end{code}


%************************************************************************
%*									*
	Collecting type signatures from patterns
%*									*
%************************************************************************

\begin{code}
collectSigTysFromPats :: [InPat name] -> [LHsType name]
collectSigTysFromPats pats = foldr collect_sig_lpat [] pats

collectSigTysFromPat :: InPat name -> [LHsType name]
collectSigTysFromPat pat = collect_sig_lpat pat []

collect_sig_lpat :: InPat name -> [LHsType name] -> [LHsType name]
collect_sig_lpat pat acc = collect_sig_pat (unLoc pat) acc

collect_sig_pat :: Pat name -> [LHsType name] -> [LHsType name]
collect_sig_pat (SigPatIn pat ty)  	acc = collect_sig_lpat pat (ty:acc)
collect_sig_pat (TypePat ty)       	acc = ty:acc

collect_sig_pat (LazyPat pat)       acc = collect_sig_lpat pat acc
collect_sig_pat (BangPat pat)       acc = collect_sig_lpat pat acc
collect_sig_pat (AsPat _ pat)       acc = collect_sig_lpat pat acc
collect_sig_pat (ParPat  pat)       acc = collect_sig_lpat pat acc
collect_sig_pat (ListPat pats _)    acc = foldr collect_sig_lpat acc pats
collect_sig_pat (PArrPat pats _)    acc = foldr collect_sig_lpat acc pats
collect_sig_pat (TuplePat pats _ _) acc = foldr collect_sig_lpat acc pats
collect_sig_pat (ConPatIn _ ps)     acc = foldr collect_sig_lpat acc (hsConPatArgs ps)
collect_sig_pat _                   acc = acc       -- Literals, vars, wildcard
\end{code}
