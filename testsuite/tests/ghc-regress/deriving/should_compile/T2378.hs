{-# LANGUAGE StandaloneDeriving, DeriveDataTypeable #-}
module Foo( T ) where

-- Trac 2378

import Data.Generics

newtype T f = MkT Int

deriving instance Typeable1 T
