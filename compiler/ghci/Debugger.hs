-----------------------------------------------------------------------------
--
-- GHCi Interactive debugging commands 
--
-- Pepe Iborra (supported by Google SoC) 2006
--
-- ToDo: lots of violation of layering here.  This module should
-- decide whether it is above the GHC API (import GHC and nothing
-- else) or below it.
-- 
-----------------------------------------------------------------------------

module Debugger (pprintClosureCommand, showTerm, pprTypeAndContents) where

import Linker
import RtClosureInspect

import HscTypes
import IdInfo
import Id
import Name
import Var hiding ( varName )
import VarSet
import Name 
import UniqSupply
import TcType
import GHC
import DynFlags
import InteractiveEval
import Outputable
import SrcLoc
import PprTyThing
import MonadUtils

import Exception
import Control.Monad
import Data.List
import Data.Maybe
import Data.IORef

import System.IO
import GHC.Exts

-------------------------------------
-- | The :print & friends commands
-------------------------------------
pprintClosureCommand :: GhcMonad m => Bool -> Bool -> String -> m ()
pprintClosureCommand bindThings force str = do
  tythings <- (catMaybes . concat) `liftM`
                 mapM (\w -> GHC.parseName w >>=
                                mapM GHC.lookupName)
                      (words str)
  let ids = [id | AnId id <- tythings]

  -- Obtain the terms and the recovered type information
  (terms, substs0) <- unzip `liftM` mapM go ids

  -- Apply the substitutions obtained after recovering the types
  modifySession $ \hsc_env ->
    let (substs, skol_vars) = unzip$ map skolemiseSubst substs0
        hsc_ic' = foldr (flip substInteractiveContext)
                        (extendInteractiveContext (hsc_IC hsc_env) [] (unionVarSets skol_vars))
                        substs
     in hsc_env{hsc_IC = hsc_ic'}
  -- Finally, print the Terms
  unqual  <- GHC.getPrintUnqual
  docterms <- mapM showTerm terms
  liftIO $ (printForUser stdout unqual . vcat)
           (zipWith (\id docterm -> ppr id <+> char '=' <+> docterm)
                    ids
                    docterms)
 where
   -- Do the obtainTerm--bindSuspensions-computeSubstitution dance
   go :: GhcMonad m => Id -> m (Term, TvSubst)
   go id = do
       term_    <- GHC.obtainTermFromId maxBound force id
       term     <- tidyTermTyVars term_
       term'    <- if bindThings &&
                      False == isUnliftedTypeKind (termType term)
                     then bindSuspensions term
                     else return term
     -- Before leaving, we compare the type obtained to see if it's more specific
     --  Then, we extract a substitution,
     --  mapping the old tyvars to the reconstructed types.
       let reconstructed_type = termType term
       mb_subst <- withSession $ \hsc_env ->
                     liftIO $ improveRTTIType hsc_env (idType id) (reconstructed_type)
       maybe (return ())
             (\subst -> traceOptIf Opt_D_dump_rtti
                   (fsep $ [text "RTTI Improvement for", ppr id,
                           text "is the substitution:" , ppr subst]))
             mb_subst
       return (term', fromMaybe emptyTvSubst mb_subst)

   tidyTermTyVars :: GhcMonad m => Term -> m Term
   tidyTermTyVars t =
     withSession $ \hsc_env -> do
     let env_tvs      = ic_tyvars (hsc_IC hsc_env)
         my_tvs       = termTyVars t
         tvs          = env_tvs `minusVarSet` my_tvs
         tyvarOccName = nameOccName . tyVarName
         tidyEnv      = (initTidyOccEnv (map tyvarOccName (varSetElems tvs))
                        , env_tvs `intersectVarSet` my_tvs)
     return$ mapTermType (snd . tidyOpenType tidyEnv) t

-- | Give names, and bind in the interactive environment, to all the suspensions
--   included (inductively) in a term
bindSuspensions :: GhcMonad m => Term -> m Term
bindSuspensions t = do
      hsc_env <- getSession
      inScope <- GHC.getBindings
      let ictxt        = hsc_IC hsc_env
          prefix       = "_t"
          alreadyUsedNames = map (occNameString . nameOccName . getName) inScope
          availNames   = map ((prefix++) . show) [(1::Int)..] \\ alreadyUsedNames
      availNames_var  <- liftIO $ newIORef availNames
      (t', stuff)     <- liftIO $ foldTerm (nameSuspensionsAndGetInfos availNames_var) t
      let (names, tys, hvals) = unzip3 stuff
          (tys', skol_vars)   = unzip $ map skolemiseTy tys
      let ids = [ mkGlobalId VanillaGlobal name ty vanillaIdInfo
                | (name,ty) <- zip names tys']
          new_ic = extendInteractiveContext ictxt ids (unionVarSets skol_vars)
      liftIO $ extendLinkEnv (zip names hvals)
      modifySession $ \_ -> hsc_env {hsc_IC = new_ic }
      return t'
     where

--    Processing suspensions. Give names and recopilate info
        nameSuspensionsAndGetInfos :: IORef [String] ->
                                       TermFold (IO (Term, [(Name,Type,HValue)]))
        nameSuspensionsAndGetInfos freeNames = TermFold
                      {
                        fSuspension = doSuspension freeNames
                      , fTerm = \ty dc v tt -> do
                                    tt' <- sequence tt
                                    let (terms,names) = unzip tt'
                                    return (Term ty dc v terms, concat names)
                      , fPrim    = \ty n ->return (Prim ty n,[])
                      , fNewtypeWrap  = 
                                \ty dc t -> do 
                                    (term, names) <- t
                                    return (NewtypeWrap ty dc term, names)
                      , fRefWrap = \ty t -> do
                                    (term, names) <- t 
                                    return (RefWrap ty term, names)
                      }
        doSuspension freeNames ct ty hval _name = do
          name <- atomicModifyIORef freeNames (\x->(tail x, head x))
          n <- newGrimName name
          return (Suspension ct ty hval (Just n), [(n,ty,hval)])


--  A custom Term printer to enable the use of Show instances
showTerm :: GhcMonad m => Term -> m SDoc
showTerm term = do
    dflags       <- GHC.getSessionDynFlags
    if dopt Opt_PrintEvldWithShow dflags
       then cPprTerm (liftM2 (++) (\_y->[cPprShowable]) cPprTermBase) term
       else cPprTerm cPprTermBase term
 where
  cPprShowable prec t@Term{ty=ty, val=val} =
    if not (isFullyEvaluatedTerm t)
     then return Nothing
     else do
        hsc_env <- getSession
        dflags  <- GHC.getSessionDynFlags
        do
           (new_env, bname) <- bindToFreshName hsc_env ty "showme"
           setSession new_env
                      -- XXX: this tries to disable logging of errors
                      -- does this still do what it is intended to do
                      -- with the changed error handling and logging?
           let noop_log _ _ _ _ = return ()
               expr = "show " ++ showSDoc (ppr bname)
           GHC.setSessionDynFlags dflags{log_action=noop_log}
           txt_ <- withExtendedLinkEnv [(bname, val)]
                                         (GHC.compileExpr expr)
           let myprec = 10 -- application precedence. TODO Infix constructors
           let txt = unsafeCoerce# txt_
           if not (null txt) then
             return $ Just$ cparen (prec >= myprec &&
                                         needsParens txt)
                                   (text txt)
            else return Nothing
         `gfinally` do
           setSession hsc_env
           GHC.setSessionDynFlags dflags
  cPprShowable prec NewtypeWrap{ty=new_ty,wrapped_term=t} = 
      cPprShowable prec t{ty=new_ty}
  cPprShowable _ _ = return Nothing

  needsParens ('"':_) = False   -- some simple heuristics to see whether parens
                                -- are redundant in an arbitrary Show output
  needsParens ('(':_) = False
  needsParens txt = ' ' `elem` txt


  bindToFreshName hsc_env ty userName = do
    name <- newGrimName userName
    let ictxt    = hsc_IC hsc_env
        tmp_ids  = ic_tmp_ids ictxt
        id       = mkGlobalId VanillaGlobal name ty vanillaIdInfo
        new_ic   = ictxt { ic_tmp_ids = id : tmp_ids }
    return (hsc_env {hsc_IC = new_ic }, name)

--    Create new uniques and give them sequentially numbered names
newGrimName :: MonadIO m => String -> m Name
newGrimName userName  = do
    us <- liftIO $ mkSplitUniqSupply 'b'
    let unique  = uniqFromSupply us
        occname = mkOccName varName userName
        name    = mkInternalName unique occname noSrcSpan
    return name

pprTypeAndContents :: GhcMonad m => [Id] -> m SDoc
pprTypeAndContents ids = do
  dflags  <- GHC.getSessionDynFlags
  let pefas     = dopt Opt_PrintExplicitForalls dflags
      pcontents = dopt Opt_PrintBindContents dflags
  if pcontents 
    then do
      let depthBound = 100
      terms      <- mapM (GHC.obtainTermFromId depthBound False) ids
      docs_terms <- mapM showTerm terms
      return $ vcat $ zipWith (\ty cts -> ty <+> equals <+> cts)
                             (map (pprTyThing pefas . AnId) ids)
                             docs_terms
    else return $  vcat $ map (pprTyThing pefas . AnId) ids

--------------------------------------------------------------
-- Utils 

traceOptIf :: GhcMonad m => DynFlag -> SDoc -> m ()
traceOptIf flag doc = do
  dflags <- GHC.getSessionDynFlags
  when (dopt flag dflags) $ liftIO $ printForUser stderr alwaysQualify doc
