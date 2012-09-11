%
% (c) The University of Glasgow 2006
% (c) The AQUA Project, Glasgow University, 1998
%
\section[TcForeign]{Typechecking \tr{foreign} declarations}

A foreign declaration is used to either give an externally
implemented function a Haskell type (and calling interface) or
give a Haskell function an external calling interface. Either way,
the range of argument and result types these functions can accommodate
is restricted to what the outside world understands (read C), and this
module checks to see if a foreign declaration has got a legal type.

\begin{code}
module TcForeign 
	( 
	  tcForeignImports
        , tcForeignExports
	) where

#include "HsVersions.h"

import HsSyn

import TcRnMonad
import TcHsType
import TcExpr
import TcEnv

import ForeignCall
import ErrUtils
import Id
#if alpha_TARGET_ARCH
import Type
import SMRep
import MachOp
#endif
import Name
import OccName
import TcType
import DynFlags
import Outputable
import SrcLoc
import Bag
import FastString
\end{code}

\begin{code}
-- Defines a binding
isForeignImport :: LForeignDecl name -> Bool
isForeignImport (L _ (ForeignImport _ _ _)) = True
isForeignImport _			      = False

-- Exports a binding
isForeignExport :: LForeignDecl name -> Bool
isForeignExport (L _ (ForeignExport _ _ _)) = True
isForeignExport _	  	              = False
\end{code}

%************************************************************************
%*									*
\subsection{Imports}
%*									*
%************************************************************************

\begin{code}
tcForeignImports :: [LForeignDecl Name] -> TcM ([Id], [LForeignDecl Id])
tcForeignImports decls
  = mapAndUnzipM (wrapLocSndM tcFImport) (filter isForeignImport decls)

tcFImport :: ForeignDecl Name -> TcM (Id, ForeignDecl Id)
tcFImport fo@(ForeignImport (L loc nm) hs_ty imp_decl)
 = addErrCtxt (foreignDeclCtxt fo)  $ do
   sig_ty <- tcHsSigType (ForSigCtxt nm) hs_ty
   let 
      -- drop the foralls before inspecting the structure
      -- of the foreign type.
	(_, t_ty)	  = tcSplitForAllTys sig_ty
	(arg_tys, res_ty) = tcSplitFunTys t_ty
	id		  = mkLocalId nm sig_ty
 		-- Use a LocalId to obey the invariant that locally-defined 
		-- things are LocalIds.  However, it does not need zonking,
		-- (so TcHsSyn.zonkForeignExports ignores it).
   
   imp_decl' <- tcCheckFIType sig_ty arg_tys res_ty imp_decl
   -- can't use sig_ty here because it :: Type and we need HsType Id
   -- hence the undefined
   return (id, ForeignImport (L loc id) undefined imp_decl')
tcFImport d = pprPanic "tcFImport" (ppr d)
\end{code}


------------ Checking types for foreign import ----------------------
\begin{code}
tcCheckFIType :: Type -> [Type] -> Type -> ForeignImport -> TcM ForeignImport
tcCheckFIType _ arg_tys res_ty (DNImport spec) = do
    checkCg checkDotnet
    dflags <- getDOpts
    checkForeignArgs (isFFIDotnetTy dflags) arg_tys
    checkForeignRes True{-non IO ok-} (isFFIDotnetTy dflags) res_ty
    let (DNCallSpec isStatic kind _ _ _ _) = spec
    case kind of
       DNMethod | not isStatic ->
         case arg_tys of
	   [] -> addErrTc illegalDNMethodSig
	   _  
	    | not (isFFIDotnetObjTy (last arg_tys)) -> addErrTc illegalDNMethodSig
	    | otherwise -> return ()
       _ -> return ()
    return (DNImport (withDNTypes spec (map toDNType arg_tys) (toDNType res_ty)))

tcCheckFIType sig_ty _ _ idecl@(CImport _ _ _ _ (CLabel _)) = do
    checkCg checkCOrAsm
    check (isFFILabelTy sig_ty) (illegalForeignTyErr empty sig_ty)
    return idecl

tcCheckFIType sig_ty arg_tys res_ty idecl@(CImport cconv _ _ _ CWrapper) = do
   	-- Foreign wrapper (former f.e.d.)
   	-- The type must be of the form ft -> IO (FunPtr ft), where ft is a
   	-- valid foreign type.  For legacy reasons ft -> IO (Ptr ft) as well
   	-- as ft -> IO Addr is accepted, too.  The use of the latter two forms
   	-- is DEPRECATED, though.
    checkCg checkCOrAsmOrInterp
    checkCConv cconv
    case arg_tys of
        [arg1_ty] -> do checkForeignArgs isFFIExternalTy arg1_tys
                        checkForeignRes nonIOok  isFFIExportResultTy res1_ty
                        checkForeignRes mustBeIO isFFIDynResultTy    res_ty
                        checkFEDArgs arg1_tys
                  where
                     (arg1_tys, res1_ty) = tcSplitFunTys arg1_ty
        _ -> addErrTc (illegalForeignTyErr empty sig_ty)
    return idecl

tcCheckFIType sig_ty arg_tys res_ty idecl@(CImport cconv safety _ _ (CFunction target))
  | isDynamicTarget target = do -- Foreign import dynamic
      checkCg checkCOrAsmOrInterp
      checkCConv cconv
      case arg_tys of           -- The first arg must be Ptr, FunPtr, or Addr
        []                -> do
          check False (illegalForeignTyErr empty sig_ty)
          return idecl
        (arg1_ty:arg_tys) -> do
          dflags <- getDOpts
          check (isFFIDynArgumentTy arg1_ty)
                (illegalForeignTyErr argument arg1_ty)
          checkForeignArgs (isFFIArgumentTy dflags safety) arg_tys
          checkForeignRes nonIOok (isFFIImportResultTy dflags) res_ty
          return idecl
  | otherwise = do              -- Normal foreign import
      checkCg (checkCOrAsmOrDotNetOrInterp)
      checkCConv cconv
      checkCTarget target
      dflags <- getDOpts
      checkForeignArgs (isFFIArgumentTy dflags safety) arg_tys
      checkForeignRes nonIOok (isFFIImportResultTy dflags) res_ty
      checkMissingAmpersand dflags arg_tys res_ty
      return idecl

-- This makes a convenient place to check
-- that the C identifier is valid for C
checkCTarget :: CCallTarget -> TcM ()
checkCTarget (StaticTarget str) = do
    checkCg checkCOrAsmOrDotNetOrInterp
    check (isCLabelString str) (badCName str)
checkCTarget DynamicTarget = panic "checkCTarget DynamicTarget"

checkMissingAmpersand :: DynFlags -> [Type] -> Type -> TcM ()
checkMissingAmpersand dflags arg_tys res_ty
  | null arg_tys && isFunPtrTy res_ty &&
    dopt Opt_WarnDodgyForeignImports dflags
  = addWarn (ptext (sLit "possible missing & in foreign import of FunPtr"))
  | otherwise
  = return ()
\end{code}

On an Alpha, with foreign export dynamic, due to a giant hack when
building adjustor thunks, we only allow 4 integer arguments with
foreign export dynamic (i.e., 32 bytes of arguments after padding each
argument to a quadword, excluding floating-point arguments).

The check is needed for both via-C and native-code routes

\begin{code}
#include "nativeGen/NCG.h"

checkFEDArgs :: [Type] -> TcM ()
#if alpha_TARGET_ARCH
checkFEDArgs arg_tys
  = check (integral_args <= 32) err
  where
    integral_args = sum [ (machRepByteWidth . argMachRep . primRepToCgRep) prim_rep
			| prim_rep <- map typePrimRep arg_tys,
			  primRepHint prim_rep /= FloatHint ]
    err = ptext (sLit "On Alpha, I can only handle 32 bytes of non-floating-point arguments to foreign export dynamic")
#else
checkFEDArgs _ = return ()
#endif
\end{code}


%************************************************************************
%*									*
\subsection{Exports}
%*									*
%************************************************************************

\begin{code}
tcForeignExports :: [LForeignDecl Name] 
    		 -> TcM (LHsBinds TcId, [LForeignDecl TcId])
tcForeignExports decls
  = foldlM combine (emptyLHsBinds, []) (filter isForeignExport decls)
  where
   combine (binds, fs) fe = do
       (b, f) <- wrapLocSndM tcFExport fe
       return (b `consBag` binds, f:fs)

tcFExport :: ForeignDecl Name -> TcM (LHsBind Id, ForeignDecl Id)
tcFExport fo@(ForeignExport (L loc nm) hs_ty spec) =
   addErrCtxt (foreignDeclCtxt fo)      $ do

   sig_ty <- tcHsSigType (ForSigCtxt nm) hs_ty
   rhs <- tcPolyExpr (nlHsVar nm) sig_ty

   tcCheckFEType sig_ty spec

	  -- we're exporting a function, but at a type possibly more
	  -- constrained than its declared/inferred type. Hence the need
	  -- to create a local binding which will call the exported function
	  -- at a particular type (and, maybe, overloading).


   -- We need to give a name to the new top-level binding that
   -- is *stable* (i.e. the compiler won't change it later),
   -- because this name will be referred to by the C code stub.
   id  <- mkStableIdFromName nm sig_ty loc mkForeignExportOcc
   return (L loc (VarBind id rhs), ForeignExport (L loc id) undefined spec)
tcFExport d = pprPanic "tcFExport" (ppr d)
\end{code}

------------ Checking argument types for foreign export ----------------------

\begin{code}
tcCheckFEType :: Type -> ForeignExport -> TcM ()
tcCheckFEType sig_ty (CExport (CExportStatic str _)) = do
    check (isCLabelString str) (badCName str)
    checkForeignArgs isFFIExternalTy arg_tys
    checkForeignRes nonIOok isFFIExportResultTy res_ty
  where
      -- Drop the foralls before inspecting n
      -- the structure of the foreign type.
    (_, t_ty) = tcSplitForAllTys sig_ty
    (arg_tys, res_ty) = tcSplitFunTys t_ty
tcCheckFEType _ d = pprPanic "tcCheckFEType" (ppr d)
\end{code}



%************************************************************************
%*									*
\subsection{Miscellaneous}
%*									*
%************************************************************************

\begin{code}
------------ Checking argument types for foreign import ----------------------
checkForeignArgs :: (Type -> Bool) -> [Type] -> TcM ()
checkForeignArgs pred tys
  = mapM_ go tys
  where
    go ty = check (pred ty) (illegalForeignTyErr argument ty)

------------ Checking result types for foreign calls ----------------------
-- Check that the type has the form 
--    (IO t) or (t) , and that t satisfies the given predicate.
--
checkForeignRes :: Bool -> (Type -> Bool) -> Type -> TcM ()

nonIOok, mustBeIO :: Bool
nonIOok  = True
mustBeIO = False

checkForeignRes non_io_result_ok pred_res_ty ty
	-- (IO t) is ok, and so is any newtype wrapping thereof
  | Just (_, res_ty, _) <- tcSplitIOType_maybe ty,
    pred_res_ty res_ty
  = return ()
 
  | otherwise
  = check (non_io_result_ok && pred_res_ty ty) 
	  (illegalForeignTyErr result ty)
\end{code}

\begin{code}
checkDotnet :: HscTarget -> Maybe SDoc
#if defined(mingw32_TARGET_OS)
checkDotnet HscC   = Nothing
checkDotnet _      = Just (text "requires C code generation (-fvia-C)")
#else
checkDotnet _      = Just (text "requires .NET support (-filx or win32)")
#endif

checkCOrAsm :: HscTarget -> Maybe SDoc
checkCOrAsm HscC   = Nothing
checkCOrAsm HscAsm = Nothing
checkCOrAsm _
   = Just (text "requires via-C or native code generation (-fvia-C)")

checkCOrAsmOrInterp :: HscTarget -> Maybe SDoc
checkCOrAsmOrInterp HscC           = Nothing
checkCOrAsmOrInterp HscAsm         = Nothing
checkCOrAsmOrInterp HscInterpreted = Nothing
checkCOrAsmOrInterp _
   = Just (text "requires interpreted, C or native code generation")

checkCOrAsmOrDotNetOrInterp :: HscTarget -> Maybe SDoc
checkCOrAsmOrDotNetOrInterp HscC           = Nothing
checkCOrAsmOrDotNetOrInterp HscAsm         = Nothing
checkCOrAsmOrDotNetOrInterp HscInterpreted = Nothing
checkCOrAsmOrDotNetOrInterp _
   = Just (text "requires interpreted, C or native code generation")

checkCg :: (HscTarget -> Maybe SDoc) -> TcM ()
checkCg check = do
   dflags <- getDOpts
   let target = hscTarget dflags
   case target of
     HscNothing -> return ()
     _ ->
       case check target of
	 Nothing  -> return ()
	 Just err -> addErrTc (text "Illegal foreign declaration:" <+> err)
\end{code}
			   
Calling conventions

\begin{code}
checkCConv :: CCallConv -> TcM ()
checkCConv CCallConv  = return ()
#if i386_TARGET_ARCH
checkCConv StdCallConv = return ()
#else
checkCConv StdCallConv = addErrTc (text "calling convention not supported on this architecture: stdcall")
#endif
checkCConv CmmCallConv = panic "checkCConv CmmCallConv"
\end{code}

Warnings

\begin{code}
check :: Bool -> Message -> TcM ()
check True _	   = return ()
check _    the_err = addErrTc the_err

illegalForeignTyErr :: SDoc -> Type -> SDoc
illegalForeignTyErr arg_or_res ty
  = hang (hsep [ptext (sLit "Unacceptable"), arg_or_res, 
                ptext (sLit "type in foreign declaration:")])
	 4 (hsep [ppr ty])

-- Used for 'arg_or_res' argument to illegalForeignTyErr
argument, result :: SDoc
argument = text "argument"
result   = text "result"

badCName :: CLabelString -> Message
badCName target 
   = sep [quotes (ppr target) <+> ptext (sLit "is not a valid C identifier")]

foreignDeclCtxt :: ForeignDecl Name -> SDoc
foreignDeclCtxt fo
  = hang (ptext (sLit "When checking declaration:"))
         4 (ppr fo)

illegalDNMethodSig :: SDoc
illegalDNMethodSig
  = ptext (sLit "'This pointer' expected as last argument")

\end{code}

