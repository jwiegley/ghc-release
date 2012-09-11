{-# LANGUAGE TemplateHaskell, FlexibleInstances,
          MultiParamTypeClasses, TypeSynonymInstances #-}
module Main where

import Language.Haskell.TH
import Language.Haskell.TH.Syntax

class Eq a => MyClass a 
data Foo = Foo deriving Eq

instance MyClass Foo 

data Bar = Bar
  deriving Eq

type Baz = Bar
instance MyClass Baz

data Quux a  = Quux a   deriving Eq
data Quux2 a = Quux2 a  deriving Eq
instance Eq a  => MyClass (Quux a)
instance Num a => MyClass (Quux2 a)

class MyClass2 a b
instance MyClass2 Int Bool

main = do
    putStrLn $(do { info <- reify ''MyClass; lift (pprint info) })
    print $(isClassInstance ''Eq [ConT ''Foo] >>= lift)
    print $(isClassInstance ''MyClass [ConT ''Foo] >>= lift)
    print $ not $(isClassInstance ''Show [ConT ''Foo] >>= lift)
    print $(isClassInstance ''MyClass [ConT ''Bar] >>= lift) -- this one
    print $(isClassInstance ''MyClass [ConT ''Baz] >>= lift)
    print $(isClassInstance ''MyClass [AppT (ConT ''Quux) (ConT ''Int)] >>= lift) --this one
    print $(isClassInstance ''MyClass [AppT (ConT ''Quux2) (ConT ''Int)] >>= lift) -- this one
    print $(isClassInstance ''MyClass2 [ConT ''Int, ConT ''Bool] >>= lift)
    print $(isClassInstance ''MyClass2 [ConT ''Bool, ConT ''Bool] >>= lift)
