{-# LANGUAGE TypeFamilies #-}

module Simple2a where

class C a where
  data Sd a :: *
  data Sn a :: *
  type St a :: *

instance C Int where
  data    Sd a :: *   -- must fail: parse error
  data    Sd Int = SdC Char
  newtype Sn Int = SnC Char
  type    St Int = Char
