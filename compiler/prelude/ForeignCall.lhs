%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%
\section[Foreign]{Foreign calls}

\begin{code}
{-# OPTIONS -w #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

module ForeignCall (
	ForeignCall(..),
	Safety(..), playSafe,

	CExportSpec(..), CLabelString, isCLabelString, pprCLabelString,
	CCallSpec(..), 
	CCallTarget(..), isDynamicTarget,
	CCallConv(..), defaultCCallConv, ccallConvToInt, ccallConvAttribute,
    ) where

import FastString
import Binary
import Outputable

import Data.Char
\end{code}


%************************************************************************
%*									*
\subsubsection{Data types}
%*									*
%************************************************************************

\begin{code}
newtype ForeignCall = CCall CCallSpec
  deriving Eq
  {-! derive: Binary !-}

-- We may need more clues to distinguish foreign calls
-- but this simple printer will do for now
instance Outputable ForeignCall where
  ppr (CCall cc)  = ppr cc		
\end{code}

  
\begin{code}
data Safety
  = PlaySafe		-- Might invoke Haskell GC, or do a call back, or
			-- switch threads, etc.  So make sure things are
			-- tidy before the call. Additionally, in the threaded
			-- RTS we arrange for the external call to be executed
			-- by a separate OS thread, i.e., _concurrently_ to the
			-- execution of other Haskell threads.

      Bool              -- Indicates the deprecated "threadsafe" annotation
                        -- which is now an alias for "safe". This information
                        -- is never used except to emit a deprecation warning.

  | PlayRisky		-- None of the above can happen; the call will return
			-- without interacting with the runtime system at all
  deriving ( Eq, Show )
	-- Show used just for Show Lex.Token, I think
  {-! derive: Binary !-}

instance Outputable Safety where
  ppr (PlaySafe False) = ptext (sLit "safe")
  ppr (PlaySafe True)  = ptext (sLit "threadsafe")
  ppr PlayRisky = ptext (sLit "unsafe")

playSafe :: Safety -> Bool
playSafe PlaySafe{} = True
playSafe PlayRisky  = False
\end{code}


%************************************************************************
%*									*
\subsubsection{Calling C}
%*									*
%************************************************************************

\begin{code}
data CExportSpec
  = CExportStatic		-- foreign export ccall foo :: ty
	CLabelString		-- C Name of exported function
	CCallConv
  {-! derive: Binary !-}

data CCallSpec
  =  CCallSpec	CCallTarget	-- What to call
		CCallConv	-- Calling convention to use.
		Safety
  deriving( Eq )
  {-! derive: Binary !-}
\end{code}

The call target:

\begin{code}
data CCallTarget
  = StaticTarget  CLabelString  -- An "unboxed" ccall# to `fn'.
  | DynamicTarget 		-- First argument (an Addr#) is the function pointer
  deriving( Eq )
  {-! derive: Binary !-}

isDynamicTarget :: CCallTarget -> Bool
isDynamicTarget DynamicTarget = True
isDynamicTarget _             = False
\end{code}


Stuff to do with calling convention:

ccall:		Caller allocates parameters, *and* deallocates them.

stdcall: 	Caller allocates parameters, callee deallocates.
		Function name has @N after it, where N is number of arg bytes
		e.g.  _Foo@8

ToDo: The stdcall calling convention is x86 (win32) specific,
so perhaps we should emit a warning if it's being used on other
platforms.
 
See: http://www.programmersheaven.com/2/Calling-conventions

\begin{code}
data CCallConv = CCallConv | StdCallConv | CmmCallConv | PrimCallConv
  deriving (Eq)
  {-! derive: Binary !-}

instance Outputable CCallConv where
  ppr StdCallConv = ptext (sLit "stdcall")
  ppr CCallConv   = ptext (sLit "ccall")
  ppr CmmCallConv = ptext (sLit "C--")
  ppr PrimCallConv = ptext (sLit "prim")

defaultCCallConv :: CCallConv
defaultCCallConv = CCallConv

ccallConvToInt :: CCallConv -> Int
ccallConvToInt StdCallConv = 0
ccallConvToInt CCallConv   = 1
\end{code}

Generate the gcc attribute corresponding to the given
calling convention (used by PprAbsC):

\begin{code}
ccallConvAttribute :: CCallConv -> String
ccallConvAttribute StdCallConv = "__attribute__((__stdcall__))"
ccallConvAttribute CCallConv   = ""
\end{code}

\begin{code}
type CLabelString = FastString		-- A C label, completely unencoded

pprCLabelString :: CLabelString -> SDoc
pprCLabelString lbl = ftext lbl

isCLabelString :: CLabelString -> Bool	-- Checks to see if this is a valid C label
isCLabelString lbl 
  = all ok (unpackFS lbl)
  where
    ok c = isAlphaNum c || c == '_' || c == '.'
	-- The '.' appears in e.g. "foo.so" in the 
	-- module part of a ExtName.  Maybe it should be separate
\end{code}


Printing into C files:

\begin{code}
instance Outputable CExportSpec where
  ppr (CExportStatic str _) = pprCLabelString str

instance Outputable CCallSpec where
  ppr (CCallSpec fun cconv safety)
    = hcat [ ifPprDebug callconv, ppr_fun fun ]
    where
      callconv = text "{-" <> ppr cconv <> text "-}"

      gc_suf | playSafe safety = text "_GC"
	     | otherwise       = empty

      ppr_fun DynamicTarget     = text "__dyn_ccall" <> gc_suf <+> text "\"\""
      ppr_fun (StaticTarget fn) = text "__ccall"     <> gc_suf <+> pprCLabelString fn
\end{code}


%************************************************************************
%*									*
\subsubsection{Misc}
%*									*
%************************************************************************

\begin{code}
{-* Generated by DrIFT-v1.0 : Look, but Don't Touch. *-}
instance Binary ForeignCall where
    put_ bh (CCall aa) = put_ bh aa
    get bh = do aa <- get bh; return (CCall aa)

instance Binary Safety where
    put_ bh (PlaySafe aa) = do
	    putByte bh 0
	    put_ bh aa
    put_ bh PlayRisky = do
	    putByte bh 1
    get bh = do
	    h <- getByte bh
	    case h of
	      0 -> do aa <- get bh
		      return (PlaySafe aa)
	      _ -> do return PlayRisky

instance Binary CExportSpec where
    put_ bh (CExportStatic aa ab) = do
	    put_ bh aa
	    put_ bh ab
    get bh = do
	  aa <- get bh
	  ab <- get bh
	  return (CExportStatic aa ab)

instance Binary CCallSpec where
    put_ bh (CCallSpec aa ab ac) = do
	    put_ bh aa
	    put_ bh ab
	    put_ bh ac
    get bh = do
	  aa <- get bh
	  ab <- get bh
	  ac <- get bh
	  return (CCallSpec aa ab ac)

instance Binary CCallTarget where
    put_ bh (StaticTarget aa) = do
	    putByte bh 0
	    put_ bh aa
    put_ bh DynamicTarget = do
	    putByte bh 1
    get bh = do
	    h <- getByte bh
	    case h of
	      0 -> do aa <- get bh
		      return (StaticTarget aa)
	      _ -> do return DynamicTarget

instance Binary CCallConv where
    put_ bh CCallConv = do
	    putByte bh 0
    put_ bh StdCallConv = do
	    putByte bh 1
    put_ bh PrimCallConv = do
	    putByte bh 2
    get bh = do
	    h <- getByte bh
	    case h of
	      0 -> do return CCallConv
	      1 -> do return StdCallConv
	      _ -> do return PrimCallConv
\end{code}
