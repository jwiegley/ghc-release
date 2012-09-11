%
% (c) The University of Glasgow, 2006
%
\section[HscTypes]{Types for the per-module compiler}

\begin{code}
-- | Types for the per-module compiler
module HscTypes ( 
        -- * 'Ghc' monad stuff
        Ghc(..), GhcT(..), liftGhcT,
        GhcMonad(..), WarnLogMonad(..),
        liftIO,
        ioMsgMaybe, ioMsg,
        logWarnings, clearWarnings, hasWarnings,
        SourceError, GhcApiError, mkSrcErr, srcErrorMessages, mkApiErr,
        throwOneError, handleSourceError,
        reflectGhc, reifyGhc,

	-- * Sessions and compilation state
	Session(..), withSession, modifySession,
        HscEnv(..), hscEPS,
	FinderCache, FindResult(..), ModLocationCache,
	Target(..), TargetId(..), pprTarget, pprTargetId,
	ModuleGraph, emptyMG,

        -- * Information about modules
	ModDetails(..),	emptyModDetails,
	ModGuts(..), CoreModule(..), CgGuts(..), ForeignStubs(..),
        ImportedMods,

	ModSummary(..), ms_mod_name, showModMsg, isBootSummary,
	msHsFilePath, msHiFilePath, msObjFilePath,

        -- * Information about the module being compiled
	HscSource(..), isHsBoot, hscSourceString,	-- Re-exported from DriverPhases
	
	-- * State relating to modules in this package
	HomePackageTable, HomeModInfo(..), emptyHomePackageTable,
	hptInstances, hptRules, hptVectInfo,
	
	-- * State relating to known packages
	ExternalPackageState(..), EpsStats(..), addEpsInStats,
	PackageTypeEnv, PackageIfaceTable, emptyPackageIfaceTable,
	lookupIfaceByModule, emptyModIface,
	
	PackageInstEnv, PackageRuleBase,

        -- * Interactive context
	InteractiveContext(..), emptyInteractiveContext, 
	icPrintUnqual, mkPrintUnqualified, extendInteractiveContext,
        substInteractiveContext,

	-- * Interfaces
	ModIface(..), mkIfaceWarnCache, mkIfaceHashCache, mkIfaceFixCache,
	emptyIfaceWarnCache,

        -- * Fixity
	FixityEnv, FixItem(..), lookupFixity, emptyFixityEnv,

        -- * TyThings and type environments
	TyThing(..),
	tyThingClass, tyThingTyCon, tyThingDataCon, tyThingId,
	implicitTyThings, isImplicitTyThing,
	
	TypeEnv, lookupType, lookupTypeHscEnv, mkTypeEnv, emptyTypeEnv,
	extendTypeEnv, extendTypeEnvList, extendTypeEnvWithIds, lookupTypeEnv,
	typeEnvElts, typeEnvClasses, typeEnvTyCons, typeEnvIds,
	typeEnvDataCons,

        -- * MonadThings
        MonadThings(..),

        -- * Information on imports and exports
	WhetherHasOrphans, IsBootInterface, Usage(..), 
	Dependencies(..), noDependencies,
	NameCache(..), OrigNameCache, OrigIParamCache,
	Avails, availsToNameSet, availsToNameEnv, availName, availNames,
	GenAvailInfo(..), AvailInfo, RdrAvailInfo, 
	IfaceExport,

	-- * Warnings
	Warnings(..), WarningTxt(..), plusWarns,

	-- * Linker stuff
	Linkable(..), isObjectLinkable,
	Unlinked(..), CompiledByteCode,
	isObject, nameOfObject, isInterpretable, byteCodeOfObject,
        
        -- * Program coverage
        HpcInfo(..), emptyHpcInfo, isHpcUsed, AnyHpcUsage,

        -- * Breakpoints
        ModBreaks (..), BreakIndex, emptyModBreaks,

        -- * Vectorisation information
        VectInfo(..), IfaceVectInfo(..), noVectInfo, plusVectInfo, 
        noIfaceVectInfo
    ) where

#include "HsVersions.h"

#ifdef GHCI
import ByteCodeAsm	( CompiledByteCode )
import {-# SOURCE #-}  InteractiveEval ( Resume )
#endif

import RdrName
import Name		( Name, NamedThing, getName, nameOccName, nameModule )
import NameEnv
import NameSet	
import OccName		( OccName, OccEnv, lookupOccEnv, mkOccEnv, emptyOccEnv, 
			  extendOccEnv )
import Module
import InstEnv		( InstEnv, Instance )
import FamInstEnv	( FamInstEnv, FamInst )
import Rules		( RuleBase )
import CoreSyn		( CoreBind )
import VarEnv
import VarSet
import Var
import Id
import Type		

import Class		( Class, classSelIds, classATs, classTyCon )
import TyCon
import DataCon		( DataCon, dataConImplicitIds, dataConWrapId )
import PrelNames	( gHC_PRIM )
import Packages hiding ( Version(..) )
import DynFlags		( DynFlags(..), isOneShot, HscTarget (..) )
import DriverPhases	( HscSource(..), isHsBoot, hscSourceString, Phase )
import BasicTypes	( IPName, Fixity, defaultFixity, WarningTxt(..) )
import OptimizationFuel	( OptFuelState )
import IfaceSyn
import FiniteMap	( FiniteMap )
import CoreSyn		( CoreRule )
import Maybes		( orElse, expectJust, catMaybes )
import Outputable
import BreakArray
import SrcLoc		( SrcSpan, Located )
import LazyUniqFM		( lookupUFM, eltsUFM, emptyUFM )
import UniqSupply	( UniqSupply )
import FastString
import StringBuffer	( StringBuffer )
import Fingerprint
import MonadUtils
import Data.Dynamic     ( Typeable )
import qualified Data.Dynamic as Dyn
import Bag
import ErrUtils

import System.FilePath
import System.Time	( ClockTime )
import Data.IORef
import Data.Array       ( Array, array )
import Data.List
import Control.Monad    ( mplus, guard, liftM )
import Exception
\end{code}


%************************************************************************
%*									*
\subsection{Compilation environment}
%*									*
%************************************************************************


\begin{code}
-- | The Session is a handle to the complete state of a compilation
-- session.  A compilation session consists of a set of modules
-- constituting the current program or library, the context for
-- interactive evaluation, and various caches.
data Session = Session !(IORef HscEnv) !(IORef WarningMessages)

mkSrcErr :: ErrorMessages -> SourceError
srcErrorMessages :: SourceError -> ErrorMessages
mkApiErr :: SDoc -> GhcApiError

throwOneError :: MonadIO m => ErrMsg -> m ab
throwOneError err = liftIO $ throwIO $ mkSrcErr $ unitBag err

-- | A source error is an error that is caused by one or more errors in the
-- source code.  A 'SourceError' is thrown by many functions in the
-- compilation pipeline.  Inside GHC these errors are merely printed via
-- 'log_action', but API clients may treat them differently, for example,
-- insert them into a list box.  If you want the default behaviour, use the
-- idiom:
--
-- > handleSourceError printExceptionAndWarnings $ do
-- >   ... api calls that may fail ...
--
-- The 'SourceError's error messages can be accessed via 'srcErrorMessages'.
-- This list may be empty if the compiler failed due to @-Werror@
-- ('Opt_WarnIsError').
--
-- See 'printExceptionAndWarnings' for more information on what to take care
-- of when writing a custom error handler.
data SourceError = SourceError ErrorMessages

instance Show SourceError where
  show (SourceError msgs) = unlines . map show . bagToList $ msgs
    -- ToDo: is there some nicer way to print this?

sourceErrorTc :: Dyn.TyCon
sourceErrorTc = Dyn.mkTyCon "SourceError"
{-# NOINLINE sourceErrorTc #-}
instance Typeable SourceError where
  typeOf _ = Dyn.mkTyConApp sourceErrorTc []

instance Exception SourceError

mkSrcErr = SourceError

-- | Perform the given action and call the exception handler if the action
-- throws a 'SourceError'.  See 'SourceError' for more information.
handleSourceError :: (ExceptionMonad m) =>
                     (SourceError -> m a) -- ^ exception handler
                  -> m a -- ^ action to perform
                  -> m a
handleSourceError handler act =
  gcatch act (\(e :: SourceError) -> handler e)

srcErrorMessages (SourceError msgs) = msgs

-- | XXX: what exactly is an API error?
data GhcApiError = GhcApiError SDoc

instance Show GhcApiError where
  show (GhcApiError msg) = showSDoc msg

ghcApiErrorTc :: Dyn.TyCon
ghcApiErrorTc = Dyn.mkTyCon "GhcApiError"
{-# NOINLINE ghcApiErrorTc #-}
instance Typeable GhcApiError where
  typeOf _ = Dyn.mkTyConApp ghcApiErrorTc []

instance Exception GhcApiError

mkApiErr = GhcApiError

-- | A monad that allows logging of warnings.
class Monad m => WarnLogMonad m where
  setWarnings  :: WarningMessages -> m ()
  getWarnings :: m WarningMessages

logWarnings :: WarnLogMonad m => WarningMessages -> m ()
logWarnings warns = do
    warns0 <- getWarnings
    setWarnings (unionBags warns warns0)

-- | Clear the log of 'Warnings'.
clearWarnings :: WarnLogMonad m => m ()
clearWarnings = setWarnings emptyBag

-- | Returns true if there were any warnings.
hasWarnings :: WarnLogMonad m => m Bool
hasWarnings = getWarnings >>= return . not . isEmptyBag

-- | A monad that has all the features needed by GHC API calls.
--
-- In short, a GHC monad
--
--   - allows embedding of IO actions,
--
--   - can log warnings,
--
--   - allows handling of (extensible) exceptions, and
--
--   - maintains a current session.
--
-- If you do not use 'Ghc' or 'GhcT', make sure to call 'GHC.initGhcMonad'
-- before any call to the GHC API functions can occur.
--
class (Functor m, MonadIO m, WarnLogMonad m, ExceptionMonad m)
    => GhcMonad m where
  getSession :: m HscEnv
  setSession :: HscEnv -> m ()

-- | Call the argument with the current session.
withSession :: GhcMonad m => (HscEnv -> m a) -> m a
withSession f = getSession >>= f

-- | Set the current session to the result of applying the current session to
-- the argument.
modifySession :: GhcMonad m => (HscEnv -> HscEnv) -> m ()
modifySession f = do h <- getSession
                     setSession $! f h

-- | A minimal implementation of a 'GhcMonad'.  If you need a custom monad,
-- e.g., to maintain additional state consider wrapping this monad or using
-- 'GhcT'.
newtype Ghc a = Ghc { unGhc :: Session -> IO a }

instance Functor Ghc where
  fmap f m = Ghc $ \s -> f `fmap` unGhc m s

instance Monad Ghc where
  return a = Ghc $ \_ -> return a
  m >>= g  = Ghc $ \s -> do a <- unGhc m s; unGhc (g a) s

instance MonadIO Ghc where
  liftIO ioA = Ghc $ \_ -> ioA

instance ExceptionMonad Ghc where
  gcatch act handle =
      Ghc $ \s -> unGhc act s `gcatch` \e -> unGhc (handle e) s
  gblock (Ghc m)   = Ghc $ \s -> gblock (m s)
  gunblock (Ghc m) = Ghc $ \s -> gunblock (m s)

instance WarnLogMonad Ghc where
  setWarnings warns = Ghc $ \(Session _ wref) -> writeIORef wref warns
  -- | Return 'Warnings' accumulated so far.
  getWarnings       = Ghc $ \(Session _ wref) -> readIORef wref

instance GhcMonad Ghc where
  getSession = Ghc $ \(Session r _) -> readIORef r
  setSession s' = Ghc $ \(Session r _) -> writeIORef r s'

-- | A monad transformer to add GHC specific features to another monad.
--
-- Note that the wrapped monad must support IO and handling of exceptions.
newtype GhcT m a = GhcT { unGhcT :: Session -> m a }
liftGhcT :: Monad m => m a -> GhcT m a
liftGhcT m = GhcT $ \_ -> m

instance Functor m => Functor (GhcT m) where
  fmap f m = GhcT $ \s -> f `fmap` unGhcT m s

instance Monad m => Monad (GhcT m) where
  return x = GhcT $ \_ -> return x
  m >>= k  = GhcT $ \s -> do a <- unGhcT m s; unGhcT (k a) s

instance MonadIO m => MonadIO (GhcT m) where
  liftIO ioA = GhcT $ \_ -> liftIO ioA

instance ExceptionMonad m => ExceptionMonad (GhcT m) where
  gcatch act handle =
      GhcT $ \s -> unGhcT act s `gcatch` \e -> unGhcT (handle e) s
  gblock (GhcT m) = GhcT $ \s -> gblock (m s)
  gunblock (GhcT m) = GhcT $ \s -> gunblock (m s)

instance MonadIO m => WarnLogMonad (GhcT m) where
  setWarnings warns = GhcT $ \(Session _ wref) -> liftIO $ writeIORef wref warns
  -- | Return 'Warnings' accumulated so far.
  getWarnings       = GhcT $ \(Session _ wref) -> liftIO $ readIORef wref

instance (Functor m, ExceptionMonad m, MonadIO m) => GhcMonad (GhcT m) where
  getSession = GhcT $ \(Session r _) -> liftIO $ readIORef r
  setSession s' = GhcT $ \(Session r _) -> liftIO $ writeIORef r s'

-- | Lift an IO action returning errors messages into a 'GhcMonad'.
--
-- In order to reduce dependencies to other parts of the compiler, functions
-- outside the "main" parts of GHC return warnings and errors as a parameter
-- and signal success via by wrapping the result in a 'Maybe' type.  This
-- function logs the returned warnings and propagates errors as exceptions
-- (of type 'SourceError').
--
-- This function assumes the following invariants:
--
--  1. If the second result indicates success (is of the form 'Just x'),
--     there must be no error messages in the first result.
--
--  2. If there are no error messages, but the second result indicates failure
--     there should be warnings in the first result.  That is, if the action
--     failed, it must have been due to the warnings (i.e., @-Werror@).
ioMsgMaybe :: GhcMonad m =>
              IO (Messages, Maybe a) -> m a
ioMsgMaybe ioA = do
  ((warns,errs), mb_r) <- liftIO ioA
  logWarnings warns
  case mb_r of
    Nothing -> liftIO $ throwIO (mkSrcErr errs)
    Just r  -> ASSERT( isEmptyBag errs ) return r

-- | Lift a non-failing IO action into a 'GhcMonad'.
--
-- Like 'ioMsgMaybe', but assumes that the action will never return any error
-- messages.
ioMsg :: GhcMonad m => IO (Messages, a) -> m a
ioMsg ioA = do
    ((warns,errs), r) <- liftIO ioA
    logWarnings warns
    ASSERT( isEmptyBag errs ) return r

-- | Reflect a computation in the 'Ghc' monad into the 'IO' monad.
--
-- You can use this to call functions returning an action in the 'Ghc' monad
-- inside an 'IO' action.  This is needed for some (too restrictive) callback
-- arguments of some library functions:
--
-- > libFunc :: String -> (Int -> IO a) -> IO a
-- > ghcFunc :: Int -> Ghc a
-- >
-- > ghcFuncUsingLibFunc :: String -> Ghc a -> Ghc a
-- > ghcFuncUsingLibFunc str =
-- >   reifyGhc $ \s ->
-- >     libFunc $ \i -> do
-- >       reflectGhc (ghcFunc i) s
--
reflectGhc :: Ghc a -> Session -> IO a
reflectGhc m = unGhc m

-- > Dual to 'reflectGhc'.  See its documentation.
reifyGhc :: (Session -> IO a) -> Ghc a
reifyGhc act = Ghc $ act
\end{code}

\begin{code}
-- | HscEnv is like 'Session', except that some of the fields are immutable.
-- An HscEnv is used to compile a single module from plain Haskell source
-- code (after preprocessing) to either C, assembly or C--.  Things like
-- the module graph don't change during a single compilation.
--
-- Historical note: \"hsc\" used to be the name of the compiler binary,
-- when there was a separate driver and compiler.  To compile a single
-- module, the driver would invoke hsc on the source code... so nowadays
-- we think of hsc as the layer of the compiler that deals with compiling
-- a single module.
data HscEnv 
  = HscEnv { 
	hsc_dflags :: DynFlags,
		-- ^ The dynamic flag settings

	hsc_targets :: [Target],
		-- ^ The targets (or roots) of the current session

	hsc_mod_graph :: ModuleGraph,
		-- ^ The module graph of the current session

	hsc_IC :: InteractiveContext,
		-- ^ The context for evaluating interactive statements

	hsc_HPT    :: HomePackageTable,
		-- ^ The home package table describes already-compiled
		-- home-package modules, /excluding/ the module we 
		-- are compiling right now.
		-- (In one-shot mode the current module is the only
		--  home-package module, so hsc_HPT is empty.  All other
		--  modules count as \"external-package\" modules.
		--  However, even in GHCi mode, hi-boot interfaces are
		--  demand-loaded into the external-package table.)
		--
		-- 'hsc_HPT' is not mutable because we only demand-load 
		-- external packages; the home package is eagerly 
		-- loaded, module by module, by the compilation manager.
		--	
		-- The HPT may contain modules compiled earlier by @--make@
		-- but not actually below the current module in the dependency
		-- graph.

		-- (This changes a previous invariant: changed Jan 05.)
	
	hsc_EPS	:: {-# UNPACK #-} !(IORef ExternalPackageState),
	        -- ^ Information about the currently loaded external packages.
	        -- This is mutable because packages will be demand-loaded during
	        -- a compilation run as required.
	
	hsc_NC	:: {-# UNPACK #-} !(IORef NameCache),
		-- ^ As with 'hsc_EPS', this is side-effected by compiling to
		-- reflect sucking in interface files.  They cache the state of
		-- external interface files, in effect.

	hsc_FC   :: {-# UNPACK #-} !(IORef FinderCache),
	        -- ^ The cached result of performing finding in the file system
	hsc_MLC  :: {-# UNPACK #-} !(IORef ModLocationCache),
		-- ^ This caches the location of modules, so we don't have to 
		-- search the filesystem multiple times. See also 'hsc_FC'.

        hsc_OptFuel :: OptFuelState,
                -- ^ Settings to control the use of \"optimization fuel\":
                -- by limiting the number of transformations,
                -- we can use binary search to help find compiler bugs.

        hsc_type_env_var :: Maybe (Module, IORef TypeEnv),
                -- ^ Used for one-shot compilation only, to initialise
                -- the 'IfGblEnv'. See 'TcRnTypes.tcg_type_env_var' for 
                -- 'TcRunTypes.TcGblEnv'

        hsc_global_rdr_env :: GlobalRdrEnv,
                -- ^ A mapping from 'RdrName's that are in global scope during
                -- the compilation of the current file to more detailed
                -- information about those names. Not necessarily just the
                -- names directly imported by the module being compiled!
        
        hsc_global_type_env :: TypeEnv
                -- ^ Typing information about all those things in global scope.
                -- Not necessarily just the things directly imported by the module 
                -- being compiled!
 }

hscEPS :: HscEnv -> IO ExternalPackageState
hscEPS hsc_env = readIORef (hsc_EPS hsc_env)

-- | A compilation target.
--
-- A target may be supplied with the actual text of the
-- module.  If so, use this instead of the file contents (this
-- is for use in an IDE where the file hasn't been saved by
-- the user yet).
data Target = Target
      { targetId           :: TargetId  -- ^ module or filename
      , targetAllowObjCode :: Bool      -- ^ object code allowed?
      , targetContents     :: Maybe (StringBuffer,ClockTime)
                                        -- ^ in-memory text buffer?
      }

data TargetId
  = TargetModule ModuleName
	-- ^ A module name: search for the file
  | TargetFile FilePath (Maybe Phase)
	-- ^ A filename: preprocess & parse it to find the module name.
	-- If specified, the Phase indicates how to compile this file
	-- (which phase to start from).  Nothing indicates the starting phase
	-- should be determined from the suffix of the filename.
  deriving Eq

pprTarget :: Target -> SDoc
pprTarget (Target id obj _) = 
   (if obj then char '*' else empty) <> pprTargetId id

instance Outputable Target where
    ppr = pprTarget

pprTargetId :: TargetId -> SDoc
pprTargetId (TargetModule m) = ppr m
pprTargetId (TargetFile f _) = text f

instance Outputable TargetId where
    ppr = pprTargetId

-- | Helps us find information about modules in the home package
type HomePackageTable  = ModuleNameEnv HomeModInfo
	-- Domain = modules in the home package that have been fully compiled
	-- "home" package name cached here for convenience

-- | Helps us find information about modules in the imported packages
type PackageIfaceTable = ModuleEnv ModIface
	-- Domain = modules in the imported packages

emptyHomePackageTable :: HomePackageTable
emptyHomePackageTable  = emptyUFM

emptyPackageIfaceTable :: PackageIfaceTable
emptyPackageIfaceTable = emptyModuleEnv

-- | Information about modules in the package being compiled
data HomeModInfo 
  = HomeModInfo { hm_iface    :: !ModIface,     -- ^ The basic loaded interface file: every
                                                -- loaded module has one of these, even if
                                                -- it is imported from another package
		  hm_details  :: !ModDetails,   -- ^ Extra information that has been created
		                                -- from the 'ModIface' for the module,
		                                -- typically during typechecking
		  hm_linkable :: !(Maybe Linkable)
		-- ^ The actual artifact we would like to link to access
		-- things in this module.
		--
		-- 'hm_linkable' might be Nothing:
		--
		--   1. If this is an .hs-boot module
		--
		--   2. Temporarily during compilation if we pruned away
		--      the old linkable because it was out of date.
		--
		-- After a complete compilation ('GHC.load'), all 'hm_linkable'
		-- fields in the 'HomePackageTable' will be @Just@.
		--
		-- When re-linking a module ('HscMain.HscNoRecomp'), we construct
		-- the 'HomeModInfo' by building a new 'ModDetails' from the
		-- old 'ModIface' (only).
        }

-- | Find the 'ModIface' for a 'Module', searching in both the loaded home
-- and external package module information
lookupIfaceByModule
	:: DynFlags
	-> HomePackageTable
	-> PackageIfaceTable
	-> Module
	-> Maybe ModIface
lookupIfaceByModule dflags hpt pit mod
  | modulePackageId mod == thisPackage dflags
  = 	-- The module comes from the home package, so look first
	-- in the HPT.  If it's not from the home package it's wrong to look
	-- in the HPT, because the HPT is indexed by *ModuleName* not Module
    fmap hm_iface (lookupUFM hpt (moduleName mod)) 
    `mplus` lookupModuleEnv pit mod

  | otherwise = lookupModuleEnv pit mod		-- Look in PIT only 

-- If the module does come from the home package, why do we look in the PIT as well?
-- (a) In OneShot mode, even home-package modules accumulate in the PIT
-- (b) Even in Batch (--make) mode, there is *one* case where a home-package
--     module is in the PIT, namely GHC.Prim when compiling the base package.
-- We could eliminate (b) if we wanted, by making GHC.Prim belong to a package
-- of its own, but it doesn't seem worth the bother.
\end{code}


\begin{code}
hptInstances :: HscEnv -> (ModuleName -> Bool) -> ([Instance], [FamInst])
-- ^ Find all the instance declarations (of classes and families) that are in
-- modules imported by this one, directly or indirectly, and are in the Home
-- Package Table.  This ensures that we don't see instances from modules @--make@
-- compiled before this one, but which are not below this one.
hptInstances hsc_env want_this_module
  = let (insts, famInsts) = unzip $ flip hptAllThings hsc_env $ \mod_info -> do
                guard (want_this_module (moduleName (mi_module (hm_iface mod_info))))
                let details = hm_details mod_info
                return (md_insts details, md_fam_insts details)
    in (concat insts, concat famInsts)

hptVectInfo :: HscEnv -> VectInfo
-- ^ Get the combined VectInfo of all modules in the home package table.  In
-- contrast to instances and rules, we don't care whether the modules are
-- \"below\" us in the dependency sense.  The VectInfo of those modules not \"below\" 
-- us does not affect the compilation of the current module.
hptVectInfo = concatVectInfo . hptAllThings ((: []) . md_vect_info . hm_details)

hptRules :: HscEnv -> [(ModuleName, IsBootInterface)] -> [CoreRule]
-- ^ Get rules from modules \"below\" this one (in the dependency sense)
hptRules = hptSomeThingsBelowUs (md_rules . hm_details) False

hptAllThings :: (HomeModInfo -> [a]) -> HscEnv -> [a]
hptAllThings extract hsc_env = concatMap extract (eltsUFM (hsc_HPT hsc_env))

hptSomeThingsBelowUs :: (HomeModInfo -> [a]) -> Bool -> HscEnv -> [(ModuleName, IsBootInterface)] -> [a]
-- Get things from modules \"below\" this one (in the dependency sense)
-- C.f Inst.hptInstances
hptSomeThingsBelowUs extract include_hi_boot hsc_env deps
 | isOneShot (ghcMode (hsc_dflags hsc_env)) = []
  | otherwise
  = let 
	hpt = hsc_HPT hsc_env
    in
    [ thing
    |	-- Find each non-hi-boot module below me
      (mod, is_boot_mod) <- deps
    , include_hi_boot || not is_boot_mod

	-- unsavoury: when compiling the base package with --make, we
	-- sometimes try to look up RULES etc for GHC.Prim.  GHC.Prim won't
	-- be in the HPT, because we never compile it; it's in the EPT
	-- instead.  ToDo: clean up, and remove this slightly bogus
	-- filter:
    , mod /= moduleName gHC_PRIM

	-- Look it up in the HPT
    , let things = case lookupUFM hpt mod of
		    Just info -> extract info
		    Nothing -> pprTrace "WARNING in hptSomeThingsBelowUs" msg [] 
	  msg = vcat [ptext (sLit "missing module") <+> ppr mod,
		      ptext (sLit "Probable cause: out-of-date interface files")]
			-- This really shouldn't happen, but see Trac #962

	-- And get its dfuns
    , thing <- things ]

\end{code}

%************************************************************************
%*									*
\subsection{The Finder cache}
%*									*
%************************************************************************

\begin{code}
-- | The 'FinderCache' maps home module names to the result of
-- searching for that module.  It records the results of searching for
-- modules along the search path.  On @:load@, we flush the entire
-- contents of this cache.
--
-- Although the @FinderCache@ range is 'FindResult' for convenience ,
-- in fact it will only ever contain 'Found' or 'NotFound' entries.
--
type FinderCache = ModuleNameEnv FindResult

-- | The result of searching for an imported module.
data FindResult
  = Found ModLocation Module
	-- ^ The module was found
  | NoPackage PackageId
	-- ^ The requested package was not found
  | FoundMultiple [PackageId]
	-- ^ _Error_: both in multiple packages
  | PackageHidden PackageId
	-- ^ For an explicit source import, the package containing the module is
	-- not exposed.
  | ModuleHidden  PackageId
	-- ^ For an explicit source import, the package containing the module is
	-- exposed, but the module itself is hidden.
  | NotFound [FilePath] (Maybe PackageId)
	-- ^ The module was not found, the specified places were searched
  | NotFoundInPackage PackageId
	-- ^ The module was not found in this package

-- | Cache that remembers where we found a particular module.  Contains both
-- home modules and package modules.  On @:load@, only home modules are
-- purged from this cache.
type ModLocationCache = ModuleEnv ModLocation
\end{code}

%************************************************************************
%*									*
\subsection{Symbol tables and Module details}
%*									*
%************************************************************************

\begin{code}
-- | A 'ModIface' plus a 'ModDetails' summarises everything we know 
-- about a compiled module.  The 'ModIface' is the stuff *before* linking,
-- and can be written out to an interface file. The 'ModDetails is after 
-- linking and can be completely recovered from just the 'ModIface'.
-- 
-- When we read an interface file, we also construct a 'ModIface' from it,
-- except that we explicitly make the 'mi_decls' and a few other fields empty;
-- as when reading we consolidate the declarations etc. into a number of indexed
-- maps and environments in the 'ExternalPackageState'.
data ModIface 
   = ModIface {
        mi_module   :: !Module,             -- ^ Name of the module we are for
        mi_iface_hash :: !Fingerprint,      -- ^ Hash of the whole interface
        mi_mod_hash :: !Fingerprint,	    -- ^ Hash of the ABI only

        mi_orphan   :: !WhetherHasOrphans,  -- ^ Whether this module has orphans
        mi_finsts   :: !WhetherHasFamInst,  -- ^ Whether this module has family instances
	mi_boot	    :: !IsBootInterface,    -- ^ Read from an hi-boot file?

	mi_deps	    :: Dependencies,
	        -- ^ The dependencies of the module, consulted for directly
	        -- imported modules only
	
		-- This is consulted for directly-imported modules,
		-- but not for anything else (hence lazy)
        mi_usages   :: [Usage],
                -- ^ Usages; kept sorted so that it's easy to decide
		-- whether to write a new iface file (changing usages
		-- doesn't affect the hash of this module)
        
		-- NOT STRICT!  we read this field lazily from the interface file
		-- It is *only* consulted by the recompilation checker

		-- Exports
		-- Kept sorted by (mod,occ), to make version comparisons easier
        mi_exports  :: ![IfaceExport],
                -- ^ Records the modules that are the declaration points for things
                -- exported by this module, and the 'OccName's of those things
        
        mi_exp_hash :: !Fingerprint,	-- ^ Hash of export list

        mi_fixities :: [(OccName,Fixity)],
                -- ^ Fixities
        
		-- NOT STRICT!  we read this field lazily from the interface file

	mi_warns  :: Warnings,
		-- ^ Warnings
		
		-- NOT STRICT!  we read this field lazily from the interface file

		-- Type, class and variable declarations
		-- The hash of an Id changes if its fixity or deprecations change
		--	(as well as its type of course)
		-- Ditto data constructors, class operations, except that 
		-- the hash of the parent class/tycon changes
	mi_decls :: [(Fingerprint,IfaceDecl)],	-- ^ Sorted type, variable, class etc. declarations

        mi_globals  :: !(Maybe GlobalRdrEnv),
		-- ^ Binds all the things defined at the top level in
		-- the /original source/ code for this module. which
		-- is NOT the same as mi_exports, nor mi_decls (which
		-- may contains declarations for things not actually
		-- defined by the user).  Used for GHCi and for inspecting
		-- the contents of modules via the GHC API only.
		--
		-- (We need the source file to figure out the
		-- top-level environment, if we didn't compile this module
		-- from source then this field contains @Nothing@).
		--
		-- Strictly speaking this field should live in the
		-- 'HomeModInfo', but that leads to more plumbing.

		-- Instance declarations and rules
	mi_insts     :: [IfaceInst],			-- ^ Sorted class instance
	mi_fam_insts :: [IfaceFamInst],			-- ^ Sorted family instances
	mi_rules     :: [IfaceRule],			-- ^ Sorted rules
	mi_orphan_hash :: !Fingerprint,	-- ^ Hash for orphan rules and 
					-- class and family instances
					-- combined

        mi_vect_info :: !IfaceVectInfo, -- ^ Vectorisation information

		-- Cached environments for easy lookup
		-- These are computed (lazily) from other fields
		-- and are not put into the interface file
	mi_warn_fn  :: Name -> Maybe WarningTxt,        -- ^ Cached lookup for 'mi_warns'
	mi_fix_fn  :: OccName -> Fixity,	        -- ^ Cached lookup for 'mi_fixities'
	mi_hash_fn :: OccName -> Maybe (OccName, Fingerprint),
                        -- ^ Cached lookup for 'mi_decls'.
			-- The @Nothing@ in 'mi_hash_fn' means that the thing
			-- isn't in decls. It's useful to know that when
			-- seeing if we are up to date wrt. the old interface.
                        -- The 'OccName' is the parent of the name, if it has one.
	mi_hpc    :: !AnyHpcUsage
	        -- ^ True if this program uses Hpc at any point in the program.
     }

-- | The 'ModDetails' is essentially a cache for information in the 'ModIface'
-- for home modules only. Information relating to packages will be loaded into
-- global environments in 'ExternalPackageState'.
data ModDetails
   = ModDetails {
	-- The next two fields are created by the typechecker
	md_exports   :: [AvailInfo],
        md_types     :: !TypeEnv,       -- ^ Local type environment for this particular module
        md_insts     :: ![Instance],    -- ^ 'DFunId's for the instances in this module
        md_fam_insts :: ![FamInst],
        md_rules     :: ![CoreRule],    -- ^ Domain may include 'Id's from other modules
        md_vect_info :: !VectInfo       -- ^ Module vectorisation information
     }

emptyModDetails :: ModDetails
emptyModDetails = ModDetails { md_types = emptyTypeEnv,
			       md_exports = [],
			       md_insts     = [],
			       md_rules     = [],
			       md_fam_insts = [],
                               md_vect_info = noVectInfo
                             } 

-- | Records the modules directly imported by a module for extracting e.g. usage information
type ImportedMods = ModuleEnv [(ModuleName, Bool, SrcSpan)]
-- TODO: we are not actually using the codomain of this type at all, so it can be
-- replaced with ModuleEnv ()

-- | A ModGuts is carried through the compiler, accumulating stuff as it goes
-- There is only one ModGuts at any time, the one for the module
-- being compiled right now.  Once it is compiled, a 'ModIface' and 
-- 'ModDetails' are extracted and the ModGuts is dicarded.
data ModGuts
  = ModGuts {
        mg_module    :: !Module,         -- ^ Module being compiled
	mg_boot      :: IsBootInterface, -- ^ Whether it's an hs-boot module
	mg_exports   :: ![AvailInfo],	 -- ^ What it exports
	mg_deps	     :: !Dependencies,	 -- ^ What it depends on, directly or
	                                 -- otherwise
	mg_dir_imps  :: !ImportedMods,	 -- ^ Directly-imported modules; used to
					 -- generate initialisation code
	mg_used_names:: !NameSet,	 -- ^ What the module needed (used in 'MkIface.mkIface')

        mg_rdr_env   :: !GlobalRdrEnv,	 -- ^ Top-level lexical environment

	-- These fields all describe the things **declared in this module**
	mg_fix_env   :: !FixityEnv,	 -- ^ Fixities declared in this module
	                                 -- TODO: I'm unconvinced this is actually used anywhere
	mg_types     :: !TypeEnv,        -- ^ Types declared in this module
	mg_insts     :: ![Instance],	 -- ^ Class instances declared in this module
	mg_fam_insts :: ![FamInst],	 -- ^ Family instances declared in this module
        mg_rules     :: ![CoreRule],	 -- ^ Before the core pipeline starts, contains 
                                         -- rules declared in this module. After the core
                                         -- pipeline starts, it is changed to contain all
                                         -- known rules for those things imported
	mg_binds     :: ![CoreBind],	 -- ^ Bindings for this module
	mg_foreign   :: !ForeignStubs,   -- ^ Foreign exports declared in this module
	mg_warns     :: !Warnings,	 -- ^ Warnings declared in the module
	mg_hpc_info  :: !HpcInfo,        -- ^ Coverage tick boxes in the module
        mg_modBreaks :: !ModBreaks,      -- ^ Breakpoints for the module
        mg_vect_info :: !VectInfo,       -- ^ Pool of vectorised declarations in the module

	-- The next two fields are unusual, because they give instance
	-- environments for *all* modules in the home package, including
	-- this module, rather than for *just* this module.  
	-- Reason: when looking up an instance we don't want to have to
	--	  look at each module in the home package in turn
	mg_inst_env     :: InstEnv,
        -- ^ Class instance environment from /home-package/ modules (including
	-- this one); c.f. 'tcg_inst_env'
	mg_fam_inst_env :: FamInstEnv
        -- ^ Type-family instance enviroment for /home-package/ modules
	-- (including this one); c.f. 'tcg_fam_inst_env'
    }

-- The ModGuts takes on several slightly different forms:
--
-- After simplification, the following fields change slightly:
--	mg_rules	Orphan rules only (local ones now attached to binds)
--	mg_binds	With rules attached

-- | A CoreModule consists of just the fields of a 'ModGuts' that are needed for
-- the 'GHC.compileToCoreModule' interface.
data CoreModule
  = CoreModule {
      -- | Module name
      cm_module   :: !Module,
      -- | Type environment for types declared in this module
      cm_types    :: !TypeEnv,
      -- | Declarations
      cm_binds    :: [CoreBind],
      -- | Imports
      cm_imports  :: ![Module]
    }

instance Outputable CoreModule where
   ppr (CoreModule {cm_module = mn, cm_types = te, cm_binds = cb}) =
      text "%module" <+> ppr mn <+> ppr te $$ vcat (map ppr cb)

-- The ModGuts takes on several slightly different forms:
--
-- After simplification, the following fields change slightly:
--	mg_rules	Orphan rules only (local ones now attached to binds)
--	mg_binds	With rules attached


---------------------------------------------------------
-- The Tidy pass forks the information about this module: 
--	* one lot goes to interface file generation (ModIface)
--	  and later compilations (ModDetails)
--	* the other lot goes to code generation (CgGuts)

-- | A restricted form of 'ModGuts' for code generation purposes
data CgGuts 
  = CgGuts {
	cg_module   :: !Module, -- ^ Module being compiled

	cg_tycons   :: [TyCon],
		-- ^ Algebraic data types (including ones that started
		-- life as classes); generate constructors and info
		-- tables. Includes newtypes, just for the benefit of
		-- External Core

	cg_binds    :: [CoreBind],
		-- ^ The tidied main bindings, including
		-- previously-implicit bindings for record and class
		-- selectors, and data construtor wrappers.  But *not*
		-- data constructor workers; reason: we we regard them
		-- as part of the code-gen of tycons

	cg_dir_imps :: ![Module],
		-- ^ Directly-imported modules; used to generate
		-- initialisation code

	cg_foreign  :: !ForeignStubs,	-- ^ Foreign export stubs
	cg_dep_pkgs :: ![PackageId],	-- ^ Dependent packages, used to 
	                                -- generate #includes for C code gen
        cg_hpc_info :: !HpcInfo,        -- ^ Program coverage tick box information
        cg_modBreaks :: !ModBreaks      -- ^ Module breakpoints
    }

-----------------------------------
-- | Foreign export stubs
data ForeignStubs = NoStubs             -- ^ We don't have any stubs
		  | ForeignStubs
			SDoc 		
			SDoc 		
		   -- ^ There are some stubs. Parameters:
		   --
		   --  1) Header file prototypes for
                   --     "foreign exported" functions
                   --
                   --  2) C stubs to use when calling
                   --     "foreign exported" functions
\end{code}

\begin{code}
emptyModIface :: Module -> ModIface
emptyModIface mod
  = ModIface { mi_module   = mod,
	       mi_iface_hash = fingerprint0,
	       mi_mod_hash = fingerprint0,
	       mi_orphan   = False,
	       mi_finsts   = False,
	       mi_boot	   = False,
	       mi_deps     = noDependencies,
	       mi_usages   = [],
	       mi_exports  = [],
	       mi_exp_hash = fingerprint0,
	       mi_fixities = [],
	       mi_warns    = NoWarnings,
	       mi_insts     = [],
	       mi_fam_insts = [],
	       mi_rules     = [],
	       mi_decls     = [],
	       mi_globals   = Nothing,
	       mi_orphan_hash = fingerprint0,
               mi_vect_info = noIfaceVectInfo,
	       mi_warn_fn    = emptyIfaceWarnCache,
	       mi_fix_fn    = emptyIfaceFixCache,
	       mi_hash_fn   = emptyIfaceHashCache,
	       mi_hpc       = False
    }		
\end{code}


%************************************************************************
%*									*
\subsection{The interactive context}
%*									*
%************************************************************************

\begin{code}
-- | Interactive context, recording information relevant to GHCi
data InteractiveContext 
  = InteractiveContext { 
	ic_toplev_scope :: [Module],	-- ^ The context includes the "top-level" scope of
					-- these modules

	ic_exports :: [Module],		-- ^ The context includes just the exports of these
					-- modules

	ic_rn_gbl_env :: GlobalRdrEnv,	-- ^ The contexts' cached 'GlobalRdrEnv', built from
					-- 'ic_toplev_scope' and 'ic_exports'

	ic_tmp_ids :: [Id],             -- ^ Names bound during interaction with the user.
                                        -- Later Ids shadow earlier ones with the same OccName.

        ic_tyvars :: TyVarSet           -- ^ Skolem type variables free in
                                        -- 'ic_tmp_ids'.  These arise at
                                        -- breakpoints in a polymorphic 
                                        -- context, where we have only partial
                                        -- type information.

#ifdef GHCI
        , ic_resume :: [Resume]         -- ^ The stack of breakpoint contexts
#endif
    }


emptyInteractiveContext :: InteractiveContext
emptyInteractiveContext
  = InteractiveContext { ic_toplev_scope = [],
			 ic_exports = [],
			 ic_rn_gbl_env = emptyGlobalRdrEnv,
			 ic_tmp_ids = [],
                         ic_tyvars = emptyVarSet
#ifdef GHCI
                         , ic_resume = []
#endif
                       }

icPrintUnqual :: DynFlags -> InteractiveContext -> PrintUnqualified
icPrintUnqual dflags ictxt = mkPrintUnqualified dflags (ic_rn_gbl_env ictxt)


extendInteractiveContext
        :: InteractiveContext
        -> [Id]
        -> TyVarSet
        -> InteractiveContext
extendInteractiveContext ictxt ids tyvars
  = ictxt { ic_tmp_ids =  snub((ic_tmp_ids ictxt \\ ids) ++ ids),
                          -- NB. must be this way around, because we want
                          -- new ids to shadow existing bindings.
            ic_tyvars   = ic_tyvars ictxt `unionVarSet` tyvars }
    where snub = map head . group . sort

substInteractiveContext :: InteractiveContext -> TvSubst -> InteractiveContext
substInteractiveContext ictxt subst | isEmptyTvSubst subst = ictxt
substInteractiveContext ictxt@InteractiveContext{ic_tmp_ids=ids} subst =
   let ids'     = map (\id -> id `setIdType` substTy subst (idType id)) ids
       subst_dom= varEnvKeys$ getTvSubstEnv subst
       subst_ran= varEnvElts$ getTvSubstEnv subst
       new_tvs  = [ tv | Just tv <- map getTyVar_maybe subst_ran]  
       ic_tyvars'= (`delVarSetListByKey` subst_dom) 
                 . (`extendVarSetList`   new_tvs)
                   $ ic_tyvars ictxt
    in ictxt { ic_tmp_ids = ids'
             , ic_tyvars   = ic_tyvars' }

          where delVarSetListByKey = foldl' delVarSetByKey
\end{code}

%************************************************************************
%*									*
        Building a PrintUnqualified		
%*									*
%************************************************************************

Deciding how to print names is pretty tricky.  We are given a name
P:M.T, where P is the package name, M is the defining module, and T is
the occurrence name, and we have to decide in which form to display
the name given a GlobalRdrEnv describing the current scope.

Ideally we want to display the name in the form in which it is in
scope.  However, the name might not be in scope at all, and that's
where it gets tricky.  Here are the cases:

 1. T   uniquely maps to  P:M.T                         --->  "T"
 2. there is an X for which X.T uniquely maps to  P:M.T --->  "X.T"
 3. there is no binding for "M.T"                       --->  "M.T"
 4. otherwise                                           --->  "P:M.T"

3 and 4 apply when P:M.T is not in scope.  In these cases we want to
refer to the name as "M.T", but "M.T" might mean something else in the
current scope (e.g. if there's an "import X as M"), so to avoid
confusion we avoid using "M.T" if there's already a binding for it.

There's one further subtlety: if the module M cannot be imported
because it is not exposed by any package, then we must refer to it as
"P:M".  This is handled by the qual_mod component of PrintUnqualified.

\begin{code}
-- | Creates some functions that work out the best ways to format
-- names for the user according to a set of heuristics
mkPrintUnqualified :: DynFlags -> GlobalRdrEnv -> PrintUnqualified
mkPrintUnqualified dflags env = (qual_name, qual_mod)
  where
  qual_name mod occ	-- The (mod,occ) pair is the original name of the thing
        | [gre] <- unqual_gres, right_name gre = NameUnqual
		-- If there's a unique entity that's in scope unqualified with 'occ'
		-- AND that entity is the right one, then we can use the unqualified name

        | [gre] <- qual_gres = NameQual (get_qual_mod (gre_prov gre))

        | null qual_gres = 
              if null (lookupGRE_RdrName (mkRdrQual (moduleName mod) occ) env)
                   then NameNotInScope1
                   else NameNotInScope2

	| otherwise = panic "mkPrintUnqualified"
      where
	right_name gre = nameModule (gre_name gre) == mod

        unqual_gres = lookupGRE_RdrName (mkRdrUnqual occ) env
        qual_gres   = filter right_name (lookupGlobalRdrEnv env occ)

	get_qual_mod LocalDef      = moduleName mod
	get_qual_mod (Imported is) = ASSERT( not (null is) ) is_as (is_decl (head is))

    -- we can mention a module P:M without the P: qualifier iff
    -- "import M" would resolve unambiguously to P:M.  (if P is the
    -- current package we can just assume it is unqualified).

  qual_mod mod
     | modulePackageId mod == thisPackage dflags = False

     | [pkgconfig] <- [pkg | (pkg,exposed_module) <- lookup, 
                             exposed pkg && exposed_module],
       packageConfigId pkgconfig == modulePackageId mod
        -- this says: we are given a module P:M, is there just one exposed package
        -- that exposes a module M, and is it package P?
     = False

     | otherwise = True
     where lookup = lookupModuleInAllPackages dflags (moduleName mod)
\end{code}


%************************************************************************
%*									*
		TyThing
%*									*
%************************************************************************

\begin{code}
-- | Determine the 'TyThing's brought into scope by another 'TyThing'
-- /other/ than itself. For example, Id's don't have any implicit TyThings
-- as they just bring themselves into scope, but classes bring their
-- dictionary datatype, type constructor and some selector functions into
-- scope, just for a start!

-- N.B. the set of TyThings returned here *must* match the set of
-- names returned by LoadIface.ifaceDeclSubBndrs, in the sense that
-- TyThing.getOccName should define a bijection between the two lists.
-- This invariant is used in LoadIface.loadDecl (see note [Tricky iface loop])
-- The order of the list does not matter.
implicitTyThings :: TyThing -> [TyThing]

-- For data and newtype declarations:
implicitTyThings (ATyCon tc) = 
    -- fields (names of selectors)
    map AnId (tyConSelIds tc) ++ 
    -- (possibly) implicit coercion and family coercion
    --   depending on whether it's a newtype or a family instance or both
    implicitCoTyCon tc ++
    -- for each data constructor in order,
    --   the contructor, worker, and (possibly) wrapper
    concatMap (extras_plus . ADataCon) (tyConDataCons tc)
		     
implicitTyThings (AClass cl) 
  = -- dictionary datatype:
    --    [extras_plus:]
    --      type constructor 
    --    [recursive call:]
    --      (possibly) newtype coercion; definitely no family coercion here
    --      data constructor
    --      worker
    --      (no wrapper by invariant)
    extras_plus (ATyCon (classTyCon cl)) ++
    -- associated types 
    --    No extras_plus (recursive call) for the classATs, because they
    --    are only the family decls; they have no implicit things
    map ATyCon (classATs cl) ++
    -- superclass and operation selectors
    map AnId (classSelIds cl)

implicitTyThings (ADataCon dc) = 
    -- For data cons add the worker and (possibly) wrapper
    map AnId (dataConImplicitIds dc)

implicitTyThings (AnId _)   = []

-- add a thing and recursive call
extras_plus :: TyThing -> [TyThing]
extras_plus thing = thing : implicitTyThings thing

-- For newtypes and indexed data types (and both),
-- add the implicit coercion tycon
implicitCoTyCon :: TyCon -> [TyThing]
implicitCoTyCon tc 
  = map ATyCon . catMaybes $ [-- Just if newtype, Nothing if not
                              newTyConCo_maybe tc, 
                              -- Just if family instance, Nothing if not
			        tyConFamilyCoercion_maybe tc] 

-- sortByOcc = sortBy (\ x -> \ y -> getOccName x < getOccName y)


-- | Returns @True@ if there should be no interface-file declaration
-- for this thing on its own: either it is built-in, or it is part
-- of some other declaration, or it is generated implicitly by some
-- other declaration.
isImplicitTyThing :: TyThing -> Bool
isImplicitTyThing (ADataCon _)  = True
isImplicitTyThing (AnId     id) = isImplicitId id
isImplicitTyThing (AClass   _)  = False
isImplicitTyThing (ATyCon   tc) = isImplicitTyCon tc

extendTypeEnvWithIds :: TypeEnv -> [Id] -> TypeEnv
extendTypeEnvWithIds env ids
  = extendNameEnvList env [(getName id, AnId id) | id <- ids]
\end{code}

%************************************************************************
%*									*
		TypeEnv
%*									*
%************************************************************************

\begin{code}
-- | A map from 'Name's to 'TyThing's, constructed by typechecking
-- local declarations or interface files
type TypeEnv = NameEnv TyThing

emptyTypeEnv    :: TypeEnv
typeEnvElts     :: TypeEnv -> [TyThing]
typeEnvClasses  :: TypeEnv -> [Class]
typeEnvTyCons   :: TypeEnv -> [TyCon]
typeEnvIds      :: TypeEnv -> [Id]
typeEnvDataCons :: TypeEnv -> [DataCon]
lookupTypeEnv   :: TypeEnv -> Name -> Maybe TyThing

emptyTypeEnv 	    = emptyNameEnv
typeEnvElts     env = nameEnvElts env
typeEnvClasses  env = [cl | AClass cl   <- typeEnvElts env]
typeEnvTyCons   env = [tc | ATyCon tc   <- typeEnvElts env] 
typeEnvIds      env = [id | AnId id     <- typeEnvElts env] 
typeEnvDataCons env = [dc | ADataCon dc <- typeEnvElts env] 

mkTypeEnv :: [TyThing] -> TypeEnv
mkTypeEnv things = extendTypeEnvList emptyTypeEnv things
		
lookupTypeEnv = lookupNameEnv

-- Extend the type environment
extendTypeEnv :: TypeEnv -> TyThing -> TypeEnv
extendTypeEnv env thing = extendNameEnv env (getName thing) thing 

extendTypeEnvList :: TypeEnv -> [TyThing] -> TypeEnv
extendTypeEnvList env things = foldl extendTypeEnv env things
\end{code}

\begin{code}
-- | Find the 'TyThing' for the given 'Name' by using all the resources
-- at our disposal: the compiled modules in the 'HomePackageTable' and the
-- compiled modules in other packages that live in 'PackageTypeEnv'. Note
-- that this does NOT look up the 'TyThing' in the module being compiled: you
-- have to do that yourself, if desired
lookupType :: DynFlags
	   -> HomePackageTable
	   -> PackageTypeEnv
	   -> Name
	   -> Maybe TyThing

lookupType dflags hpt pte name
  -- in one-shot, we don't use the HPT
  | not (isOneShot (ghcMode dflags)) && modulePackageId mod == this_pkg 
  = do hm <- lookupUFM hpt (moduleName mod) -- Maybe monad
       lookupNameEnv (md_types (hm_details hm)) name
  | otherwise
  = lookupNameEnv pte name
  where mod = nameModule name
	this_pkg = thisPackage dflags

-- | As 'lookupType', but with a marginally easier-to-use interface
-- if you have a 'HscEnv'
lookupTypeHscEnv :: HscEnv -> Name -> IO (Maybe TyThing)
lookupTypeHscEnv hsc_env name = do
    eps <- readIORef (hsc_EPS hsc_env)
    return $ lookupType dflags hpt (eps_PTE eps) name
  where 
    dflags = hsc_dflags hsc_env
    hpt = hsc_HPT hsc_env
\end{code}

\begin{code}
-- | Get the 'TyCon' from a 'TyThing' if it is a type constructor thing. Panics otherwise
tyThingTyCon :: TyThing -> TyCon
tyThingTyCon (ATyCon tc) = tc
tyThingTyCon other	 = pprPanic "tyThingTyCon" (pprTyThing other)

-- | Get the 'Class' from a 'TyThing' if it is a class thing. Panics otherwise
tyThingClass :: TyThing -> Class
tyThingClass (AClass cls) = cls
tyThingClass other	  = pprPanic "tyThingClass" (pprTyThing other)

-- | Get the 'DataCon' from a 'TyThing' if it is a data constructor thing. Panics otherwise
tyThingDataCon :: TyThing -> DataCon
tyThingDataCon (ADataCon dc) = dc
tyThingDataCon other	     = pprPanic "tyThingDataCon" (pprTyThing other)

-- | Get the 'Id' from a 'TyThing' if it is a id *or* data constructor thing. Panics otherwise
tyThingId :: TyThing -> Id
tyThingId (AnId id)     = id
tyThingId (ADataCon dc) = dataConWrapId dc
tyThingId other         = pprPanic "tyThingId" (pprTyThing other)
\end{code}

%************************************************************************
%*                                                                      *
\subsection{MonadThings and friends}
%*                                                                      *
%************************************************************************

\begin{code}
-- | Class that abstracts out the common ability of the monads in GHC
-- to lookup a 'TyThing' in the monadic environment by 'Name'. Provides
-- a number of related convenience functions for accessing particular
-- kinds of 'TyThing'
class Monad m => MonadThings m where
        lookupThing :: Name -> m TyThing

        lookupId :: Name -> m Id
        lookupId = liftM tyThingId . lookupThing

        lookupDataCon :: Name -> m DataCon
        lookupDataCon = liftM tyThingDataCon . lookupThing

        lookupTyCon :: Name -> m TyCon
        lookupTyCon = liftM tyThingTyCon . lookupThing

        lookupClass :: Name -> m Class
        lookupClass = liftM tyThingClass . lookupThing
\end{code}

\begin{code}
-- | Constructs cache for the 'mi_hash_fn' field of a 'ModIface'
mkIfaceHashCache :: [(Fingerprint,IfaceDecl)]
                 -> (OccName -> Maybe (OccName, Fingerprint))
mkIfaceHashCache pairs 
  = \occ -> lookupOccEnv env occ
  where
    env = foldr add_decl emptyOccEnv pairs
    add_decl (v,d) env0 = foldr add_imp env1 (ifaceDeclSubBndrs d)
      where
          decl_name = ifName d
          env1 = extendOccEnv env0 decl_name (decl_name, v)
          add_imp bndr env = extendOccEnv env bndr (decl_name, v)

emptyIfaceHashCache :: OccName -> Maybe (OccName, Fingerprint)
emptyIfaceHashCache _occ = Nothing
\end{code}

%************************************************************************
%*									*
\subsection{Auxiliary types}
%*									*
%************************************************************************

These types are defined here because they are mentioned in ModDetails,
but they are mostly elaborated elsewhere

\begin{code}
------------------ Warnings -------------------------
-- | Warning information for a module
data Warnings
  = NoWarnings                          -- ^ Nothing deprecated
  | WarnAll WarningTxt	                -- ^ Whole module deprecated
  | WarnSome [(OccName,WarningTxt)]     -- ^ Some specific things deprecated

     -- Only an OccName is needed because
     --    (1) a deprecation always applies to a binding
     --        defined in the module in which the deprecation appears.
     --    (2) deprecations are only reported outside the defining module.
     --        this is important because, otherwise, if we saw something like
     --
     --        {-# DEPRECATED f "" #-}
     --        f = ...
     --        h = f
     --        g = let f = undefined in f
     --
     --        we'd need more information than an OccName to know to say something
     --        about the use of f in h but not the use of the locally bound f in g
     --
     --        however, because we only report about deprecations from the outside,
     --        and a module can only export one value called f,
     --        an OccName suffices.
     --
     --        this is in contrast with fixity declarations, where we need to map
     --        a Name to its fixity declaration.
  deriving( Eq )

-- | Constructs the cache for the 'mi_warn_fn' field of a 'ModIface'
mkIfaceWarnCache :: Warnings -> Name -> Maybe WarningTxt
mkIfaceWarnCache NoWarnings  = \_ -> Nothing
mkIfaceWarnCache (WarnAll t) = \_ -> Just t
mkIfaceWarnCache (WarnSome pairs) = lookupOccEnv (mkOccEnv pairs) . nameOccName

emptyIfaceWarnCache :: Name -> Maybe WarningTxt
emptyIfaceWarnCache _ = Nothing

plusWarns :: Warnings -> Warnings -> Warnings
plusWarns d NoWarnings = d
plusWarns NoWarnings d = d
plusWarns _ (WarnAll t) = WarnAll t
plusWarns (WarnAll t) _ = WarnAll t
plusWarns (WarnSome v1) (WarnSome v2) = WarnSome (v1 ++ v2)
\end{code}
\begin{code}
-- | A collection of 'AvailInfo' - several things that are \"available\"
type Avails	  = [AvailInfo]
-- | 'Name'd things that are available
type AvailInfo    = GenAvailInfo Name
-- | 'RdrName'd things that are available
type RdrAvailInfo = GenAvailInfo OccName

-- | Records what things are "available", i.e. in scope
data GenAvailInfo name	= Avail name	 -- ^ An ordinary identifier in scope
			| AvailTC name
				  [name] -- ^ A type or class in scope. Parameters:
				         --
				         --  1) The name of the type or class
				         --
				         --  2) The available pieces of type or class.
					 --     NB: If the type or class is itself
					 --     to be in scope, it must be in this list.
					 --     Thus, typically: @AvailTC Eq [Eq, ==, \/=]@
			deriving( Eq )
			-- Equality used when deciding if the interface has changed

-- | The original names declared of a certain module that are exported
type IfaceExport = (Module, [GenAvailInfo OccName])

availsToNameSet :: [AvailInfo] -> NameSet
availsToNameSet avails = foldr add emptyNameSet avails
      where add avail set = addListToNameSet set (availNames avail)

availsToNameEnv :: [AvailInfo] -> NameEnv AvailInfo
availsToNameEnv avails = foldr add emptyNameEnv avails
     where add avail env = extendNameEnvList env
                                (zip (availNames avail) (repeat avail))

-- | Just the main name made available, i.e. not the available pieces
-- of type or class brought into scope by the 'GenAvailInfo'
availName :: GenAvailInfo name -> name
availName (Avail n)     = n
availName (AvailTC n _) = n

-- | All names made available by the availability information
availNames :: GenAvailInfo name -> [name]
availNames (Avail n)      = [n]
availNames (AvailTC _ ns) = ns

instance Outputable n => Outputable (GenAvailInfo n) where
   ppr = pprAvail

pprAvail :: Outputable n => GenAvailInfo n -> SDoc
pprAvail (Avail n)      = ppr n
pprAvail (AvailTC n ns) = ppr n <> braces (hsep (punctuate comma (map ppr ns)))
\end{code}

\begin{code}
-- | Creates cached lookup for the 'mi_fix_fn' field of 'ModIface'
mkIfaceFixCache :: [(OccName, Fixity)] -> OccName -> Fixity
mkIfaceFixCache pairs 
  = \n -> lookupOccEnv env n `orElse` defaultFixity
  where
   env = mkOccEnv pairs

emptyIfaceFixCache :: OccName -> Fixity
emptyIfaceFixCache _ = defaultFixity

-- | Fixity environment mapping names to their fixities
type FixityEnv = NameEnv FixItem

-- | Fixity information for an 'Name'. We keep the OccName in the range 
-- so that we can generate an interface from it
data FixItem = FixItem OccName Fixity

instance Outputable FixItem where
  ppr (FixItem occ fix) = ppr fix <+> ppr occ

emptyFixityEnv :: FixityEnv
emptyFixityEnv = emptyNameEnv

lookupFixity :: FixityEnv -> Name -> Fixity
lookupFixity env n = case lookupNameEnv env n of
			Just (FixItem _ fix) -> fix
			Nothing	      	-> defaultFixity
\end{code}


%************************************************************************
%*									*
\subsection{WhatsImported}
%*									*
%************************************************************************

\begin{code}
-- | Records whether a module has orphans. An \"orphan\" is one of:
--
-- * An instance declaration in a module other than the definition
--   module for one of the type constructors or classes in the instance head
--
-- * A transformation rule in a module other than the one defining
--   the function in the head of the rule
type WhetherHasOrphans   = Bool

-- | Does this module define family instances?
type WhetherHasFamInst = Bool

-- | Did this module originate from a *-boot file?
type IsBootInterface = Bool

-- | Dependency information about modules and packages below this one
-- in the import hierarchy.
--
-- Invariant: the dependencies of a module @M@ never includes @M@.
--
-- Invariant: none of the lists contain duplicates.
data Dependencies
  = Deps { dep_mods   :: [(ModuleName, IsBootInterface)]
                        -- ^ Home-package module dependencies
	 , dep_pkgs   :: [PackageId]
	                -- ^ External package dependencies
	 , dep_orphs  :: [Module]	    
	                -- ^ Orphan modules (whether home or external pkg),
	                -- *not* including family instance orphans as they
	                -- are anyway included in 'dep_finsts'
         , dep_finsts :: [Module]	    
                        -- ^ Modules that contain family instances (whether the
                        -- instances are from the home or an external package)
         }
  deriving( Eq )
	-- Equality used only for old/new comparison in MkIface.addVersionInfo

        -- See 'TcRnTypes.ImportAvails' for details on dependencies.

noDependencies :: Dependencies
noDependencies = Deps [] [] [] []

-- | Records modules that we depend on by making a direct import from
data Usage
  = UsagePackageModule {
        usg_mod      :: Module,
           -- ^ External package module depended on
        usg_mod_hash :: Fingerprint
    }                                           -- ^ Module from another package
  | UsageHomeModule {
        usg_mod_name :: ModuleName,
            -- ^ Name of the module
	usg_mod_hash :: Fingerprint,
	    -- ^ Cached module fingerprint
	usg_entities :: [(OccName,Fingerprint)],
            -- ^ Entities we depend on, sorted by occurrence name and fingerprinted.
            -- NB: usages are for parent names only, e.g. type constructors 
            -- but not the associated data constructors.
	usg_exports  :: Maybe Fingerprint
            -- ^ Fingerprint for the export list we used to depend on this module,
            -- if we depend on the export list
    }                                           -- ^ Module from the current package
    deriving( Eq )
	-- The export list field is (Just v) if we depend on the export list:
	--	i.e. we imported the module directly, whether or not we
	--	     enumerated the things we imported, or just imported 
        --           everything
	-- We need to recompile if M's exports change, because 
	-- if the import was	import M, 	we might now have a name clash
        --                                      in the importing module.
	-- if the import was	import M(x)	M might no longer export x
	-- The only way we don't depend on the export list is if we have
	--			import M()
	-- And of course, for modules that aren't imported directly we don't
	-- depend on their export lists
\end{code}


%************************************************************************
%*									*
		The External Package State
%*									*
%************************************************************************

\begin{code}
type PackageTypeEnv    = TypeEnv
type PackageRuleBase   = RuleBase
type PackageInstEnv    = InstEnv
type PackageFamInstEnv = FamInstEnv
type PackageVectInfo   = VectInfo

-- | Information about other packages that we have slurped in by reading
-- their interface files
data ExternalPackageState
  = EPS {
	eps_is_boot :: !(ModuleNameEnv (ModuleName, IsBootInterface)),
		-- ^ In OneShot mode (only), home-package modules
		-- accumulate in the external package state, and are
		-- sucked in lazily.  For these home-pkg modules
		-- (only) we need to record which are boot modules.
		-- We set this field after loading all the
		-- explicitly-imported interfaces, but before doing
		-- anything else
		--
		-- The 'ModuleName' part is not necessary, but it's useful for
		-- debug prints, and it's convenient because this field comes
		-- direct from 'TcRnTypes.imp_dep_mods'

	eps_PIT :: !PackageIfaceTable,
		-- ^ The 'ModIface's for modules in external packages
		-- whose interfaces we have opened.
		-- The declarations in these interface files are held in the
		-- 'eps_decls', 'eps_inst_env', 'eps_fam_inst_env' and 'eps_rules'
		-- fields of this record, not in the 'mi_decls' fields of the 
		-- interface we have sucked in.
		--
		-- What /is/ in the PIT is:
		--
		-- * The Module
		--
		-- * Fingerprint info
		--
		-- * Its exports
		--
		-- * Fixities
		--
		-- * Deprecations and warnings

	eps_PTE :: !PackageTypeEnv,	   
	        -- ^ Result of typechecking all the external package
	        -- interface files we have sucked in. The domain of
	        -- the mapping is external-package modules
	        
	eps_inst_env     :: !PackageInstEnv,   -- ^ The total 'InstEnv' accumulated
					       -- from all the external-package modules
	eps_fam_inst_env :: !PackageFamInstEnv,-- ^ The total 'FamInstEnv' accumulated
					       -- from all the external-package modules
	eps_rule_base    :: !PackageRuleBase,  -- ^ The total 'RuleEnv' accumulated
					       -- from all the external-package modules
	eps_vect_info    :: !PackageVectInfo,  -- ^ The total 'VectInfo' accumulated
					       -- from all the external-package modules

        eps_mod_fam_inst_env :: !(ModuleEnv FamInstEnv), -- ^ The family instances accumulated from external
                                                         -- packages, keyed off the module that declared them

	eps_stats :: !EpsStats                 -- ^ Stastics about what was loaded from external packages
  }

-- | Accumulated statistics about what we are putting into the 'ExternalPackageState'.
-- \"In\" means stuff that is just /read/ from interface files,
-- \"Out\" means actually sucked in and type-checked
data EpsStats = EpsStats { n_ifaces_in
			 , n_decls_in, n_decls_out 
			 , n_rules_in, n_rules_out
			 , n_insts_in, n_insts_out :: !Int }

addEpsInStats :: EpsStats -> Int -> Int -> Int -> EpsStats
-- ^ Add stats for one newly-read interface
addEpsInStats stats n_decls n_insts n_rules
  = stats { n_ifaces_in = n_ifaces_in stats + 1
	  , n_decls_in  = n_decls_in stats + n_decls
	  , n_insts_in  = n_insts_in stats + n_insts
	  , n_rules_in  = n_rules_in stats + n_rules }
\end{code}

Names in a NameCache are always stored as a Global, and have the SrcLoc 
of their binding locations.

Actually that's not quite right.  When we first encounter the original
name, we might not be at its binding site (e.g. we are reading an
interface file); so we give it 'noSrcLoc' then.  Later, when we find
its binding site, we fix it up.

\begin{code}
-- | The NameCache makes sure that there is just one Unique assigned for
-- each original name; i.e. (module-name, occ-name) pair and provides
-- something of a lookup mechanism for those names.
data NameCache
 = NameCache {  nsUniqs :: UniqSupply,
		-- ^ Supply of uniques
		nsNames :: OrigNameCache,
		-- ^ Ensures that one original name gets one unique
		nsIPs   :: OrigIParamCache
		-- ^ Ensures that one implicit parameter name gets one unique
   }

-- | Per-module cache of original 'OccName's given 'Name's
type OrigNameCache   = ModuleEnv (OccEnv Name)

-- | Module-local cache of implicit parameter 'OccName's given 'Name's
type OrigIParamCache = FiniteMap (IPName OccName) (IPName Name)
\end{code}



%************************************************************************
%*									*
		The module graph and ModSummary type
	A ModSummary is a node in the compilation manager's
	dependency graph, and it's also passed to hscMain
%*									*
%************************************************************************

\begin{code}
-- | A ModuleGraph contains all the nodes from the home package (only).
-- There will be a node for each source module, plus a node for each hi-boot
-- module.
--
-- The graph is not necessarily stored in topologically-sorted order.
type ModuleGraph = [ModSummary]

emptyMG :: ModuleGraph
emptyMG = []

-- | A single node in a 'ModuleGraph. The nodes of the module graph are one of:
--
-- * A regular Haskell source module
--
-- * A hi-boot source module
--
-- * An external-core source module
data ModSummary
   = ModSummary {
        ms_mod       :: Module,			-- ^ Identity of the module
	ms_hsc_src   :: HscSource,		-- ^ The module source either plain Haskell, hs-boot or external core
        ms_location  :: ModLocation,		-- ^ Location of the various files belonging to the module
        ms_hs_date   :: ClockTime,		-- ^ Timestamp of source file
	ms_obj_date  :: Maybe ClockTime,	-- ^ Timestamp of object, if we have one
        ms_srcimps   :: [Located ModuleName],	-- ^ Source imports of the module
        ms_imps      :: [Located ModuleName],	-- ^ Non-source imports of the module
        ms_hspp_file :: FilePath,		-- ^ Filename of preprocessed source file
        ms_hspp_opts :: DynFlags,               -- ^ Cached flags from @OPTIONS@, @INCLUDE@
                                                -- and @LANGUAGE@ pragmas in the modules source code
	ms_hspp_buf  :: Maybe StringBuffer    	-- ^ The actual preprocessed source, if we have it
     }

ms_mod_name :: ModSummary -> ModuleName
ms_mod_name = moduleName . ms_mod

-- The ModLocation contains both the original source filename and the
-- filename of the cleaned-up source file after all preprocessing has been
-- done.  The point is that the summariser will have to cpp/unlit/whatever
-- all files anyway, and there's no point in doing this twice -- just 
-- park the result in a temp file, put the name of it in the location,
-- and let @compile@ read from that file on the way back up.

-- The ModLocation is stable over successive up-sweeps in GHCi, wheres
-- the ms_hs_date and imports can, of course, change

msHsFilePath, msHiFilePath, msObjFilePath :: ModSummary -> FilePath
msHsFilePath  ms = expectJust "msHsFilePath" (ml_hs_file  (ms_location ms))
msHiFilePath  ms = ml_hi_file  (ms_location ms)
msObjFilePath ms = ml_obj_file (ms_location ms)

-- | Did this 'ModSummary' originate from a hs-boot file?
isBootSummary :: ModSummary -> Bool
isBootSummary ms = isHsBoot (ms_hsc_src ms)

instance Outputable ModSummary where
   ppr ms
      = sep [text "ModSummary {",
             nest 3 (sep [text "ms_hs_date = " <> text (show (ms_hs_date ms)),
                          text "ms_mod =" <+> ppr (ms_mod ms) 
				<> text (hscSourceString (ms_hsc_src ms)) <> comma,
                          text "ms_imps =" <+> ppr (ms_imps ms),
                          text "ms_srcimps =" <+> ppr (ms_srcimps ms)]),
             char '}'
            ]

showModMsg :: HscTarget -> Bool -> ModSummary -> String
showModMsg target recomp mod_summary
  = showSDoc $
        hsep [text (mod_str ++ replicate (max 0 (16 - length mod_str)) ' '),
              char '(', text (normalise $ msHsFilePath mod_summary) <> comma,
              case target of
                  HscInterpreted | recomp 
                             -> text "interpreted"
                  HscNothing -> text "nothing"
                  _          -> text (normalise $ msObjFilePath mod_summary),
              char ')']
 where 
    mod     = moduleName (ms_mod mod_summary)
    mod_str = showSDoc (ppr mod) ++ hscSourceString (ms_hsc_src mod_summary)
\end{code}


%************************************************************************
%*									*
\subsection{Hpc Support}
%*									*
%************************************************************************

\begin{code}
-- | Information about a modules use of Haskell Program Coverage
data HpcInfo
  = HpcInfo 
     { hpcInfoTickCount :: Int
     , hpcInfoHash      :: Int
     }
  | NoHpcInfo 
     { hpcUsed          :: AnyHpcUsage  -- ^ Is hpc used anywhere on the module \*tree\*?
     }

-- | This is used to signal if one of my imports used HPC instrumentation
-- even if there is no module-local HPC usage
type AnyHpcUsage = Bool

emptyHpcInfo :: AnyHpcUsage -> HpcInfo
emptyHpcInfo = NoHpcInfo 

-- | Find out if HPC is used by this module or any of the modules
-- it depends upon
isHpcUsed :: HpcInfo -> AnyHpcUsage
isHpcUsed (HpcInfo {})     		 = True
isHpcUsed (NoHpcInfo { hpcUsed = used }) = used
\end{code}

%************************************************************************
%*									*
\subsection{Vectorisation Support}
%*									*
%************************************************************************

The following information is generated and consumed by the vectorisation
subsystem.  It communicates the vectorisation status of declarations from one
module to another.

Why do we need both f and f_v in the ModGuts/ModDetails/EPS version VectInfo
below?  We need to know `f' when converting to IfaceVectInfo.  However, during
vectorisation, we need to know `f_v', whose `Var' we cannot lookup based
on just the OccName easily in a Core pass.

\begin{code}
-- | Vectorisation information for 'ModGuts', 'ModDetails' and 'ExternalPackageState'.
-- All of this information is always tidy, even in ModGuts.
data VectInfo      
  = VectInfo {
      vectInfoVar     :: VarEnv  (Var    , Var  ),   -- ^ @(f, f_v)@ keyed on @f@
      vectInfoTyCon   :: NameEnv (TyCon  , TyCon),   -- ^ @(T, T_v)@ keyed on @T@
      vectInfoDataCon :: NameEnv (DataCon, DataCon), -- ^ @(C, C_v)@ keyed on @C@
      vectInfoPADFun  :: NameEnv (TyCon  , Var),     -- ^ @(T_v, paT)@ keyed on @T_v@
      vectInfoIso     :: NameEnv (TyCon  , Var)      -- ^ @(T, isoT)@ keyed on @T@
    }

-- | Vectorisation information for 'ModIface': a slightly less low-level view
data IfaceVectInfo 
  = IfaceVectInfo {
      ifaceVectInfoVar        :: [Name],
        -- ^ All variables in here have a vectorised variant
      ifaceVectInfoTyCon      :: [Name],
        -- ^ All 'TyCon's in here have a vectorised variant;
        -- the name of the vectorised variant and those of its
        -- data constructors are determined by 'OccName.mkVectTyConOcc'
        -- and 'OccName.mkVectDataConOcc'; the names of
        -- the isomorphisms are determined by 'OccName.mkVectIsoOcc'
      ifaceVectInfoTyConReuse :: [Name]              
        -- ^ The vectorised form of all the 'TyCon's in here coincides with
        -- the unconverted form; the name of the isomorphisms is determined
        -- by 'OccName.mkVectIsoOcc'
    }

noVectInfo :: VectInfo
noVectInfo = VectInfo emptyVarEnv emptyNameEnv emptyNameEnv emptyNameEnv emptyNameEnv

plusVectInfo :: VectInfo -> VectInfo -> VectInfo
plusVectInfo vi1 vi2 = 
  VectInfo (vectInfoVar     vi1 `plusVarEnv`  vectInfoVar     vi2)
           (vectInfoTyCon   vi1 `plusNameEnv` vectInfoTyCon   vi2)
           (vectInfoDataCon vi1 `plusNameEnv` vectInfoDataCon vi2)
           (vectInfoPADFun  vi1 `plusNameEnv` vectInfoPADFun  vi2)
           (vectInfoIso     vi1 `plusNameEnv` vectInfoIso     vi2)

concatVectInfo :: [VectInfo] -> VectInfo
concatVectInfo = foldr plusVectInfo noVectInfo

noIfaceVectInfo :: IfaceVectInfo
noIfaceVectInfo = IfaceVectInfo [] [] []
\end{code}

%************************************************************************
%*									*
\subsection{Linkable stuff}
%*									*
%************************************************************************

This stuff is in here, rather than (say) in Linker.lhs, because the Linker.lhs
stuff is the *dynamic* linker, and isn't present in a stage-1 compiler

\begin{code}
-- | Information we can use to dynamically link modules into the compiler
data Linkable = LM {
  linkableTime     :: ClockTime,	-- ^ Time at which this linkable was built
					-- (i.e. when the bytecodes were produced,
					--	 or the mod date on the files)
  linkableModule   :: Module,           -- ^ The linkable module itself
  linkableUnlinked :: [Unlinked]        -- ^ Those files and chunks of code we have
                                        -- yet to link
 }

isObjectLinkable :: Linkable -> Bool
isObjectLinkable l = not (null unlinked) && all isObject unlinked
  where unlinked = linkableUnlinked l
	-- A linkable with no Unlinked's is treated as a BCO.  We can
	-- generate a linkable with no Unlinked's as a result of
	-- compiling a module in HscNothing mode, and this choice
	-- happens to work well with checkStability in module GHC.

instance Outputable Linkable where
   ppr (LM when_made mod unlinkeds)
      = (text "LinkableM" <+> parens (text (show when_made)) <+> ppr mod)
        $$ nest 3 (ppr unlinkeds)

-------------------------------------------

-- | Objects which have yet to be linked by the compiler
data Unlinked
   = DotO FilePath      -- ^ An object file (.o)
   | DotA FilePath      -- ^ Static archive file (.a)
   | DotDLL FilePath    -- ^ Dynamically linked library file (.so, .dll, .dylib)
   | BCOs CompiledByteCode ModBreaks    -- ^ A byte-code object, lives only in memory

#ifndef GHCI
data CompiledByteCode = CompiledByteCodeUndefined
_unused :: CompiledByteCode
_unused = CompiledByteCodeUndefined
#endif

instance Outputable Unlinked where
   ppr (DotO path)   = text "DotO" <+> text path
   ppr (DotA path)   = text "DotA" <+> text path
   ppr (DotDLL path) = text "DotDLL" <+> text path
#ifdef GHCI
   ppr (BCOs bcos _) = text "BCOs" <+> ppr bcos
#else
   ppr (BCOs _ _)    = text "No byte code"
#endif

-- | Is this an actual file on disk we can link in somehow?
isObject :: Unlinked -> Bool
isObject (DotO _)   = True
isObject (DotA _)   = True
isObject (DotDLL _) = True
isObject _          = False

-- | Is this a bytecode linkable with no file on disk?
isInterpretable :: Unlinked -> Bool
isInterpretable = not . isObject

-- | Retrieve the filename of the linkable if possible. Panic if it is a byte-code object
nameOfObject :: Unlinked -> FilePath
nameOfObject (DotO fn)   = fn
nameOfObject (DotA fn)   = fn
nameOfObject (DotDLL fn) = fn
nameOfObject other       = pprPanic "nameOfObject" (ppr other)

-- | Retrieve the compiled byte-code if possible. Panic if it is a file-based linkable
byteCodeOfObject :: Unlinked -> CompiledByteCode
byteCodeOfObject (BCOs bc _) = bc
byteCodeOfObject other       = pprPanic "byteCodeOfObject" (ppr other)
\end{code}

%************************************************************************
%*                                                                      *
\subsection{Breakpoint Support}
%*                                                                      *
%************************************************************************

\begin{code}
-- | Breakpoint index
type BreakIndex = Int

-- | All the information about the breakpoints for a given module
data ModBreaks
   = ModBreaks
   { modBreaks_flags :: BreakArray
        -- ^ The array of flags, one per breakpoint, 
        -- indicating which breakpoints are enabled.
   , modBreaks_locs :: !(Array BreakIndex SrcSpan)
        -- ^ An array giving the source span of each breakpoint.
   , modBreaks_vars :: !(Array BreakIndex [OccName])
        -- ^ An array giving the names of the free variables at each breakpoint.
   }

emptyModBreaks :: ModBreaks
emptyModBreaks = ModBreaks
   { modBreaks_flags = error "ModBreaks.modBreaks_array not initialised"
         -- Todo: can we avoid this? 
   , modBreaks_locs = array (0,-1) []
   , modBreaks_vars = array (0,-1) []
   }
\end{code}
