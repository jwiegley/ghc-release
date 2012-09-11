{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import GHC
import MonadUtils  ( liftIO )
import DynFlags    ( defaultDynFlags )
import Annotations ( AnnTarget(..), CoreAnnTarget )
import Serialized  ( deserializeWithData )

import Config
import Annrun01_Help

import qualified Language.Haskell.TH as TH
import Data.List
import Data.Function

main = defaultErrorHandler defaultDynFlags $ runGhc (Just cTop) $ do
    liftIO $ putStrLn "Initializing Package Database"
    dflags <- getSessionDynFlags
    let dflags' = dflags
    setSessionDynFlags dflags'
    
    let mod_nm = mkModuleName "Annrun01_Help"
    
    liftIO $ putStrLn "Setting Target"
    setTargets [Target (TargetModule mod_nm) True Nothing]
    liftIO $ putStrLn "Loading Targets"
    load LoadAllTargets
    
    liftIO $ putStrLn "Finding Module"
    mod <- findModule mod_nm Nothing
    liftIO $ putStrLn "Getting Module Info"
    Just mod_info <- getModuleInfo mod
    
    liftIO $ putStrLn "Showing Details For Module"
    showTargetAnns (ModuleTarget mod)
    liftIO $ putStrLn "Showing Details For Exports"
    mapM (showTargetAnns . NamedTarget) $ sortBy (compare `on` getOccName) $ modInfoExports mod_info

showTargetAnns :: CoreAnnTarget -> Ghc ()
showTargetAnns target = do
    (int_anns     :: [Int])        <- findGlobalAnns deserializeWithData target
    (mb_bool_anns :: [Maybe Bool]) <- findGlobalAnns deserializeWithData target
    (string_anns  :: [String])     <- findGlobalAnns deserializeWithData target
    (name_anns    :: [TH.Name])    <- findGlobalAnns deserializeWithData target
    liftIO $ print (int_anns, mb_bool_anns, string_anns, name_anns)
