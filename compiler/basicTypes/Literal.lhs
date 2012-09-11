%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1998
%
\section[Literal]{@Literal@: Machine literals (unboxed, of course)}

\begin{code}
{-# OPTIONS -fno-warn-incomplete-patterns #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

module Literal
	( 
	-- * Main data type
	  Literal(..)		-- Exported to ParseIface
	
	-- ** Creating Literals
	, mkMachInt, mkMachWord
	, mkMachInt64, mkMachWord64
	, mkMachFloat, mkMachDouble
	, mkMachChar, mkMachString
	
	-- ** Operations on Literals
	, literalType
	, hashLiteral

        -- ** Predicates on Literals and their contents
	, litIsDupable, litIsTrivial
	, inIntRange, inWordRange, tARGET_MAX_INT, inCharRange
	, isZeroLit
	, litFitsInChar

        -- ** Coercions
	, word2IntLit, int2WordLit
	, narrow8IntLit, narrow16IntLit, narrow32IntLit
	, narrow8WordLit, narrow16WordLit, narrow32WordLit
	, char2IntLit, int2CharLit
	, float2IntLit, int2FloatLit, double2IntLit, int2DoubleLit
	, nullAddrLit, float2DoubleLit, double2FloatLit
	) where

import TysPrim
import Type
import Outputable
import FastTypes
import FastString
import BasicTypes
import Binary
import Constants

import Data.Int
import Data.Ratio
import Data.Word
import Data.Char
\end{code}


%************************************************************************
%*									*
\subsection{Literals}
%*									*
%************************************************************************

\begin{code}
-- | So-called 'Literal's are one of:
--
-- * An unboxed (/machine/) literal ('MachInt', 'MachFloat', etc.),
--   which is presumed to be surrounded by appropriate constructors
--   (@Int#@, etc.), so that the overall thing makes sense.
--
-- * The literal derived from the label mentioned in a \"foreign label\" 
--   declaration ('MachLabel')
data Literal
  =	------------------
	-- First the primitive guys
    MachChar	Char            -- ^ @Char#@ - at least 31 bits. Create with 'mkMachChar'

  | MachStr	FastString	-- ^ A string-literal: stored and emitted
				-- UTF-8 encoded, we'll arrange to decode it
				-- at runtime.  Also emitted with a @'\0'@
				-- terminator. Create with 'mkMachString'

  | MachNullAddr                -- ^ The @NULL@ pointer, the only pointer value
                                -- that can be represented as a Literal. Create 
                                -- with 'nullAddrLit'

  | MachInt	Integer		-- ^ @Int#@ - at least @WORD_SIZE_IN_BITS@ bits. Create with 'mkMachInt'
  | MachInt64	Integer		-- ^ @Int64#@ - at least 64 bits. Create with 'mkMachInt64'
  | MachWord	Integer		-- ^ @Word#@ - at least @WORD_SIZE_IN_BITS@ bits. Create with 'mkMachWord'
  | MachWord64	Integer		-- ^ @Word64#@ - at least 64 bits. Create with 'mkMachWord64'

  | MachFloat	Rational        -- ^ @Float#@. Create with 'mkMachFloat'
  | MachDouble	Rational        -- ^ @Double#@. Create with 'mkMachDouble'

  | MachLabel   FastString
  		(Maybe Int)
        FunctionOrData
                -- ^ A label literal. Parameters:
  		        --
  		        -- 1) The name of the symbol mentioned in the declaration
  		        --
  		        -- 2) The size (in bytes) of the arguments
				--    the label expects. Only applicable with
				--    @stdcall@ labels. @Just x@ => @\<x\>@ will
				--    be appended to label name when emitting assembly.
\end{code}

Binary instance

\begin{code}
instance Binary Literal where
    put_ bh (MachChar aa)     = do putByte bh 0; put_ bh aa
    put_ bh (MachStr ab)      = do putByte bh 1; put_ bh ab
    put_ bh (MachNullAddr)    = do putByte bh 2
    put_ bh (MachInt ad)      = do putByte bh 3; put_ bh ad
    put_ bh (MachInt64 ae)    = do putByte bh 4; put_ bh ae
    put_ bh (MachWord af)     = do putByte bh 5; put_ bh af
    put_ bh (MachWord64 ag)   = do putByte bh 6; put_ bh ag
    put_ bh (MachFloat ah)    = do putByte bh 7; put_ bh ah
    put_ bh (MachDouble ai)   = do putByte bh 8; put_ bh ai
    put_ bh (MachLabel aj mb fod)
        = do putByte bh 9
             put_ bh aj
             put_ bh mb
             put_ bh fod
    get bh = do
	    h <- getByte bh
	    case h of
	      0 -> do
		    aa <- get bh
		    return (MachChar aa)
	      1 -> do
		    ab <- get bh
		    return (MachStr ab)
	      2 -> do
		    return (MachNullAddr)
	      3 -> do
		    ad <- get bh
		    return (MachInt ad)
	      4 -> do
		    ae <- get bh
		    return (MachInt64 ae)
	      5 -> do
		    af <- get bh
		    return (MachWord af)
	      6 -> do
		    ag <- get bh
		    return (MachWord64 ag)
	      7 -> do
		    ah <- get bh
		    return (MachFloat ah)
	      8 -> do
		    ai <- get bh
		    return (MachDouble ai)
	      9 -> do
		    aj <- get bh
		    mb <- get bh
		    fod <- get bh
		    return (MachLabel aj mb fod)
\end{code}

\begin{code}
instance Outputable Literal where
    ppr lit = pprLit lit

instance Show Literal where
    showsPrec p lit = showsPrecSDoc p (ppr lit)

instance Eq Literal where
    a == b = case (a `compare` b) of { EQ -> True;   _ -> False }
    a /= b = case (a `compare` b) of { EQ -> False;  _ -> True  }

instance Ord Literal where
    a <= b = case (a `compare` b) of { LT -> True;  EQ -> True;  GT -> False }
    a <	 b = case (a `compare` b) of { LT -> True;  EQ -> False; GT -> False }
    a >= b = case (a `compare` b) of { LT -> False; EQ -> True;  GT -> True  }
    a >	 b = case (a `compare` b) of { LT -> False; EQ -> False; GT -> True  }
    compare a b = cmpLit a b
\end{code}


	Construction
	~~~~~~~~~~~~
\begin{code}
-- | Creates a 'Literal' of type @Int#@
mkMachInt :: Integer -> Literal
mkMachInt  x   = -- ASSERT2( inIntRange x,  integer x ) 
	 	 -- Not true: you can write out of range Int# literals
		 -- For example, one can write (intToWord# 0xffff0000) to
		 -- get a particular Word bit-pattern, and there's no other
		 -- convenient way to write such literals, which is why we allow it.
		 MachInt x

-- | Creates a 'Literal' of type @Word#@
mkMachWord :: Integer -> Literal
mkMachWord x   = -- ASSERT2( inWordRange x, integer x ) 
		 MachWord x

-- | Creates a 'Literal' of type @Int64#@
mkMachInt64 :: Integer -> Literal
mkMachInt64  x = MachInt64 x

-- | Creates a 'Literal' of type @Word64#@
mkMachWord64 :: Integer -> Literal
mkMachWord64 x = MachWord64 x

-- | Creates a 'Literal' of type @Float#@
mkMachFloat :: Rational -> Literal
mkMachFloat = MachFloat

-- | Creates a 'Literal' of type @Double#@
mkMachDouble :: Rational -> Literal
mkMachDouble = MachDouble

-- | Creates a 'Literal' of type @Char#@
mkMachChar :: Char -> Literal
mkMachChar = MachChar

-- | Creates a 'Literal' of type @Addr#@, which is appropriate for passing to
-- e.g. some of the \"error\" functions in GHC.Err such as @GHC.Err.runtimeError@
mkMachString :: String -> Literal
mkMachString s = MachStr (mkFastString s) -- stored UTF-8 encoded

inIntRange, inWordRange :: Integer -> Bool
inIntRange  x = x >= tARGET_MIN_INT && x <= tARGET_MAX_INT
inWordRange x = x >= 0		    && x <= tARGET_MAX_WORD

inCharRange :: Char -> Bool
inCharRange c =  c >= '\0' && c <= chr tARGET_MAX_CHAR

-- | Tests whether the literal represents a zero of whatever type it is
isZeroLit :: Literal -> Bool
isZeroLit (MachInt    0) = True
isZeroLit (MachInt64  0) = True
isZeroLit (MachWord   0) = True
isZeroLit (MachWord64 0) = True
isZeroLit (MachFloat  0) = True
isZeroLit (MachDouble 0) = True
isZeroLit _              = False
\end{code}

	Coercions
	~~~~~~~~~
\begin{code}
word2IntLit, int2WordLit,
  narrow8IntLit, narrow16IntLit, narrow32IntLit,
  narrow8WordLit, narrow16WordLit, narrow32WordLit,
  char2IntLit, int2CharLit,
  float2IntLit, int2FloatLit, double2IntLit, int2DoubleLit,
  float2DoubleLit, double2FloatLit
  :: Literal -> Literal

word2IntLit (MachWord w) 
  | w > tARGET_MAX_INT = MachInt (w - tARGET_MAX_WORD - 1)
  | otherwise	       = MachInt w

int2WordLit (MachInt i)
  | i < 0     = MachWord (1 + tARGET_MAX_WORD + i)	-- (-1)  --->  tARGET_MAX_WORD
  | otherwise = MachWord i

narrow8IntLit    (MachInt  i) = MachInt  (toInteger (fromInteger i :: Int8))
narrow16IntLit   (MachInt  i) = MachInt  (toInteger (fromInteger i :: Int16))
narrow32IntLit   (MachInt  i) = MachInt  (toInteger (fromInteger i :: Int32))
narrow8WordLit   (MachWord w) = MachWord (toInteger (fromInteger w :: Word8))
narrow16WordLit  (MachWord w) = MachWord (toInteger (fromInteger w :: Word16))
narrow32WordLit  (MachWord w) = MachWord (toInteger (fromInteger w :: Word32))

char2IntLit (MachChar c) = MachInt  (toInteger (ord c))
int2CharLit (MachInt  i) = MachChar (chr (fromInteger i))

float2IntLit (MachFloat f) = MachInt   (truncate    f)
int2FloatLit (MachInt   i) = MachFloat (fromInteger i)

double2IntLit (MachDouble f) = MachInt    (truncate    f)
int2DoubleLit (MachInt   i) = MachDouble (fromInteger i)

float2DoubleLit (MachFloat  f) = MachDouble f
double2FloatLit (MachDouble d) = MachFloat  d

nullAddrLit :: Literal
nullAddrLit = MachNullAddr
\end{code}

	Predicates
	~~~~~~~~~~
\begin{code}
-- | True if there is absolutely no penalty to duplicating the literal.
-- False principally of strings
litIsTrivial :: Literal -> Bool
--	c.f. CoreUtils.exprIsTrivial
litIsTrivial (MachStr _) = False
litIsTrivial _           = True

-- | True if code space does not go bad if we duplicate this literal
-- Currently we treat it just like 'litIsTrivial'
litIsDupable :: Literal -> Bool
--	c.f. CoreUtils.exprIsDupable
litIsDupable (MachStr _) = False
litIsDupable _           = True

litFitsInChar :: Literal -> Bool
litFitsInChar (MachInt i)
    		         = fromInteger i <= ord minBound 
                        && fromInteger i >= ord maxBound 
litFitsInChar _         = False
\end{code}

	Types
	~~~~~
\begin{code}
-- | Find the Haskell 'Type' the literal occupies
literalType :: Literal -> Type
literalType MachNullAddr    = addrPrimTy
literalType (MachChar _)    = charPrimTy
literalType (MachStr  _)    = addrPrimTy
literalType (MachInt  _)    = intPrimTy
literalType (MachWord  _)   = wordPrimTy
literalType (MachInt64  _)  = int64PrimTy
literalType (MachWord64  _) = word64PrimTy
literalType (MachFloat _)   = floatPrimTy
literalType (MachDouble _)  = doublePrimTy
literalType (MachLabel _ _ _) = addrPrimTy
\end{code}


	Comparison
	~~~~~~~~~~
\begin{code}
cmpLit :: Literal -> Literal -> Ordering
cmpLit (MachChar      a)   (MachChar	   b)   = a `compare` b
cmpLit (MachStr       a)   (MachStr	   b)   = a `compare` b
cmpLit (MachNullAddr)      (MachNullAddr)       = EQ
cmpLit (MachInt       a)   (MachInt	   b)   = a `compare` b
cmpLit (MachWord      a)   (MachWord	   b)   = a `compare` b
cmpLit (MachInt64     a)   (MachInt64	   b)   = a `compare` b
cmpLit (MachWord64    a)   (MachWord64	   b)   = a `compare` b
cmpLit (MachFloat     a)   (MachFloat	   b)   = a `compare` b
cmpLit (MachDouble    a)   (MachDouble	   b)   = a `compare` b
cmpLit (MachLabel     a _ _) (MachLabel      b _ _) = a `compare` b
cmpLit lit1		   lit2		        | litTag lit1 <# litTag lit2 = LT
					        | otherwise  		     = GT

litTag :: Literal -> FastInt
litTag (MachChar      _)   = _ILIT(1)
litTag (MachStr       _)   = _ILIT(2)
litTag (MachNullAddr)      = _ILIT(3)
litTag (MachInt       _)   = _ILIT(4)
litTag (MachWord      _)   = _ILIT(5)
litTag (MachInt64     _)   = _ILIT(6)
litTag (MachWord64    _)   = _ILIT(7)
litTag (MachFloat     _)   = _ILIT(8)
litTag (MachDouble    _)   = _ILIT(9)
litTag (MachLabel _ _ _)   = _ILIT(10)
\end{code}

	Printing
	~~~~~~~~
* MachX (i.e. unboxed) things are printed unadornded (e.g. 3, 'a', "foo")
  exceptions: MachFloat gets an initial keyword prefix.

\begin{code}
pprLit :: Literal -> SDoc
pprLit (MachChar ch)  	= pprHsChar ch
pprLit (MachStr s)    	= pprHsString s
pprLit (MachInt i)    	= pprIntVal i
pprLit (MachInt64 i)  	= ptext (sLit "__int64") <+> integer i
pprLit (MachWord w)   	= ptext (sLit "__word") <+> integer w
pprLit (MachWord64 w) 	= ptext (sLit "__word64") <+> integer w
pprLit (MachFloat f)  	= ptext (sLit "__float") <+> rational f
pprLit (MachDouble d) 	= rational d
pprLit (MachNullAddr) 	= ptext (sLit "__NULL")
pprLit (MachLabel l mb fod) = ptext (sLit "__label") <+> b <+> ppr fod
    where b = case mb of
              Nothing -> pprHsString l
              Just x  -> doubleQuotes (text (unpackFS l ++ '@':show x))

pprIntVal :: Integer -> SDoc
-- ^ Print negative integers with parens to be sure it's unambiguous
pprIntVal i | i < 0     = parens (integer i)
	    | otherwise = integer i
\end{code}


%************************************************************************
%*									*
\subsection{Hashing}
%*									*
%************************************************************************

Hash values should be zero or a positive integer.  No negatives please.
(They mess up the UniqFM for some reason.)

\begin{code}
hashLiteral :: Literal -> Int
hashLiteral (MachChar c)    	= ord c + 1000	-- Keep it out of range of common ints
hashLiteral (MachStr s)     	= hashFS s
hashLiteral (MachNullAddr)    	= 0
hashLiteral (MachInt i)   	= hashInteger i
hashLiteral (MachInt64 i) 	= hashInteger i
hashLiteral (MachWord i)   	= hashInteger i
hashLiteral (MachWord64 i) 	= hashInteger i
hashLiteral (MachFloat r)   	= hashRational r
hashLiteral (MachDouble r)  	= hashRational r
hashLiteral (MachLabel s _ _)     = hashFS s

hashRational :: Rational -> Int
hashRational r = hashInteger (numerator r)

hashInteger :: Integer -> Int
hashInteger i = 1 + abs (fromInteger (i `rem` 10000))
		-- The 1+ is to avoid zero, which is a Bad Number
		-- since we use * to combine hash values

hashFS :: FastString -> Int
hashFS s = iBox (uniqueOfFS s)
\end{code}
