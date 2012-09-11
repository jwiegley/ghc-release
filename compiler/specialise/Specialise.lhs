%
% (c) The GRASP/AQUA Project, Glasgow University, 1993-1998
%
\section[Specialise]{Stamping out overloading, and (optionally) polymorphism}

\begin{code}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

module Specialise ( specProgram ) where

#include "HsVersions.h"

import DynFlags	( DynFlags, DynFlag(..) )
import Id		( Id, idName, idType, mkUserLocal, idCoreRules,
			  idInlinePragma, setInlinePragma, setIdUnfolding,
			  isLocalId ) 
import TcType		( Type, mkTyVarTy, tcSplitSigmaTy, 
			  tyVarsOfTypes, tyVarsOfTheta, isClassPred,
			  tcCmpType, isUnLiftedType
			)
import CoreSubst	( Subst, mkEmptySubst, extendTvSubstList, lookupIdSubst,
			  substBndr, substBndrs, substTy, substInScope,
			  cloneIdBndr, cloneIdBndrs, cloneRecIdBndrs,
			  extendIdSubst
			) 
import CoreUnfold	( mkUnfolding )
import SimplUtils	( interestingArg )
import Var		( DictId )
import VarSet
import VarEnv
import CoreSyn
import Rules
import CoreUtils	( exprIsTrivial, applyTypeToArgs, mkPiTypes )
import CoreFVs		( exprFreeVars, exprsFreeVars, idFreeVars )
import CoreLint		( showPass, endPass )
import UniqSupply	( UniqSupply,
			  UniqSM, initUs_,
			  MonadUnique(..)
			)
import Name
import MkId		( voidArgId, realWorldPrimId )
import FiniteMap
import Maybes		( catMaybes, isJust )
import ErrUtils		( dumpIfSet_dyn )
import Bag
import Util
import Outputable
import FastString

\end{code}

%************************************************************************
%*									*
\subsection[notes-Specialise]{Implementation notes [SLPJ, Aug 18 1993]}
%*									*
%************************************************************************

These notes describe how we implement specialisation to eliminate
overloading.

The specialisation pass works on Core
syntax, complete with all the explicit dictionary application,
abstraction and construction as added by the type checker.  The
existing type checker remains largely as it is.

One important thought: the {\em types} passed to an overloaded
function, and the {\em dictionaries} passed are mutually redundant.
If the same function is applied to the same type(s) then it is sure to
be applied to the same dictionary(s)---or rather to the same {\em
values}.  (The arguments might look different but they will evaluate
to the same value.)

Second important thought: we know that we can make progress by
treating dictionary arguments as static and worth specialising on.  So
we can do without binding-time analysis, and instead specialise on
dictionary arguments and no others.

The basic idea
~~~~~~~~~~~~~~
Suppose we have

	let f = <f_rhs>
	in <body>

and suppose f is overloaded.

STEP 1: CALL-INSTANCE COLLECTION

We traverse <body>, accumulating all applications of f to types and
dictionaries.

(Might there be partial applications, to just some of its types and
dictionaries?  In principle yes, but in practice the type checker only
builds applications of f to all its types and dictionaries, so partial
applications could only arise as a result of transformation, and even
then I think it's unlikely.  In any case, we simply don't accumulate such
partial applications.)


STEP 2: EQUIVALENCES

So now we have a collection of calls to f:
	f t1 t2 d1 d2
	f t3 t4 d3 d4
	...
Notice that f may take several type arguments.  To avoid ambiguity, we
say that f is called at type t1/t2 and t3/t4.

We take equivalence classes using equality of the *types* (ignoring
the dictionary args, which as mentioned previously are redundant).

STEP 3: SPECIALISATION

For each equivalence class, choose a representative (f t1 t2 d1 d2),
and create a local instance of f, defined thus:

	f@t1/t2 = <f_rhs> t1 t2 d1 d2

f_rhs presumably has some big lambdas and dictionary lambdas, so lots
of simplification will now result.  However we don't actually *do* that
simplification.  Rather, we leave it for the simplifier to do.  If we
*did* do it, though, we'd get more call instances from the specialised
RHS.  We can work out what they are by instantiating the call-instance
set from f's RHS with the types t1, t2.

Add this new id to f's IdInfo, to record that f has a specialised version.

Before doing any of this, check that f's IdInfo doesn't already
tell us about an existing instance of f at the required type/s.
(This might happen if specialisation was applied more than once, or
it might arise from user SPECIALIZE pragmas.)

Recursion
~~~~~~~~~
Wait a minute!  What if f is recursive?  Then we can't just plug in
its right-hand side, can we?

But it's ok.  The type checker *always* creates non-recursive definitions
for overloaded recursive functions.  For example:

	f x = f (x+x)		-- Yes I know its silly

becomes

	f a (d::Num a) = let p = +.sel a d
			 in
			 letrec fl (y::a) = fl (p y y)
			 in
			 fl

We still have recusion for non-overloaded functions which we
speciailise, but the recursive call should get specialised to the
same recursive version.


Polymorphism 1
~~~~~~~~~~~~~~

All this is crystal clear when the function is applied to *constant
types*; that is, types which have no type variables inside.  But what if
it is applied to non-constant types?  Suppose we find a call of f at type
t1/t2.  There are two possibilities:

(a) The free type variables of t1, t2 are in scope at the definition point
of f.  In this case there's no problem, we proceed just as before.  A common
example is as follows.  Here's the Haskell:

	g y = let f x = x+x
	      in f y + f y

After typechecking we have

	g a (d::Num a) (y::a) = let f b (d'::Num b) (x::b) = +.sel b d' x x
				in +.sel a d (f a d y) (f a d y)

Notice that the call to f is at type type "a"; a non-constant type.
Both calls to f are at the same type, so we can specialise to give:

	g a (d::Num a) (y::a) = let f@a (x::a) = +.sel a d x x
				in +.sel a d (f@a y) (f@a y)


(b) The other case is when the type variables in the instance types
are *not* in scope at the definition point of f.  The example we are
working with above is a good case.  There are two instances of (+.sel a d),
but "a" is not in scope at the definition of +.sel.  Can we do anything?
Yes, we can "common them up", a sort of limited common sub-expression deal.
This would give:

	g a (d::Num a) (y::a) = let +.sel@a = +.sel a d
				    f@a (x::a) = +.sel@a x x
				in +.sel@a (f@a y) (f@a y)

This can save work, and can't be spotted by the type checker, because
the two instances of +.sel weren't originally at the same type.

Further notes on (b)

* There are quite a few variations here.  For example, the defn of
  +.sel could be floated ouside the \y, to attempt to gain laziness.
  It certainly mustn't be floated outside the \d because the d has to
  be in scope too.

* We don't want to inline f_rhs in this case, because
that will duplicate code.  Just commoning up the call is the point.

* Nothing gets added to +.sel's IdInfo.

* Don't bother unless the equivalence class has more than one item!

Not clear whether this is all worth it.  It is of course OK to
simply discard call-instances when passing a big lambda.

Polymorphism 2 -- Overloading
~~~~~~~~~~~~~~
Consider a function whose most general type is

	f :: forall a b. Ord a => [a] -> b -> b

There is really no point in making a version of g at Int/Int and another
at Int/Bool, because it's only instancing the type variable "a" which
buys us any efficiency. Since g is completely polymorphic in b there
ain't much point in making separate versions of g for the different
b types.

That suggests that we should identify which of g's type variables
are constrained (like "a") and which are unconstrained (like "b").
Then when taking equivalence classes in STEP 2, we ignore the type args
corresponding to unconstrained type variable.  In STEP 3 we make
polymorphic versions.  Thus:

	f@t1/ = /\b -> <f_rhs> t1 b d1 d2

We do this.


Dictionary floating
~~~~~~~~~~~~~~~~~~~
Consider this

	f a (d::Num a) = let g = ...
			 in
			 ...(let d1::Ord a = Num.Ord.sel a d in g a d1)...

Here, g is only called at one type, but the dictionary isn't in scope at the
definition point for g.  Usually the type checker would build a
definition for d1 which enclosed g, but the transformation system
might have moved d1's defn inward.  Solution: float dictionary bindings
outwards along with call instances.

Consider

	f x = let g p q = p==q
		  h r s = (r+s, g r s)
	      in
	      h x x


Before specialisation, leaving out type abstractions we have

	f df x = let g :: Eq a => a -> a -> Bool
		     g dg p q = == dg p q
		     h :: Num a => a -> a -> (a, Bool)
		     h dh r s = let deq = eqFromNum dh
				in (+ dh r s, g deq r s)
	      in
	      h df x x

After specialising h we get a specialised version of h, like this:

		    h' r s = let deq = eqFromNum df
			     in (+ df r s, g deq r s)

But we can't naively make an instance for g from this, because deq is not in scope
at the defn of g.  Instead, we have to float out the (new) defn of deq
to widen its scope.  Notice that this floating can't be done in advance -- it only
shows up when specialisation is done.

User SPECIALIZE pragmas
~~~~~~~~~~~~~~~~~~~~~~~
Specialisation pragmas can be digested by the type checker, and implemented
by adding extra definitions along with that of f, in the same way as before

	f@t1/t2 = <f_rhs> t1 t2 d1 d2

Indeed the pragmas *have* to be dealt with by the type checker, because
only it knows how to build the dictionaries d1 and d2!  For example

	g :: Ord a => [a] -> [a]
	{-# SPECIALIZE f :: [Tree Int] -> [Tree Int] #-}

Here, the specialised version of g is an application of g's rhs to the
Ord dictionary for (Tree Int), which only the type checker can conjure
up.  There might not even *be* one, if (Tree Int) is not an instance of
Ord!  (All the other specialision has suitable dictionaries to hand
from actual calls.)

Problem.  The type checker doesn't have to hand a convenient <f_rhs>, because
it is buried in a complex (as-yet-un-desugared) binding group.
Maybe we should say

	f@t1/t2 = f* t1 t2 d1 d2

where f* is the Id f with an IdInfo which says "inline me regardless!".
Indeed all the specialisation could be done in this way.
That in turn means that the simplifier has to be prepared to inline absolutely
any in-scope let-bound thing.


Again, the pragma should permit polymorphism in unconstrained variables:

	h :: Ord a => [a] -> b -> b
	{-# SPECIALIZE h :: [Int] -> b -> b #-}

We *insist* that all overloaded type variables are specialised to ground types,
(and hence there can be no context inside a SPECIALIZE pragma).
We *permit* unconstrained type variables to be specialised to
	- a ground type
	- or left as a polymorphic type variable
but nothing in between.  So

	{-# SPECIALIZE h :: [Int] -> [c] -> [c] #-}

is *illegal*.  (It can be handled, but it adds complication, and gains the
programmer nothing.)


SPECIALISING INSTANCE DECLARATIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider

	instance Foo a => Foo [a] where
		...
	{-# SPECIALIZE instance Foo [Int] #-}

The original instance decl creates a dictionary-function
definition:

	dfun.Foo.List :: forall a. Foo a -> Foo [a]

The SPECIALIZE pragma just makes a specialised copy, just as for
ordinary function definitions:

	dfun.Foo.List@Int :: Foo [Int]
	dfun.Foo.List@Int = dfun.Foo.List Int dFooInt

The information about what instance of the dfun exist gets added to
the dfun's IdInfo in the same way as a user-defined function too.


Automatic instance decl specialisation?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Can instance decls be specialised automatically?  It's tricky.
We could collect call-instance information for each dfun, but
then when we specialised their bodies we'd get new call-instances
for ordinary functions; and when we specialised their bodies, we might get
new call-instances of the dfuns, and so on.  This all arises because of
the unrestricted mutual recursion between instance decls and value decls.

Still, there's no actual problem; it just means that we may not do all
the specialisation we could theoretically do.

Furthermore, instance decls are usually exported and used non-locally,
so we'll want to compile enough to get those specialisations done.

Lastly, there's no such thing as a local instance decl, so we can
survive solely by spitting out *usage* information, and then reading that
back in as a pragma when next compiling the file.  So for now,
we only specialise instance decls in response to pragmas.


SPITTING OUT USAGE INFORMATION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To spit out usage information we need to traverse the code collecting
call-instance information for all imported (non-prelude?) functions
and data types. Then we equivalence-class it and spit it out.

This is done at the top-level when all the call instances which escape
must be for imported functions and data types.

*** Not currently done ***


Partial specialisation by pragmas
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
What about partial specialisation:

	k :: (Ord a, Eq b) => [a] -> b -> b -> [a]
	{-# SPECIALIZE k :: Eq b => [Int] -> b -> b -> [a] #-}

or even

	{-# SPECIALIZE k :: Eq b => [Int] -> [b] -> [b] -> [a] #-}

Seems quite reasonable.  Similar things could be done with instance decls:

	instance (Foo a, Foo b) => Foo (a,b) where
		...
	{-# SPECIALIZE instance Foo a => Foo (a,Int) #-}
	{-# SPECIALIZE instance Foo b => Foo (Int,b) #-}

Ho hum.  Things are complex enough without this.  I pass.


Requirements for the simplifer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The simplifier has to be able to take advantage of the specialisation.

* When the simplifier finds an application of a polymorphic f, it looks in
f's IdInfo in case there is a suitable instance to call instead.  This converts

	f t1 t2 d1 d2 	===>   f_t1_t2

Note that the dictionaries get eaten up too!

* Dictionary selection operations on constant dictionaries must be
  short-circuited:

	+.sel Int d	===>  +Int

The obvious way to do this is in the same way as other specialised
calls: +.sel has inside it some IdInfo which tells that if it's applied
to the type Int then it should eat a dictionary and transform to +Int.

In short, dictionary selectors need IdInfo inside them for constant
methods.

* Exactly the same applies if a superclass dictionary is being
  extracted:

	Eq.sel Int d   ===>   dEqInt

* Something similar applies to dictionary construction too.  Suppose
dfun.Eq.List is the function taking a dictionary for (Eq a) to
one for (Eq [a]).  Then we want

	dfun.Eq.List Int d	===> dEq.List_Int

Where does the Eq [Int] dictionary come from?  It is built in
response to a SPECIALIZE pragma on the Eq [a] instance decl.

In short, dfun Ids need IdInfo with a specialisation for each
constant instance of their instance declaration.

All this uses a single mechanism: the SpecEnv inside an Id


What does the specialisation IdInfo look like?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The SpecEnv of an Id maps a list of types (the template) to an expression

	[Type]  |->  Expr

For example, if f has this SpecInfo:

	[Int, a]  ->  \d:Ord Int. f' a

it means that we can replace the call

	f Int t  ===>  (\d. f' t)

This chucks one dictionary away and proceeds with the
specialised version of f, namely f'.


What can't be done this way?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
There is no way, post-typechecker, to get a dictionary for (say)
Eq a from a dictionary for Eq [a].  So if we find

	==.sel [t] d

we can't transform to

	eqList (==.sel t d')

where
	eqList :: (a->a->Bool) -> [a] -> [a] -> Bool

Of course, we currently have no way to automatically derive
eqList, nor to connect it to the Eq [a] instance decl, but you
can imagine that it might somehow be possible.  Taking advantage
of this is permanently ruled out.

Still, this is no great hardship, because we intend to eliminate
overloading altogether anyway!

A note about non-tyvar dictionaries
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Some Ids have types like

	forall a,b,c. Eq a -> Ord [a] -> tau

This seems curious at first, because we usually only have dictionary
args whose types are of the form (C a) where a is a type variable.
But this doesn't hold for the functions arising from instance decls,
which sometimes get arguements with types of form (C (T a)) for some
type constructor T.

Should we specialise wrt this compound-type dictionary?  We used to say
"no", saying:
	"This is a heuristic judgement, as indeed is the fact that we 
	specialise wrt only dictionaries.  We choose *not* to specialise
	wrt compound dictionaries because at the moment the only place
	they show up is in instance decls, where they are simply plugged
	into a returned dictionary.  So nothing is gained by specialising
	wrt them."

But it is simpler and more uniform to specialise wrt these dicts too;
and in future GHC is likely to support full fledged type signatures 
like
	f :: Eq [(a,b)] => ...


%************************************************************************
%*									*
\subsubsection{The new specialiser}
%*									*
%************************************************************************

Our basic game plan is this.  For let(rec) bound function
	f :: (C a, D c) => (a,b,c,d) -> Bool

* Find any specialised calls of f, (f ts ds), where 
  ts are the type arguments t1 .. t4, and
  ds are the dictionary arguments d1 .. d2.

* Add a new definition for f1 (say):

	f1 = /\ b d -> (..body of f..) t1 b t3 d d1 d2

  Note that we abstract over the unconstrained type arguments.

* Add the mapping

	[t1,b,t3,d]  |->  \d1 d2 -> f1 b d

  to the specialisations of f.  This will be used by the
  simplifier to replace calls 
		(f t1 t2 t3 t4) da db
  by
		(\d1 d1 -> f1 t2 t4) da db

  All the stuff about how many dictionaries to discard, and what types
  to apply the specialised function to, are handled by the fact that the
  SpecEnv contains a template for the result of the specialisation.

We don't build *partial* specialisations for f.  For example:

  f :: Eq a => a -> a -> Bool
  {-# SPECIALISE f :: (Eq b, Eq c) => (b,c) -> (b,c) -> Bool #-}

Here, little is gained by making a specialised copy of f.
There's a distinct danger that the specialised version would
first build a dictionary for (Eq b, Eq c), and then select the (==) 
method from it!  Even if it didn't, not a great deal is saved.

We do, however, generate polymorphic, but not overloaded, specialisations:

  f :: Eq a => [a] -> b -> b -> b
  {#- SPECIALISE f :: [Int] -> b -> b -> b #-}

Hence, the invariant is this: 

	*** no specialised version is overloaded ***


%************************************************************************
%*									*
\subsubsection{The exported function}
%*									*
%************************************************************************

\begin{code}
specProgram :: DynFlags -> UniqSupply -> [CoreBind] -> IO [CoreBind]
specProgram dflags us binds = do
   
	showPass dflags "Specialise"

	let binds' = initSM us (do (binds', uds') <- go binds
			           return (dumpAllDictBinds uds' binds'))

	endPass dflags "Specialise" Opt_D_dump_spec binds'

	dumpIfSet_dyn dflags Opt_D_dump_rules "Top-level specialisations"
		      (pprRulesForUser (rulesOfBinds binds'))

	return binds'
  where
	-- We need to start with a Subst that knows all the things
	-- that are in scope, so that the substitution engine doesn't
	-- accidentally re-use a unique that's already in use
	-- Easiest thing is to do it all at once, as if all the top-level
	-- decls were mutually recursive
    top_subst       = mkEmptySubst (mkInScopeSet (mkVarSet (bindersOfBinds binds)))

    go []           = return ([], emptyUDs)
    go (bind:binds) = do (binds', uds) <- go binds
                         (bind', uds') <- specBind top_subst bind uds
                         return (bind' ++ binds', uds')
\end{code}

%************************************************************************
%*									*
\subsubsection{@specExpr@: the main function}
%*									*
%************************************************************************

\begin{code}
specVar :: Subst -> Id -> CoreExpr
specVar subst v = lookupIdSubst subst v

specExpr :: Subst -> CoreExpr -> SpecM (CoreExpr, UsageDetails)
-- We carry a substitution down:
--	a) we must clone any binding that might float outwards,
--	   to avoid name clashes
--	b) we carry a type substitution to use when analysing
--	   the RHS of specialised bindings (no type-let!)

---------------- First the easy cases --------------------
specExpr subst (Type ty) = return (Type (substTy subst ty), emptyUDs)
specExpr subst (Var v)   = return (specVar subst v,         emptyUDs)
specExpr _     (Lit lit) = return (Lit lit,                 emptyUDs)
specExpr subst (Cast e co) = do
    (e', uds) <- specExpr subst e
    return ((Cast e' (substTy subst co)), uds)
specExpr subst (Note note body) = do
    (body', uds) <- specExpr subst body
    return (Note (specNote subst note) body', uds)


---------------- Applications might generate a call instance --------------------
specExpr subst expr@(App {})
  = go expr []
  where
    go (App fun arg) args = do (arg', uds_arg) <- specExpr subst arg
                               (fun', uds_app) <- go fun (arg':args)
                               return (App fun' arg', uds_arg `plusUDs` uds_app)

    go (Var f)       args = case specVar subst f of
                                Var f' -> return (Var f', mkCallUDs f' args)
                                e'     -> return (e', emptyUDs)	-- I don't expect this!
    go other	     _    = specExpr subst other

---------------- Lambda/case require dumping of usage details --------------------
specExpr subst e@(Lam _ _) = do
    (body', uds) <- specExpr subst' body
    let (filtered_uds, body'') = dumpUDs bndrs' uds body'
    return (mkLams bndrs' body'', filtered_uds)
  where
    (bndrs, body) = collectBinders e
    (subst', bndrs') = substBndrs subst bndrs
	-- More efficient to collect a group of binders together all at once
	-- and we don't want to split a lambda group with dumped bindings

specExpr subst (Case scrut case_bndr ty alts) = do
    (scrut', uds_scrut) <- specExpr subst scrut
    (alts', uds_alts) <- mapAndCombineSM spec_alt alts
    return (Case scrut' case_bndr' (substTy subst ty) alts', uds_scrut `plusUDs` uds_alts)
  where
    (subst_alt, case_bndr') = substBndr subst case_bndr
	-- No need to clone case binder; it can't float like a let(rec)

    spec_alt (con, args, rhs) = do
          (rhs', uds) <- specExpr subst_rhs rhs
          let (uds', rhs'') = dumpUDs args uds rhs'
          return ((con, args', rhs''), uds')
        where
          (subst_rhs, args') = substBndrs subst_alt args

---------------- Finally, let is the interesting case --------------------
specExpr subst (Let bind body) = do
   	-- Clone binders
    (rhs_subst, body_subst, bind') <- cloneBindSM subst bind

        -- Deal with the body
    (body', body_uds) <- specExpr body_subst body

        -- Deal with the bindings
    (binds', uds) <- specBind rhs_subst bind' body_uds

        -- All done
    return (foldr Let body' binds', uds)

-- Must apply the type substitution to coerceions
specNote :: Subst -> Note -> Note
specNote _ note = note
\end{code}

%************************************************************************
%*									*
\subsubsection{Dealing with a binding}
%*									*
%************************************************************************

\begin{code}
specBind :: Subst			-- Use this for RHSs
	 -> CoreBind
	 -> UsageDetails		-- Info on how the scope of the binding
	 -> SpecM ([CoreBind],		-- New bindings
		   UsageDetails)	-- And info to pass upstream

specBind rhs_subst bind body_uds
  = do	{ (bind', bind_uds) <- specBindItself rhs_subst bind (calls body_uds)
	; return (finishSpecBind bind' bind_uds body_uds) }

finishSpecBind :: CoreBind -> UsageDetails -> UsageDetails -> ([CoreBind], UsageDetails)
finishSpecBind bind 
	(MkUD { dict_binds = rhs_dbs,  calls = rhs_calls,  ud_fvs = rhs_fvs })
	(MkUD { dict_binds = body_dbs, calls = body_calls, ud_fvs = body_fvs })
  | not (mkVarSet bndrs `intersectsVarSet` all_fvs)
		-- Common case 1: the bound variables are not
		--		  mentioned in the dictionary bindings
  = ([bind], MkUD { dict_binds = body_dbs `unionBags` rhs_dbs
			-- It's important that the `unionBags` is this way round,
			-- because body_uds may bind dictionaries that are
			-- used in the calls passed to specDefn.  So the
			-- dictionary bindings in rhs_uds may mention 
			-- dictionaries bound in body_uds.
		  , calls  = all_calls
		  , ud_fvs = all_fvs })

  | case bind of { NonRec {} -> True; Rec {} -> False }
		-- Common case 2: no specialisation happened, and binding
		--		  is non-recursive.  But the binding may be
		--		  mentioned in body_dbs, so we should put it first
  = ([], MkUD { dict_binds = rhs_dbs `unionBags` ((bind, b_fvs) `consBag` body_dbs)
	      , calls      = all_calls
	      , ud_fvs     = all_fvs `unionVarSet` b_fvs })

  | otherwise	-- General case: make a huge Rec (sigh)
  = ([], MkUD { dict_binds = unitBag (Rec all_db_prs, all_db_fvs)
	      , calls      = all_calls
	      , ud_fvs     = all_fvs `unionVarSet` b_fvs })
  where
    all_fvs = rhs_fvs `unionVarSet` body_fvs
    all_calls = zapCalls bndrs (rhs_calls `unionCalls` body_calls)

    bndrs   = bindersOf bind
    b_fvs   = bind_fvs bind

    (all_db_prs, all_db_fvs) = add (bind, b_fvs) $ 
			       foldrBag add ([], emptyVarSet) $
			       rhs_dbs `unionBags` body_dbs
    add (NonRec b r, b_fvs) (prs, fvs) = ((b,r)  : prs, b_fvs `unionVarSet` fvs)
    add (Rec b_prs,  b_fvs) (prs, fvs) = (b_prs ++ prs, b_fvs `unionVarSet` fvs)

---------------------------
specBindItself :: Subst -> CoreBind -> CallDetails -> SpecM (CoreBind, UsageDetails)

-- specBindItself deals with the RHS, specialising it according
-- to the calls found in the body (if any)
specBindItself rhs_subst (NonRec fn rhs) call_info
  = do { (rhs', rhs_uds) <- specExpr rhs_subst rhs	     -- Do RHS of original fn
       ; (fn', spec_defns, spec_uds) <- specDefn rhs_subst call_info fn rhs
       ; if null spec_defns then
       	    return (NonRec fn rhs', rhs_uds)
	 else 
	    return (Rec ((fn',rhs') : spec_defns), rhs_uds `plusUDs` spec_uds) }
		-- bndr' mentions the spec_defns in its SpecEnv
		-- Not sure why we couln't just put the spec_defns first
	    	  
specBindItself rhs_subst (Rec pairs) call_info
       -- Note [Specialising a recursive group]
  = do { let (bndrs,rhss) = unzip pairs
       ; (rhss', rhs_uds) <- mapAndCombineSM (specExpr rhs_subst) rhss
       ; let all_calls = call_info `unionCalls` calls rhs_uds
       ; (bndrs1, spec_defns1, spec_uds1) <- specDefns rhs_subst all_calls pairs

       ; if null spec_defns1 then   -- Common case: no specialisation
       	    return (Rec (bndrs `zip` rhss'), rhs_uds)
	 else do   	       	     -- Specialisation occurred; do it again
       { (bndrs2, spec_defns2, spec_uds2) <- 
       	 	  -- pprTrace "specB" (ppr bndrs $$ ppr rhs_uds) $
       	 	  specDefns rhs_subst (calls spec_uds1) (bndrs1 `zip` rhss)

       ; let all_defns = spec_defns1 ++ spec_defns2 ++ zip bndrs2 rhss'
             
       ; return (Rec all_defns, rhs_uds `plusUDs` spec_uds1 `plusUDs` spec_uds2) } }


---------------------------
specDefns :: Subst
	 -> CallDetails			-- Info on how it is used in its scope
	 -> [(Id,CoreExpr)]		-- The things being bound and their un-processed RHS
	 -> SpecM ([Id],		-- Original Ids with RULES added
	    	   [(Id,CoreExpr)],	-- Extra, specialised bindings
		   UsageDetails)	-- Stuff to fling upwards from the specialised versions

-- Specialise a list of bindings (the contents of a Rec), but flowing usages
-- upwards binding by binding.  Example: { f = ...g ...; g = ...f .... }
-- Then if the input CallDetails has a specialised call for 'g', whose specialisation
-- in turn generates a specialised call for 'f', we catch that in this one sweep.
-- But not vice versa (it's a fixpoint problem).

specDefns _subst _call_info []
  = return ([], [], emptyUDs)
specDefns subst call_info ((bndr,rhs):pairs)
  = do { (bndrs', spec_defns, spec_uds) <- specDefns subst call_info pairs
       ; let all_calls = call_info `unionCalls` calls spec_uds
       ; (bndr', spec_defns1, spec_uds1) <- specDefn subst all_calls bndr rhs
       ; return (bndr' : bndrs',
       	 	 spec_defns1 ++ spec_defns, 
		 spec_uds1 `plusUDs` spec_uds) }

---------------------------
specDefn :: Subst
	 -> CallDetails			-- Info on how it is used in its scope
	 -> Id -> CoreExpr		-- The thing being bound and its un-processed RHS
	 -> SpecM (Id,			-- Original Id with added RULES
		   [(Id,CoreExpr)],	-- Extra, specialised bindings
	    	   UsageDetails)	-- Stuff to fling upwards from the specialised versions

specDefn subst calls fn rhs
	-- The first case is the interesting one
  |  rhs_tyvars `lengthIs`     n_tyvars -- Rhs of fn's defn has right number of big lambdas
  && rhs_ids    `lengthAtLeast` n_dicts	-- and enough dict args
  && notNull calls_for_me		-- And there are some calls to specialise

--   && not (certainlyWillInline (idUnfolding fn))	-- And it's not small
--	See Note [Inline specialisation] for why we do not 
--	switch off specialisation for inline functions

  = do {       -- Make a specialised version for each call in calls_for_me
         stuff <- mapM spec_call calls_for_me
       ; let (spec_defns, spec_uds, spec_rules) = unzip3 (catMaybes stuff)
             fn' = addIdSpecialisations fn spec_rules
       ; return (fn', spec_defns, plusUDList spec_uds) }

  | otherwise	-- No calls or RHS doesn't fit our preconceptions
  = WARN( notNull calls_for_me, ptext (sLit "Missed specialisation opportunity for") <+> ppr fn )
	  -- Note [Specialisation shape]
    return (fn, [], emptyUDs)
  
  where
    fn_type	       = idType fn
    (tyvars, theta, _) = tcSplitSigmaTy fn_type
    n_tyvars	       = length tyvars
    n_dicts	       = length theta
    inline_prag        = idInlinePragma fn

	-- It's important that we "see past" any INLINE pragma
	-- else we'll fail to specialise an INLINE thing
    (inline_rhs, rhs_inside) = dropInline rhs
    (rhs_tyvars, rhs_ids, rhs_body) = collectTyAndValBinders rhs_inside

    rhs_dict_ids = take n_dicts rhs_ids
    body         = mkLams (drop n_dicts rhs_ids) rhs_body
		-- Glue back on the non-dict lambdas

    calls_for_me = case lookupFM calls fn of
			Nothing -> []
			Just cs -> fmToList cs

    already_covered :: [CoreExpr] -> Bool
    already_covered args	  -- Note [Specialisations already covered]
       = isJust (lookupRule (const True) (substInScope subst) 
       	 		    fn args (idCoreRules fn))

    mk_ty_args :: [Maybe Type] -> [CoreExpr]
    mk_ty_args call_ts = zipWithEqual "spec_call" mk_ty_arg rhs_tyvars call_ts
    	       where
	          mk_ty_arg rhs_tyvar Nothing   = Type (mkTyVarTy rhs_tyvar)
		  mk_ty_arg _	      (Just ty) = Type ty

    ----------------------------------------------------------
	-- Specialise to one particular call pattern
    spec_call :: (CallKey, ([DictExpr], VarSet))  -- Call instance
              -> SpecM (Maybe ((Id,CoreExpr),	  -- Specialised definition
	                       UsageDetails, 	  -- Usage details from specialised body
			       CoreRule))	  -- Info for the Id's SpecEnv
    spec_call (CallKey call_ts, (call_ds, _))
      = ASSERT( call_ts `lengthIs` n_tyvars  && call_ds `lengthIs` n_dicts )
	
	-- Suppose f's defn is 	f = /\ a b c -> \ d1 d2 -> rhs	
        -- Supppose the call is for f [Just t1, Nothing, Just t3] [dx1, dx2]

	-- Construct the new binding
	-- 	f1 = SUBST[a->t1,c->t3, d1->d1', d2->d2'] (/\ b -> rhs)
	-- PLUS the usage-details
	--	{ d1' = dx1; d2' = dx2 }
	-- where d1', d2' are cloned versions of d1,d2, with the type substitution
	-- applied.  These auxiliary bindings just avoid duplication of dx1, dx2
	--
	-- Note that the substitution is applied to the whole thing.
	-- This is convenient, but just slightly fragile.  Notably:
	--	* There had better be no name clashes in a/b/c
        do { let
		-- poly_tyvars = [b] in the example above
		-- spec_tyvars = [a,c] 
		-- ty_args     = [t1,b,t3]
		poly_tyvars   = [tv | (tv, Nothing) <- rhs_tyvars `zip` call_ts]
           	spec_tv_binds = [(tv,ty) | (tv, Just ty) <- rhs_tyvars `zip` call_ts]
		spec_ty_args  = map snd spec_tv_binds
	   	ty_args       = mk_ty_args call_ts
	   	rhs_subst     = extendTvSubstList subst spec_tv_binds

	   ; (rhs_subst1, inst_dict_ids) <- cloneDictBndrs rhs_subst rhs_dict_ids
	     		  -- Clone rhs_dicts, including instantiating their types

	   ; let (rhs_subst2, dx_binds) = bindAuxiliaryDicts rhs_subst1 $
	     	 	      		  (my_zipEqual rhs_dict_ids inst_dict_ids call_ds)
	         inst_args = ty_args ++ map Var inst_dict_ids

	   ; if already_covered inst_args then
	        return Nothing
	     else do
	   {	-- Figure out the type of the specialised function
	     let body_ty = applyTypeToArgs rhs fn_type inst_args
	         (lam_args, app_args) 		-- Add a dummy argument if body_ty is unlifted
		   | isUnLiftedType body_ty	-- C.f. WwLib.mkWorkerArgs
		   = (poly_tyvars ++ [voidArgId], poly_tyvars ++ [realWorldPrimId])
		   | otherwise = (poly_tyvars, poly_tyvars)
	         spec_id_ty = mkPiTypes lam_args body_ty
	
           ; spec_f <- newSpecIdSM fn spec_id_ty
           ; (spec_rhs, rhs_uds) <- specExpr rhs_subst2 (mkLams lam_args body)
	   ; let
		-- The rule to put in the function's specialisation is:
		--	forall b, d1',d2'.  f t1 b t3 d1' d2' = f1 b  
	        rule_name = mkFastString ("SPEC " ++ showSDoc (ppr fn <+> ppr spec_ty_args))
  		spec_env_rule = mkLocalRule
			          rule_name
				  inline_prag 	-- Note [Auto-specialisation and RULES]
			 	  (idName fn)
			          (poly_tyvars ++ inst_dict_ids)
				  inst_args 
				  (mkVarApps (Var spec_f) app_args)

		-- Add the { d1' = dx1; d2' = dx2 } usage stuff
	   	final_uds = foldr addDictBind rhs_uds dx_binds

	   	spec_pr | inline_rhs = (spec_f `setInlinePragma` inline_prag, Note InlineMe spec_rhs)
		        | otherwise  = (spec_f, 		 	      spec_rhs)

	   ; return (Just (spec_pr, final_uds, spec_env_rule)) } }
      where
	my_zipEqual xs ys zs
	 | debugIsOn && not (equalLength xs ys && equalLength ys zs)
             = pprPanic "my_zipEqual" (vcat [ ppr xs, ppr ys
					    , ppr fn <+> ppr call_ts
					    , ppr (idType fn), ppr theta
					    , ppr n_dicts, ppr rhs_dict_ids 
					    , ppr rhs])
    	 | otherwise = zip3 xs ys zs

bindAuxiliaryDicts
	:: Subst
	-> [(DictId,DictId,CoreExpr)]	-- (orig_dict, inst_dict, dx)
	-> (Subst,			-- Substitute for all orig_dicts
	    [(DictId, CoreExpr)])	-- Auxiliary bindings
-- Bind any dictionary arguments to fresh names, to preserve sharing
-- Substitution already substitutes orig_dict -> inst_dict
bindAuxiliaryDicts subst triples = go subst [] triples
  where
    go subst binds []    = (subst, binds)
    go subst binds ((d, dx_id, dx) : pairs)
      | exprIsTrivial dx = go (extendIdSubst subst d dx) binds pairs
             -- No auxiliary binding necessary
      | otherwise        = go subst_w_unf ((dx_id,dx) : binds) pairs
      where
        dx_id1 = dx_id `setIdUnfolding` mkUnfolding False dx
	subst_w_unf = extendIdSubst subst d (Var dx_id1)
       	     -- Important!  We're going to substitute dx_id1 for d
	     -- and we want it to look "interesting", else we won't gather *any*
	     -- consequential calls. E.g.
	     --	    f d = ...g d....
	     -- If we specialise f for a call (f (dfun dNumInt)), we'll get 
	     -- a consequent call (g d') with an auxiliary definition
	     --	    d' = df dNumInt
  	     -- We want that consequent call to look interesting
\end{code}

Note [Specialising a recursive group]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider
    let rec { f x = ...g x'...
            ; g y = ...f y'.... }
    in f 'a'
Here we specialise 'f' at Char; but that is very likely to lead to 
a specialisation of 'g' at Char.  We must do the latter, else the
whole point of specialisation is lost.

But we do not want to keep iterating to a fixpoint, because in the
presence of polymorphic recursion we might generate an infinite number
of specialisations.

So we use the following heuristic:
  * Arrange the rec block in dependency order, so far as possible
    (the occurrence analyser already does this)

  * Specialise it much like a sequence of lets

  * Then go through the block a second time, feeding call-info from
    the RHSs back in the bottom, as it were

In effect, the ordering maxmimises the effectiveness of each sweep,
and we do just two sweeps.   This should catch almost every case of 
monomorphic recursion -- the exception could be a very knotted-up
recursion with multiple cycles tied up together.

This plan is implemented in the Rec case of specBindItself.
 
Note [Specialisations already covered]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We obviously don't want to generate two specialisations for the same
argument pattern.  There are two wrinkles

1. We do the already-covered test in specDefn, not when we generate
the CallInfo in mkCallUDs.  We used to test in the latter place, but
we now iterate the specialiser somewhat, and the Id at the call site
might therefore not have all the RULES that we can see in specDefn

2. What about two specialisations where the second is an *instance*
of the first?  If the more specific one shows up first, we'll generate
specialisations for both.  If the *less* specific one shows up first,
we *don't* currently generate a specialisation for the more specific
one.  (See the call to lookupRule in already_covered.)  Reasons:
  (a) lookupRule doesn't say which matches are exact (bad reason)
  (b) if the earlier specialisation is user-provided, it's
      far from clear that we should auto-specialise further

Note [Auto-specialisation and RULES]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider:
   g :: Num a => a -> a
   g = ...

   f :: (Int -> Int) -> Int
   f w = ...
   {-# RULE f g = 0 #-}

Suppose that auto-specialisation makes a specialised version of
g::Int->Int That version won't appear in the LHS of the RULE for f.
So if the specialisation rule fires too early, the rule for f may
never fire. 

It might be possible to add new rules, to "complete" the rewrite system.
Thus when adding
	RULE forall d. g Int d = g_spec
also add
	RULE f g_spec = 0

But that's a bit complicated.  For now we ask the programmer's help,
by *copying the INLINE activation pragma* to the auto-specialised rule.
So if g says {-# NOINLINE[2] g #-}, then the auto-spec rule will also
not be active until phase 2.  


Note [Specialisation shape]
~~~~~~~~~~~~~~~~~~~~~~~~~~~
We only specialise a function if it has visible top-level lambdas
corresponding to its overloading.  E.g. if
	f :: forall a. Eq a => ....
then its body must look like
	f = /\a. \d. ...

Reason: when specialising the body for a call (f ty dexp), we want to
substitute dexp for d, and pick up specialised calls in the body of f.

This doesn't always work.  One example I came across was this:
	newtype Gen a = MkGen{ unGen :: Int -> a }

	choose :: Eq a => a -> Gen a
	choose n = MkGen (\r -> n)

	oneof = choose (1::Int)

It's a silly exapmle, but we get
	choose = /\a. g `cast` co
where choose doesn't have any dict arguments.  Thus far I have not
tried to fix this (wait till there's a real example).


Note [Inline specialisations]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We transfer to the specialised function any INLINE stuff from the
original.  This means (a) the Activation in the IdInfo, and (b) any
InlineMe on the RHS.  

This is a change (Jun06).  Previously the idea is that the point of
inlining was precisely to specialise the function at its call site,
and that's not so important for the specialised copies.  But
*pragma-directed* specialisation now takes place in the
typechecker/desugarer, with manually specified INLINEs.  The
specialiation here is automatic.  It'd be very odd if a function
marked INLINE was specialised (because of some local use), and then
forever after (including importing modules) the specialised version
wasn't INLINEd.  After all, the programmer said INLINE!

You might wonder why we don't just not specialise INLINE functions.
It's because even INLINE functions are sometimes not inlined, when 
they aren't applied to interesting arguments.  But perhaps the type
arguments alone are enough to specialise (even though the args are too
boring to trigger inlining), and it's certainly better to call the 
specialised version.

A case in point is dictionary functions, which are current marked
INLINE, but which are worth specialising.

\begin{code}
dropInline :: CoreExpr -> (Bool, CoreExpr)
dropInline (Note InlineMe rhs) = (True,  rhs)
dropInline rhs		       = (False, rhs)
\end{code}

%************************************************************************
%*									*
\subsubsection{UsageDetails and suchlike}
%*									*
%************************************************************************

\begin{code}
data UsageDetails 
  = MkUD {
	dict_binds :: !(Bag DictBind),
			-- Floated dictionary bindings
			-- The order is important; 
			-- in ds1 `union` ds2, bindings in ds2 can depend on those in ds1
			-- (Remember, Bags preserve order in GHC.)

	calls     :: !CallDetails, 

	ud_fvs :: !VarSet	-- A superset of the variables mentioned in 
				-- either dict_binds or calls
    }

instance Outputable UsageDetails where
  ppr (MkUD { dict_binds = dbs, calls = calls, ud_fvs = fvs })
	= ptext (sLit "MkUD") <+> braces (sep (punctuate comma 
		[ptext (sLit "binds") <+> equals <+> ppr dbs,
	 	 ptext (sLit "calls") <+> equals <+> ppr calls,
	 	 ptext (sLit "fvs")   <+> equals <+> ppr fvs]))

type DictBind = (CoreBind, VarSet)
	-- The set is the free vars of the binding
	-- both tyvars and dicts

type DictExpr = CoreExpr

emptyUDs :: UsageDetails
emptyUDs = MkUD { dict_binds = emptyBag, calls = emptyFM, ud_fvs = emptyVarSet }

------------------------------------------------------------			
type CallDetails  = FiniteMap Id CallInfo
newtype CallKey   = CallKey [Maybe Type]			-- Nothing => unconstrained type argument

-- CallInfo uses a FiniteMap, thereby ensuring that
-- we record only one call instance for any key
--
-- The list of types and dictionaries is guaranteed to
-- match the type of f
type CallInfo = FiniteMap CallKey ([DictExpr], VarSet)
     	      		-- Range is dict args and the vars of the whole
			-- call (including tyvars)
			-- [*not* include the main id itself, of course]

instance Outputable CallKey where
  ppr (CallKey ts) = ppr ts

-- Type isn't an instance of Ord, so that we can control which
-- instance we use.  That's tiresome here.  Oh well
instance Eq CallKey where
  k1 == k2 = case k1 `compare` k2 of { EQ -> True; _ -> False }

instance Ord CallKey where
  compare (CallKey k1) (CallKey k2) = cmpList cmp k1 k2
		where
		  cmp Nothing   Nothing   = EQ
		  cmp Nothing   (Just _)  = LT
		  cmp (Just _)  Nothing   = GT
		  cmp (Just t1) (Just t2) = tcCmpType t1 t2

unionCalls :: CallDetails -> CallDetails -> CallDetails
unionCalls c1 c2 = plusFM_C plusFM c1 c2

singleCall :: Id -> [Maybe Type] -> [DictExpr] -> UsageDetails
singleCall id tys dicts 
  = MkUD {dict_binds = emptyBag, 
	  calls      = unitFM id (unitFM (CallKey tys) (dicts, call_fvs)),
	  ud_fvs     = call_fvs }
  where
    call_fvs = exprsFreeVars dicts `unionVarSet` tys_fvs
    tys_fvs  = tyVarsOfTypes (catMaybes tys)
	-- The type args (tys) are guaranteed to be part of the dictionary
	-- types, because they are just the constrained types,
	-- and the dictionary is therefore sure to be bound
	-- inside the binding for any type variables free in the type;
	-- hence it's safe to neglect tyvars free in tys when making
	-- the free-var set for this call
	-- BUT I don't trust this reasoning; play safe and include tys_fvs
	--
	-- We don't include the 'id' itself.

mkCallUDs :: Id -> [CoreExpr] -> UsageDetails
mkCallUDs f args 
  | not (isLocalId f)	-- Imported from elsewhere
  || null theta	   	-- Not overloaded
  || not (all isClassPred theta)	
	-- Only specialise if all overloading is on class params. 
	-- In ptic, with implicit params, the type args
	--  *don't* say what the value of the implicit param is!
  || not (spec_tys `lengthIs` n_tyvars)
  || not ( dicts   `lengthIs` n_dicts)
  || not (any interestingArg dicts)	-- Note [Interesting dictionary arguments]
  -- See also Note [Specialisations already covered]
  = -- pprTrace "mkCallUDs: discarding" (vcat [ppr f, ppr args, ppr n_tyvars, ppr n_dicts, ppr (map interestingArg dicts)]) 
    emptyUDs	-- Not overloaded, or no specialisation wanted

  | otherwise
  = -- pprTrace "mkCallUDs: keeping" (vcat [ppr f, ppr args, ppr n_tyvars, ppr n_dicts, ppr (map interestingArg dicts)]) 
    singleCall f spec_tys dicts
  where
    (tyvars, theta, _) = tcSplitSigmaTy (idType f)
    constrained_tyvars = tyVarsOfTheta theta 
    n_tyvars	       = length tyvars
    n_dicts	       = length theta

    spec_tys = [mk_spec_ty tv ty | (tv, Type ty) <- tyvars `zip` args]
    dicts    = [dict_expr | (_, dict_expr) <- theta `zip` (drop n_tyvars args)]
    
    mk_spec_ty tyvar ty 
	| tyvar `elemVarSet` constrained_tyvars = Just ty
	| otherwise				= Nothing
\end{code}

Note [Interesting dictionary arguments]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider this
	 \a.\d:Eq a.  let f = ... in ...(f d)...
There really is not much point in specialising f wrt the dictionary d,
because the code for the specialised f is not improved at all, because
d is lambda-bound.  We simply get junk specialisations.

We re-use the function SimplUtils.interestingArg function to determine
what sort of dictionary arguments have *some* information in them.


\begin{code}
plusUDs :: UsageDetails -> UsageDetails -> UsageDetails
plusUDs (MkUD {dict_binds = db1, calls = calls1, ud_fvs = fvs1})
	(MkUD {dict_binds = db2, calls = calls2, ud_fvs = fvs2})
  = MkUD {dict_binds = d, calls = c, ud_fvs = fvs1 `unionVarSet` fvs2}
  where
    d = db1    `unionBags`   db2 
    c = calls1 `unionCalls`  calls2

plusUDList :: [UsageDetails] -> UsageDetails
plusUDList = foldr plusUDs emptyUDs

-- zapCalls deletes calls to ids from uds
zapCalls :: [Id] -> CallDetails -> CallDetails
zapCalls ids calls = delListFromFM calls ids

mkDB :: CoreBind -> DictBind
mkDB bind = (bind, bind_fvs bind)

bind_fvs :: CoreBind -> VarSet
bind_fvs (NonRec bndr rhs) = pair_fvs (bndr,rhs)
bind_fvs (Rec prs)	   = foldl delVarSet rhs_fvs bndrs
			   where
			     bndrs = map fst prs
			     rhs_fvs = unionVarSets (map pair_fvs prs)

pair_fvs :: (Id, CoreExpr) -> VarSet
pair_fvs (bndr, rhs) = exprFreeVars rhs `unionVarSet` idFreeVars bndr
	-- Don't forget variables mentioned in the
	-- rules of the bndr.  C.f. OccAnal.addRuleUsage
	-- Also tyvars mentioned in its type; they may not appear in the RHS
	--	type T a = Int
	--	x :: T a = 3

addDictBind :: (Id,CoreExpr) -> UsageDetails -> UsageDetails
addDictBind (dict,rhs) uds 
  = uds { dict_binds = db `consBag` dict_binds uds
	, ud_fvs = ud_fvs uds `unionVarSet` fvs }
  where
    db@(_, fvs) = mkDB (NonRec dict rhs) 

dumpAllDictBinds :: UsageDetails -> [CoreBind] -> [CoreBind]
dumpAllDictBinds (MkUD {dict_binds = dbs}) binds
  = foldrBag add binds dbs
  where
    add (bind,_) binds = bind : binds

dumpUDs :: [CoreBndr]
	-> UsageDetails -> CoreExpr
	-> (UsageDetails, CoreExpr)
dumpUDs bndrs (MkUD { dict_binds = orig_dbs
		    , calls = orig_calls
		    , ud_fvs = fvs}) body
  = (new_uds, foldrBag add_let body dump_dbs)		
		-- This may delete fewer variables 
		-- than in priciple possible
  where
    new_uds = 
     MkUD { dict_binds = free_dbs
	  , calls      = free_calls 
	  , ud_fvs     = fvs `minusVarSet` bndr_set}

    bndr_set = mkVarSet bndrs
    add_let (bind,_) body = Let bind body

    (free_dbs, dump_dbs, dump_set) 
	= foldlBag dump_db (emptyBag, emptyBag, bndr_set) orig_dbs
		-- Important that it's foldl not foldr;
		-- we're accumulating the set of dumped ids in dump_set

    free_calls = filterCalls dump_set orig_calls

    dump_db (free_dbs, dump_dbs, dump_idset) db@(bind, fvs)
	| dump_idset `intersectsVarSet` fvs	-- Dump it
	= (free_dbs, dump_dbs `snocBag` db,
	   extendVarSetList dump_idset (bindersOf bind))

	| otherwise	-- Don't dump it
	= (free_dbs `snocBag` db, dump_dbs, dump_idset)

filterCalls :: VarSet -> CallDetails -> CallDetails
-- Remove any calls that mention the variables
filterCalls bs calls
  = mapFM (\_ cs -> filter_calls cs) $
    filterFM (\k _ -> not (k `elemVarSet` bs)) calls
  where
    filter_calls :: CallInfo -> CallInfo
    filter_calls = filterFM (\_ (_, fvs) -> not (fvs `intersectsVarSet` bs))
\end{code}


%************************************************************************
%*									*
\subsubsection{Boring helper functions}
%*									*
%************************************************************************

\begin{code}
type SpecM a = UniqSM a

initSM :: UniqSupply -> SpecM a -> a
initSM	  = initUs_

mapAndCombineSM :: (a -> SpecM (b, UsageDetails)) -> [a] -> SpecM ([b], UsageDetails)
mapAndCombineSM _ []     = return ([], emptyUDs)
mapAndCombineSM f (x:xs) = do (y, uds1) <- f x
                              (ys, uds2) <- mapAndCombineSM f xs
                              return (y:ys, uds1 `plusUDs` uds2)

cloneBindSM :: Subst -> CoreBind -> SpecM (Subst, Subst, CoreBind)
-- Clone the binders of the bind; return new bind with the cloned binders
-- Return the substitution to use for RHSs, and the one to use for the body
cloneBindSM subst (NonRec bndr rhs) = do
    us <- getUniqueSupplyM
    let (subst', bndr') = cloneIdBndr subst us bndr
    return (subst, subst', NonRec bndr' rhs)

cloneBindSM subst (Rec pairs) = do
    us <- getUniqueSupplyM
    let (subst', bndrs') = cloneRecIdBndrs subst us (map fst pairs)
    return (subst', subst', Rec (bndrs' `zip` map snd pairs))

cloneDictBndrs :: Subst -> [CoreBndr] -> SpecM (Subst, [CoreBndr])
cloneDictBndrs subst bndrs 
  = do { us <- getUniqueSupplyM
       ; return (cloneIdBndrs subst us bndrs) }

newSpecIdSM :: Id -> Type -> SpecM Id
    -- Give the new Id a similar occurrence name to the old one
newSpecIdSM old_id new_ty
  = do	{ uniq <- getUniqueM
    	; let 
	    name    = idName old_id
	    new_occ = mkSpecOcc (nameOccName name)
	    new_id  = mkUserLocal new_occ uniq new_ty (getSrcSpan name)
        ; return new_id }
\end{code}


		Old (but interesting) stuff about unboxed bindings
		~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

What should we do when a value is specialised to a *strict* unboxed value?

	map_*_* f (x:xs) = let h = f x
			       t = map f xs
			   in h:t

Could convert let to case:

	map_*_Int# f (x:xs) = case f x of h# ->
			      let t = map f xs
			      in h#:t

This may be undesirable since it forces evaluation here, but the value
may not be used in all branches of the body. In the general case this
transformation is impossible since the mutual recursion in a letrec
cannot be expressed as a case.

There is also a problem with top-level unboxed values, since our
implementation cannot handle unboxed values at the top level.

Solution: Lift the binding of the unboxed value and extract it when it
is used:

	map_*_Int# f (x:xs) = let h = case (f x) of h# -> _Lift h#
				  t = map f xs
			      in case h of
				 _Lift h# -> h#:t

Now give it to the simplifier and the _Lifting will be optimised away.

The benfit is that we have given the specialised "unboxed" values a
very simplep lifted semantics and then leave it up to the simplifier to
optimise it --- knowing that the overheads will be removed in nearly
all cases.

In particular, the value will only be evaluted in the branches of the
program which use it, rather than being forced at the point where the
value is bound. For example:

	filtermap_*_* p f (x:xs)
	  = let h = f x
		t = ...
	    in case p x of
		True  -> h:t
		False -> t
   ==>
	filtermap_*_Int# p f (x:xs)
	  = let h = case (f x) of h# -> _Lift h#
		t = ...
	    in case p x of
		True  -> case h of _Lift h#
			   -> h#:t
		False -> t

The binding for h can still be inlined in the one branch and the
_Lifting eliminated.


Question: When won't the _Lifting be eliminated?

Answer: When they at the top-level (where it is necessary) or when
inlining would duplicate work (or possibly code depending on
options). However, the _Lifting will still be eliminated if the
strictness analyser deems the lifted binding strict.
