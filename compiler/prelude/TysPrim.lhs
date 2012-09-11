%
% (c) The AQUA Project, Glasgow University, 1994-1998
%
\section[TysPrim]{Wired-in knowledge about primitive types}

\begin{code}
module TysPrim(
	alphaTyVars, betaTyVars, alphaTyVar, betaTyVar, gammaTyVar, deltaTyVar,
	alphaTy, betaTy, gammaTy, deltaTy,
	openAlphaTy, openBetaTy, openAlphaTyVar, openBetaTyVar, openAlphaTyVars,

	primTyCons,

	charPrimTyCon, 		charPrimTy,
	intPrimTyCon,		intPrimTy,
	wordPrimTyCon,		wordPrimTy,
	addrPrimTyCon,		addrPrimTy,
	floatPrimTyCon,		floatPrimTy,
	doublePrimTyCon,	doublePrimTy,

	statePrimTyCon,		mkStatePrimTy,
	realWorldTyCon,		realWorldTy, realWorldStatePrimTy,

	arrayPrimTyCon,			mkArrayPrimTy, 
	byteArrayPrimTyCon,		byteArrayPrimTy,
	mutableArrayPrimTyCon,		mkMutableArrayPrimTy,
	mutableByteArrayPrimTyCon,	mkMutableByteArrayPrimTy,
	mutVarPrimTyCon,		mkMutVarPrimTy,

	mVarPrimTyCon,			mkMVarPrimTy,	
        tVarPrimTyCon,                  mkTVarPrimTy,
	stablePtrPrimTyCon,		mkStablePtrPrimTy,
	stableNamePrimTyCon,		mkStableNamePrimTy,
	bcoPrimTyCon,			bcoPrimTy,
	weakPrimTyCon,  		mkWeakPrimTy,
	threadIdPrimTyCon,		threadIdPrimTy,
	
	int32PrimTyCon,		int32PrimTy,
	word32PrimTyCon,	word32PrimTy,

	int64PrimTyCon,		int64PrimTy,
	word64PrimTyCon,	word64PrimTy,

	anyPrimTyCon, anyPrimTy, anyPrimTyCon1, mkAnyPrimTyCon
  ) where

#include "HsVersions.h"

import Var		( TyVar, mkTyVar )
import Name		( Name, BuiltInSyntax(..), mkInternalName, mkWiredInName )
import OccName		( mkTyVarOccFS, mkTcOccFS )
import TyCon		( TyCon, mkPrimTyCon, mkLiftedPrimTyCon,
			  PrimRep(..) )
import Type
import SrcLoc
import Unique		( mkAlphaTyVarUnique, pprUnique )
import PrelNames
import StaticFlags
import FastString
import Outputable

import Char 		( ord, chr )
\end{code}

%************************************************************************
%*									*
\subsection{Primitive type constructors}
%*									*
%************************************************************************

\begin{code}
primTyCons :: [TyCon]
primTyCons 
  = [ addrPrimTyCon
    , arrayPrimTyCon
    , byteArrayPrimTyCon
    , charPrimTyCon
    , doublePrimTyCon
    , floatPrimTyCon
    , intPrimTyCon
    , int32PrimTyCon
    , int64PrimTyCon
    , bcoPrimTyCon
    , weakPrimTyCon
    , mutableArrayPrimTyCon
    , mutableByteArrayPrimTyCon
    , mVarPrimTyCon
    , tVarPrimTyCon
    , mutVarPrimTyCon
    , realWorldTyCon
    , stablePtrPrimTyCon
    , stableNamePrimTyCon
    , statePrimTyCon
    , threadIdPrimTyCon
    , wordPrimTyCon
    , word32PrimTyCon
    , word64PrimTyCon
    , anyPrimTyCon, anyPrimTyCon1
    ]

mkPrimTc :: FastString -> Unique -> TyCon -> Name
mkPrimTc fs unique tycon
  = mkWiredInName gHC_PRIM (mkTcOccFS fs) 
		  unique
		  (ATyCon tycon)	-- Relevant TyCon
		  UserSyntax		-- None are built-in syntax

charPrimTyConName, intPrimTyConName, int32PrimTyConName, int64PrimTyConName, wordPrimTyConName, word32PrimTyConName, word64PrimTyConName, addrPrimTyConName, floatPrimTyConName, doublePrimTyConName, statePrimTyConName, realWorldTyConName, arrayPrimTyConName, byteArrayPrimTyConName, mutableArrayPrimTyConName, mutableByteArrayPrimTyConName, mutVarPrimTyConName, mVarPrimTyConName, tVarPrimTyConName, stablePtrPrimTyConName, stableNamePrimTyConName, bcoPrimTyConName, weakPrimTyConName, threadIdPrimTyConName, anyPrimTyConName, anyPrimTyCon1Name :: Name
charPrimTyConName    	      = mkPrimTc (fsLit "Char#") charPrimTyConKey charPrimTyCon
intPrimTyConName     	      = mkPrimTc (fsLit "Int#") intPrimTyConKey  intPrimTyCon
int32PrimTyConName	      = mkPrimTc (fsLit "Int32#") int32PrimTyConKey int32PrimTyCon
int64PrimTyConName   	      = mkPrimTc (fsLit "Int64#") int64PrimTyConKey int64PrimTyCon
wordPrimTyConName    	      = mkPrimTc (fsLit "Word#") wordPrimTyConKey wordPrimTyCon
word32PrimTyConName  	      = mkPrimTc (fsLit "Word32#") word32PrimTyConKey word32PrimTyCon
word64PrimTyConName  	      = mkPrimTc (fsLit "Word64#") word64PrimTyConKey word64PrimTyCon
addrPrimTyConName    	      = mkPrimTc (fsLit "Addr#") addrPrimTyConKey addrPrimTyCon
floatPrimTyConName   	      = mkPrimTc (fsLit "Float#") floatPrimTyConKey floatPrimTyCon
doublePrimTyConName  	      = mkPrimTc (fsLit "Double#") doublePrimTyConKey doublePrimTyCon
statePrimTyConName   	      = mkPrimTc (fsLit "State#") statePrimTyConKey statePrimTyCon
realWorldTyConName   	      = mkPrimTc (fsLit "RealWorld") realWorldTyConKey realWorldTyCon
arrayPrimTyConName   	      = mkPrimTc (fsLit "Array#") arrayPrimTyConKey arrayPrimTyCon
byteArrayPrimTyConName	      = mkPrimTc (fsLit "ByteArray#") byteArrayPrimTyConKey byteArrayPrimTyCon
mutableArrayPrimTyConName     = mkPrimTc (fsLit "MutableArray#") mutableArrayPrimTyConKey mutableArrayPrimTyCon
mutableByteArrayPrimTyConName = mkPrimTc (fsLit "MutableByteArray#") mutableByteArrayPrimTyConKey mutableByteArrayPrimTyCon
mutVarPrimTyConName	      = mkPrimTc (fsLit "MutVar#") mutVarPrimTyConKey mutVarPrimTyCon
mVarPrimTyConName	      = mkPrimTc (fsLit "MVar#") mVarPrimTyConKey mVarPrimTyCon
tVarPrimTyConName	      = mkPrimTc (fsLit "TVar#") tVarPrimTyConKey tVarPrimTyCon
stablePtrPrimTyConName        = mkPrimTc (fsLit "StablePtr#") stablePtrPrimTyConKey stablePtrPrimTyCon
stableNamePrimTyConName       = mkPrimTc (fsLit "StableName#") stableNamePrimTyConKey stableNamePrimTyCon
bcoPrimTyConName 	      = mkPrimTc (fsLit "BCO#") bcoPrimTyConKey bcoPrimTyCon
weakPrimTyConName  	      = mkPrimTc (fsLit "Weak#") weakPrimTyConKey weakPrimTyCon
threadIdPrimTyConName  	      = mkPrimTc (fsLit "ThreadId#") threadIdPrimTyConKey threadIdPrimTyCon
anyPrimTyConName	      = mkPrimTc (fsLit "Any") anyPrimTyConKey anyPrimTyCon
anyPrimTyCon1Name	      = mkPrimTc (fsLit "Any1") anyPrimTyCon1Key anyPrimTyCon
\end{code}

%************************************************************************
%*									*
\subsection{Support code}
%*									*
%************************************************************************

alphaTyVars is a list of type variables for use in templates: 
	["a", "b", ..., "z", "t1", "t2", ... ]

\begin{code}
tyVarList :: Kind -> [TyVar]
tyVarList kind = [ mkTyVar (mkInternalName (mkAlphaTyVarUnique u) 
				(mkTyVarOccFS (mkFastString name))
			 	noSrcSpan) kind
	         | u <- [2..],
		   let name | c <= 'z'  = [c]
		            | otherwise = 't':show u
			    where c = chr (u-2 + ord 'a')
	         ]

alphaTyVars :: [TyVar]
alphaTyVars = tyVarList liftedTypeKind

betaTyVars :: [TyVar]
betaTyVars = tail alphaTyVars

alphaTyVar, betaTyVar, gammaTyVar, deltaTyVar :: TyVar
(alphaTyVar:betaTyVar:gammaTyVar:deltaTyVar:_) = alphaTyVars

alphaTys :: [Type]
alphaTys = mkTyVarTys alphaTyVars
alphaTy, betaTy, gammaTy, deltaTy :: Type
(alphaTy:betaTy:gammaTy:deltaTy:_) = alphaTys

	-- openAlphaTyVar is prepared to be instantiated
	-- to a lifted or unlifted type variable.  It's used for the 
	-- result type for "error", so that we can have (error Int# "Help")
openAlphaTyVars :: [TyVar]
openAlphaTyVar, openBetaTyVar :: TyVar
openAlphaTyVars@(openAlphaTyVar:openBetaTyVar:_) = tyVarList openTypeKind

openAlphaTy, openBetaTy :: Type
openAlphaTy = mkTyVarTy openAlphaTyVar
openBetaTy   = mkTyVarTy openBetaTyVar
\end{code}


%************************************************************************
%*									*
\subsection[TysPrim-basic]{Basic primitive types (@Char#@, @Int#@, etc.)}
%*									*
%************************************************************************

\begin{code}
-- only used herein
pcPrimTyCon :: Name -> Int -> PrimRep -> TyCon
pcPrimTyCon name arity rep
  = mkPrimTyCon name kind arity rep
  where
    kind        = mkArrowKinds (replicate arity liftedTypeKind) result_kind
    result_kind = unliftedTypeKind

pcPrimTyCon0 :: Name -> PrimRep -> TyCon
pcPrimTyCon0 name rep
  = mkPrimTyCon name result_kind 0 rep
  where
    result_kind = unliftedTypeKind

charPrimTy :: Type
charPrimTy	= mkTyConTy charPrimTyCon
charPrimTyCon :: TyCon
charPrimTyCon	= pcPrimTyCon0 charPrimTyConName WordRep

intPrimTy :: Type
intPrimTy	= mkTyConTy intPrimTyCon
intPrimTyCon :: TyCon
intPrimTyCon	= pcPrimTyCon0 intPrimTyConName IntRep

int32PrimTy :: Type
int32PrimTy	= mkTyConTy int32PrimTyCon
int32PrimTyCon :: TyCon
int32PrimTyCon	= pcPrimTyCon0 int32PrimTyConName IntRep

int64PrimTy :: Type
int64PrimTy	= mkTyConTy int64PrimTyCon
int64PrimTyCon :: TyCon
int64PrimTyCon	= pcPrimTyCon0 int64PrimTyConName Int64Rep

wordPrimTy :: Type
wordPrimTy	= mkTyConTy wordPrimTyCon
wordPrimTyCon :: TyCon
wordPrimTyCon	= pcPrimTyCon0 wordPrimTyConName WordRep

word32PrimTy :: Type
word32PrimTy	= mkTyConTy word32PrimTyCon
word32PrimTyCon :: TyCon
word32PrimTyCon	= pcPrimTyCon0 word32PrimTyConName WordRep

word64PrimTy :: Type
word64PrimTy	= mkTyConTy word64PrimTyCon
word64PrimTyCon :: TyCon
word64PrimTyCon	= pcPrimTyCon0 word64PrimTyConName Word64Rep

addrPrimTy :: Type
addrPrimTy	= mkTyConTy addrPrimTyCon
addrPrimTyCon :: TyCon
addrPrimTyCon	= pcPrimTyCon0 addrPrimTyConName AddrRep

floatPrimTy	:: Type
floatPrimTy	= mkTyConTy floatPrimTyCon
floatPrimTyCon :: TyCon
floatPrimTyCon	= pcPrimTyCon0 floatPrimTyConName FloatRep

doublePrimTy :: Type
doublePrimTy	= mkTyConTy doublePrimTyCon
doublePrimTyCon	:: TyCon
doublePrimTyCon	= pcPrimTyCon0 doublePrimTyConName DoubleRep
\end{code}


%************************************************************************
%*									*
\subsection[TysPrim-state]{The @State#@ type (and @_RealWorld@ types)}
%*									*
%************************************************************************

State# is the primitive, unlifted type of states.  It has one type parameter,
thus
	State# RealWorld
or
	State# s

where s is a type variable. The only purpose of the type parameter is to
keep different state threads separate.  It is represented by nothing at all.

\begin{code}
mkStatePrimTy :: Type -> Type
mkStatePrimTy ty = mkTyConApp statePrimTyCon [ty]
statePrimTyCon :: TyCon
statePrimTyCon	 = pcPrimTyCon statePrimTyConName 1 VoidRep
\end{code}

RealWorld is deeply magical.  It is *primitive*, but it is not
*unlifted* (hence ptrArg).  We never manipulate values of type
RealWorld; it's only used in the type system, to parameterise State#.

\begin{code}
realWorldTyCon :: TyCon
realWorldTyCon = mkLiftedPrimTyCon realWorldTyConName liftedTypeKind 0 PtrRep
realWorldTy :: Type
realWorldTy	     = mkTyConTy realWorldTyCon
realWorldStatePrimTy :: Type
realWorldStatePrimTy = mkStatePrimTy realWorldTy	-- State# RealWorld
\end{code}

Note: the ``state-pairing'' types are not truly primitive, so they are
defined in \tr{TysWiredIn.lhs}, not here.


%************************************************************************
%*									*
		Any
%*									*
%************************************************************************

The type constructor Any is type to which you can unsafely coerce any
lifted type, and back. 

  * It is lifted, and hence represented by a pointer

  * It does not claim to be a *data* type, and that's important for
    the code generator, because the code gen may *enter* a data value
    but never enters a function value.  

It's also used to instantiate un-constrained type variables after type
checking.  For example
	length Any []
Annoyingly, we sometimes need Anys of other kinds, such as (*->*) etc.
This is a bit like tuples.   We define a couple of useful ones here,
and make others up on the fly.  If any of these others end up being exported
into interface files, we'll get a crash; at least until we add interface-file
syntax to support them.

\begin{code}
anyPrimTy :: Type
anyPrimTy = mkTyConApp anyPrimTyCon []

anyPrimTyCon :: TyCon 	-- Kind *
anyPrimTyCon = mkLiftedPrimTyCon anyPrimTyConName liftedTypeKind 0 PtrRep

anyPrimTyCon1 :: TyCon 	-- Kind *->*
anyPrimTyCon1 = mkLiftedPrimTyCon anyPrimTyCon1Name kind 0 PtrRep
  where
    kind = mkArrowKind liftedTypeKind liftedTypeKind
				  
mkAnyPrimTyCon :: Unique -> Kind -> TyCon
-- Grotesque hack alert: the client gives the unique; so equality won't work
mkAnyPrimTyCon unique kind 
  = WARN( opt_PprStyle_Debug, ptext (sLit "Urk! Inventing strangely-kinded Any TyCon:") <+> ppr unique <+> ppr kind )
	-- See Note [Strangely-kinded void TyCons] in TcHsSyn
    tycon
  where
     name  = mkPrimTc (mkFastString ("Any" ++ showSDoc (pprUnique unique))) unique tycon
     tycon = mkLiftedPrimTyCon name kind 0 PtrRep
\end{code}


%************************************************************************
%*									*
\subsection[TysPrim-arrays]{The primitive array types}
%*									*
%************************************************************************

\begin{code}
arrayPrimTyCon, mutableArrayPrimTyCon, mutableByteArrayPrimTyCon,
    byteArrayPrimTyCon :: TyCon
arrayPrimTyCon		  = pcPrimTyCon  arrayPrimTyConName	       1 PtrRep
mutableArrayPrimTyCon	  = pcPrimTyCon  mutableArrayPrimTyConName     2 PtrRep
mutableByteArrayPrimTyCon = pcPrimTyCon  mutableByteArrayPrimTyConName 1 PtrRep
byteArrayPrimTyCon	  = pcPrimTyCon0 byteArrayPrimTyConName	         PtrRep

mkArrayPrimTy :: Type -> Type
mkArrayPrimTy elt    	    = mkTyConApp arrayPrimTyCon [elt]
byteArrayPrimTy :: Type
byteArrayPrimTy	    	    = mkTyConTy byteArrayPrimTyCon
mkMutableArrayPrimTy :: Type -> Type -> Type
mkMutableArrayPrimTy s elt  = mkTyConApp mutableArrayPrimTyCon [s, elt]
mkMutableByteArrayPrimTy :: Type -> Type
mkMutableByteArrayPrimTy s  = mkTyConApp mutableByteArrayPrimTyCon [s]
\end{code}

%************************************************************************
%*									*
\subsection[TysPrim-mut-var]{The mutable variable type}
%*									*
%************************************************************************

\begin{code}
mutVarPrimTyCon :: TyCon
mutVarPrimTyCon = pcPrimTyCon mutVarPrimTyConName 2 PtrRep

mkMutVarPrimTy :: Type -> Type -> Type
mkMutVarPrimTy s elt 	    = mkTyConApp mutVarPrimTyCon [s, elt]
\end{code}

%************************************************************************
%*									*
\subsection[TysPrim-synch-var]{The synchronizing variable type}
%*									*
%************************************************************************

\begin{code}
mVarPrimTyCon :: TyCon
mVarPrimTyCon = pcPrimTyCon mVarPrimTyConName 2 PtrRep

mkMVarPrimTy :: Type -> Type -> Type
mkMVarPrimTy s elt 	    = mkTyConApp mVarPrimTyCon [s, elt]
\end{code}

%************************************************************************
%*									*
\subsection[TysPrim-stm-var]{The transactional variable type}
%*									*
%************************************************************************

\begin{code}
tVarPrimTyCon :: TyCon
tVarPrimTyCon = pcPrimTyCon tVarPrimTyConName 2 PtrRep

mkTVarPrimTy :: Type -> Type -> Type
mkTVarPrimTy s elt = mkTyConApp tVarPrimTyCon [s, elt]
\end{code}

%************************************************************************
%*									*
\subsection[TysPrim-stable-ptrs]{The stable-pointer type}
%*									*
%************************************************************************

\begin{code}
stablePtrPrimTyCon :: TyCon
stablePtrPrimTyCon = pcPrimTyCon stablePtrPrimTyConName 1 AddrRep

mkStablePtrPrimTy :: Type -> Type
mkStablePtrPrimTy ty = mkTyConApp stablePtrPrimTyCon [ty]
\end{code}

%************************************************************************
%*									*
\subsection[TysPrim-stable-names]{The stable-name type}
%*									*
%************************************************************************

\begin{code}
stableNamePrimTyCon :: TyCon
stableNamePrimTyCon = pcPrimTyCon stableNamePrimTyConName 1 PtrRep

mkStableNamePrimTy :: Type -> Type
mkStableNamePrimTy ty = mkTyConApp stableNamePrimTyCon [ty]
\end{code}

%************************************************************************
%*									*
\subsection[TysPrim-BCOs]{The ``bytecode object'' type}
%*									*
%************************************************************************

\begin{code}
bcoPrimTy    :: Type
bcoPrimTy    = mkTyConTy bcoPrimTyCon
bcoPrimTyCon :: TyCon
bcoPrimTyCon = pcPrimTyCon0 bcoPrimTyConName PtrRep
\end{code}
  
%************************************************************************
%*									*
\subsection[TysPrim-Weak]{The ``weak pointer'' type}
%*									*
%************************************************************************

\begin{code}
weakPrimTyCon :: TyCon
weakPrimTyCon = pcPrimTyCon weakPrimTyConName 1 PtrRep

mkWeakPrimTy :: Type -> Type
mkWeakPrimTy v = mkTyConApp weakPrimTyCon [v]
\end{code}

%************************************************************************
%*									*
\subsection[TysPrim-thread-ids]{The ``thread id'' type}
%*									*
%************************************************************************

A thread id is represented by a pointer to the TSO itself, to ensure
that they are always unique and we can always find the TSO for a given
thread id.  However, this has the unfortunate consequence that a
ThreadId# for a given thread is treated as a root by the garbage
collector and can keep TSOs around for too long.

Hence the programmer API for thread manipulation uses a weak pointer
to the thread id internally.

\begin{code}
threadIdPrimTy :: Type
threadIdPrimTy    = mkTyConTy threadIdPrimTyCon
threadIdPrimTyCon :: TyCon
threadIdPrimTyCon = pcPrimTyCon0 threadIdPrimTyConName PtrRep
\end{code}