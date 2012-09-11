
-- | Builtin types and functions used by the vectoriser.
--   The source program uses functions from Data.Array.Parallel, which the vectoriser rewrites
--   to use equivalent vectorised versions in the DPH backend packages.
--
--   The `Builtins` structure holds the name of all the things in the DPH packages
--   we will need. We can get specific things using the selectors, which print a
--   civilized panic message if the specified thing cannot be found.
--
module Vectorise.Builtins (
  -- * Builtins
  Builtins(..),
  indexBuiltin,
  
  -- * Wrapped selectors
  selTy,
  selReplicate,
  selPick,
  selTags,
  selElements,
  sumTyCon,
  prodTyCon,
  prodDataCon,
  combinePDVar,
  scalarZip,
  closureCtrFun,

  -- * Initialisation
  initBuiltins, initBuiltinVars, initBuiltinTyCons, initBuiltinDataCons,
  initBuiltinPAs, initBuiltinPRs,
  initBuiltinBoxedTyCons,
  
  -- * Lookup
  primMethod,
  primPArray
) where
  
import Vectorise.Builtins.Base
import Vectorise.Builtins.Modules
import Vectorise.Builtins.Initialise

import TysPrim
import IfaceEnv
import TyCon
import DsMonad
import NameEnv
import Name
import Var
import Control.Monad


-- |Lookup a method function given its name and instance type.
--
primMethod :: TyCon -> String -> Builtins -> DsM (Maybe Var)
primMethod  tycon method (Builtins { dphModules = mods })
  | Just suffix <- lookupNameEnv prim_ty_cons (tyConName tycon)
  = liftM Just
  $ dsLookupGlobalId =<< lookupOrig (dph_Unboxed mods)
                                    (mkVarOcc $ method ++ suffix)

  | otherwise = return Nothing

-- |Lookup the representation type we use for PArrays that contain a given element type.
--
primPArray :: TyCon -> Builtins -> DsM (Maybe TyCon)
primPArray tycon (Builtins { dphModules = mods })
  | Just suffix <- lookupNameEnv prim_ty_cons (tyConName tycon)
  = liftM Just
  $ dsLookupTyCon =<< lookupOrig (dph_Unboxed mods)
                                 (mkTcOcc $ "PArray" ++ suffix)

  | otherwise = return Nothing

prim_ty_cons :: NameEnv String
prim_ty_cons = mkNameEnv [mk_prim intPrimTyCon]
  where
    mk_prim tycon = (tyConName tycon, '_' : getOccString tycon)

