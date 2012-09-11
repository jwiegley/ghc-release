%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%
\section[FloatOut]{Float bindings outwards (towards the top level)}

``Long-distance'' floating of bindings towards the top level.

\begin{code}
module FloatOut ( floatOutwards ) where

import CoreSyn
import CoreUtils

import DynFlags	( DynFlags, DynFlag(..), FloatOutSwitches(..) )
import ErrUtils		( dumpIfSet_dyn )
import CostCentre	( dupifyCC, CostCentre )
import Id		( Id, idType )
import Type		( isUnLiftedType )
import SetLevels	( Level(..), LevelledExpr, LevelledBind,
			  setLevels, isTopLvl, tOP_LEVEL )
import UniqSupply       ( UniqSupply )
import Bag
import Util
import Maybes
import UniqFM
import Outputable
import FastString
\end{code}

	-----------------
	Overall game plan
	-----------------

The Big Main Idea is:

  	To float out sub-expressions that can thereby get outside
	a non-one-shot value lambda, and hence may be shared.


To achieve this we may need to do two thing:

   a) Let-bind the sub-expression:

	f (g x)  ==>  let lvl = f (g x) in lvl

      Now we can float the binding for 'lvl'.  

   b) More than that, we may need to abstract wrt a type variable

	\x -> ... /\a -> let v = ...a... in ....

      Here the binding for v mentions 'a' but not 'x'.  So we
      abstract wrt 'a', to give this binding for 'v':

	    vp = /\a -> ...a...
	    v  = vp a

      Now the binding for vp can float out unimpeded.
      I can't remember why this case seemed important enough to
      deal with, but I certainly found cases where important floats
      didn't happen if we did not abstract wrt tyvars.

With this in mind we can also achieve another goal: lambda lifting.
We can make an arbitrary (function) binding float to top level by
abstracting wrt *all* local variables, not just type variables, leaving
a binding that can be floated right to top level.  Whether or not this
happens is controlled by a flag.


Random comments
~~~~~~~~~~~~~~~

At the moment we never float a binding out to between two adjacent
lambdas.  For example:

@
	\x y -> let t = x+x in ...
===>
	\x -> let t = x+x in \y -> ...
@
Reason: this is less efficient in the case where the original lambda
is never partially applied.

But there's a case I've seen where this might not be true.  Consider:
@
elEm2 x ys
  = elem' x ys
  where
    elem' _ []	= False
    elem' x (y:ys)	= x==y || elem' x ys
@
It turns out that this generates a subexpression of the form
@
	\deq x ys -> let eq = eqFromEqDict deq in ...
@
vwhich might usefully be separated to
@
	\deq -> let eq = eqFromEqDict deq in \xy -> ...
@
Well, maybe.  We don't do this at the moment.


%************************************************************************
%*									*
\subsection[floatOutwards]{@floatOutwards@: let-floating interface function}
%*									*
%************************************************************************

\begin{code}
floatOutwards :: FloatOutSwitches
	      -> DynFlags
	      -> UniqSupply 
	      -> [CoreBind] -> IO [CoreBind]

floatOutwards float_sws dflags us pgm
  = do {
	let { annotated_w_levels = setLevels float_sws pgm us ;
	      (fss, binds_s')    = unzip (map floatTopBind annotated_w_levels)
	    } ;

	dumpIfSet_dyn dflags Opt_D_verbose_core2core "Levels added:"
	          (vcat (map ppr annotated_w_levels));

	let { (tlets, ntlets, lams) = get_stats (sum_stats fss) };

	dumpIfSet_dyn dflags Opt_D_dump_simpl_stats "FloatOut stats:"
		(hcat [	int tlets,  ptext (sLit " Lets floated to top level; "),
			int ntlets, ptext (sLit " Lets floated elsewhere; from "),
			int lams,   ptext (sLit " Lambda groups")]);

	return (concat binds_s')
    }

floatTopBind :: LevelledBind -> (FloatStats, [CoreBind])
floatTopBind bind
  = case (floatBind bind) of { (fs, floats) ->
    (fs, bagToList (flattenFloats floats))
    }
\end{code}

%************************************************************************
%*									*
\subsection[FloatOut-Bind]{Floating in a binding (the business end)}
%*									*
%************************************************************************


\begin{code}
floatBind :: LevelledBind -> (FloatStats, FloatBinds)

floatBind (NonRec (TB name level) rhs)
  = case (floatRhs level rhs) of { (fs, rhs_floats, rhs') ->
    (fs, rhs_floats `plusFloats` unitFloat level (NonRec name rhs')) }

floatBind bind@(Rec pairs)
  = case (unzip3 (map do_pair pairs)) of { (fss, rhss_floats, new_pairs) ->
    let rhs_floats = foldr1 plusFloats rhss_floats in

    if not (isTopLvl bind_dest_lvl) then
	-- Find which bindings float out at least one lambda beyond this one
	-- These ones can't mention the binders, because they couldn't 
	-- be escaping a major level if so.
	-- The ones that are not going further can join the letrec;
	-- they may not be mutually recursive but the occurrence analyser will
	-- find that out.
	case (partitionByMajorLevel bind_dest_lvl rhs_floats) of { (floats', heres) ->
	(sum_stats fss,
      floats' `plusFloats` unitFloat bind_dest_lvl
                            (Rec (floatsToBindPairs heres new_pairs))) }
    else
	-- In a recursive binding, *destined for* the top level
	-- (only), the rhs floats may contain references to the 
	-- bound things.  For example
	--	f = ...(let v = ...f... in b) ...
	--  might get floated to
	--	v = ...f...
	--	f = ... b ...
	-- and hence we must (pessimistically) make all the floats recursive
	-- with the top binding.  Later dependency analysis will unravel it.
	--
	-- This can only happen for bindings destined for the top level,
	-- because only then will partitionByMajorLevel allow through a binding
	-- that only differs in its minor level
	(sum_stats fss, unitFloat tOP_LEVEL
                       (Rec (floatsToBindPairs (flattenFloats rhs_floats) new_pairs)))
    }
  where
    bind_dest_lvl = getBindLevel bind

    do_pair (TB name level, rhs)
      = case (floatRhs level rhs) of { (fs, rhs_floats, rhs') ->
	(fs, rhs_floats, (name, rhs'))
	}
\end{code}

%************************************************************************

\subsection[FloatOut-Expr]{Floating in expressions}
%*									*
%************************************************************************

\begin{code}
floatExpr, floatRhs, floatCaseAlt
	 :: Level
	 -> LevelledExpr
	 -> (FloatStats, FloatBinds, CoreExpr)

floatCaseAlt lvl arg	-- Used rec rhss, and case-alternative rhss
  = case (floatExpr lvl arg) of { (fsa, floats, arg') ->
    case (partitionByMajorLevel lvl floats) of { (floats', heres) ->
	-- Dump bindings that aren't going to escape from a lambda;
	-- in particular, we must dump the ones that are bound by 
	-- the rec or case alternative
    (fsa, floats', install heres arg') }}

floatRhs lvl arg	-- Used for nested non-rec rhss, and fn args
			-- See Note [Floating out of RHS]
  = case (floatExpr lvl arg) of { (fsa, floats, arg') ->
    if exprIsCheap arg' then	
	(fsa, floats, arg')
    else
    case (partitionByMajorLevel lvl floats) of { (floats', heres) ->
    (fsa, floats', install heres arg') }}

-- Note [Floating out of RHSs]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Dump bindings that aren't going to escape from a lambda
-- This isn't a scoping issue (the binder isn't in scope in the RHS 
--	of a non-rec binding)
-- Rather, it is to avoid floating the x binding out of
--	f (let x = e in b)
-- unnecessarily.  But we first test for values or trival rhss,
-- because (in particular) we don't want to insert new bindings between
-- the "=" and the "\".  E.g.
--	f = \x -> let <bind> in <body>
-- We do not want
--	f = let <bind> in \x -> <body>
-- (a) The simplifier will immediately float it further out, so we may
--	as well do so right now; in general, keeping rhss as manifest 
--	values is good
-- (b) If a float-in pass follows immediately, it might add yet more
--	bindings just after the '='.  And some of them might (correctly)
--	be strict even though the 'let f' is lazy, because f, being a value,
--	gets its demand-info zapped by the simplifier.
--
-- We use exprIsCheap because that is also what's used by the simplifier
-- to decide whether to float a let out of a let

floatExpr _ (Var v)   = (zeroStats, emptyFloats, Var v)
floatExpr _ (Type ty) = (zeroStats, emptyFloats, Type ty)
floatExpr _ (Lit lit) = (zeroStats, emptyFloats, Lit lit)
	  
floatExpr lvl (App e a)
  = case (floatExpr      lvl e) of { (fse, floats_e, e') ->
    case (floatRhs lvl a) 	of { (fsa, floats_a, a') ->
    (fse `add_stats` fsa, floats_e `plusFloats` floats_a, App e' a') }}

floatExpr _ lam@(Lam _ _)
  = let
	(bndrs_w_lvls, body) = collectBinders lam
	bndrs		     = [b | TB b _ <- bndrs_w_lvls]
	lvls		     = [l | TB _ l <- bndrs_w_lvls]

	-- For the all-tyvar case we are prepared to pull 
	-- the lets out, to implement the float-out-of-big-lambda
	-- transform; but otherwise we only float bindings that are
	-- going to escape a value lambda.
	-- In particular, for one-shot lambdas we don't float things
	-- out; we get no saving by so doing.
	partition_fn | all isTyVar bndrs = partitionByLevel
		     | otherwise	 = partitionByMajorLevel
    in
    case (floatExpr (last lvls) body) of { (fs, floats, body') ->

	-- Dump any bindings which absolutely cannot go any further
    case (partition_fn (head lvls) floats)	of { (floats', heres) ->

    (add_to_stats fs floats', floats', mkLams bndrs (install heres body'))
    }}

floatExpr lvl (Note note@(SCC cc) expr)
  = case (floatExpr lvl expr)    of { (fs, floating_defns, expr') ->
    let
	-- Annotate bindings floated outwards past an scc expression
	-- with the cc.  We mark that cc as "duplicated", though.

	annotated_defns = wrapCostCentre (dupifyCC cc) floating_defns
    in
    (fs, annotated_defns, Note note expr') }

floatExpr _ (Note InlineMe expr)	-- Other than SCCs
  = (zeroStats, emptyFloats, Note InlineMe (unTag expr))
	-- Do no floating at all inside INLINE.
	-- The SetLevels pass did not clone the bindings, so it's
	-- unsafe to do any floating, even if we dump the results
	-- inside the Note (which is what we used to do).

floatExpr lvl (Note note expr)	-- Other than SCCs
  = case (floatExpr lvl expr)    of { (fs, floating_defns, expr') ->
    (fs, floating_defns, Note note expr') }

floatExpr lvl (Cast expr co)
  = case (floatExpr lvl expr)	of { (fs, floating_defns, expr') ->
    (fs, floating_defns, Cast expr' co) }

floatExpr lvl (Let (NonRec (TB bndr bndr_lvl) rhs) body)
  | isUnLiftedType (idType bndr)	-- Treat unlifted lets just like a case
				-- I.e. floatExpr for rhs, floatCaseAlt for body
  = case floatExpr lvl rhs	    of { (_, rhs_floats, rhs') ->
    case floatCaseAlt bndr_lvl body of { (fs, body_floats, body') ->
    (fs, rhs_floats `plusFloats` body_floats, Let (NonRec bndr rhs') body') }}

floatExpr lvl (Let bind body)
  = case (floatBind bind)     of { (fsb, bind_floats) ->
    case (floatExpr lvl body) of { (fse, body_floats, body') ->
    (add_stats fsb fse,
     bind_floats `plusFloats` body_floats,
     body')  }}

floatExpr lvl (Case scrut (TB case_bndr case_lvl) ty alts)
  = case floatExpr lvl scrut	of { (fse, fde, scrut') ->
    case floatList float_alt alts	of { (fsa, fda, alts')  ->
    (add_stats fse fsa, fda `plusFloats` fde, Case scrut' case_bndr ty alts')
    }}
  where
	-- Use floatCaseAlt for the alternatives, so that we
	-- don't gratuitiously float bindings out of the RHSs
    float_alt (con, bs, rhs)
	= case (floatCaseAlt case_lvl rhs)	of { (fs, rhs_floats, rhs') ->
	  (fs, rhs_floats, (con, [b | TB b _ <- bs], rhs')) }


floatList :: (a -> (FloatStats, FloatBinds, b)) -> [a] -> (FloatStats, FloatBinds, [b])
floatList _ [] = (zeroStats, emptyFloats, [])
floatList f (a:as) = case f a		 of { (fs_a,  binds_a,  b)  ->
		     case floatList f as of { (fs_as, binds_as, bs) ->
		     (fs_a `add_stats` fs_as, binds_a `plusFloats` binds_as, b:bs) }}

getBindLevel :: Bind (TaggedBndr Level) -> Level
getBindLevel (NonRec (TB _ lvl) _)       = lvl
getBindLevel (Rec (((TB _ lvl), _) : _)) = lvl
getBindLevel (Rec [])                    = panic "getBindLevel Rec []"

unTagBndr :: TaggedBndr tag -> CoreBndr
unTagBndr (TB b _) = b

unTag :: TaggedExpr tag -> CoreExpr
unTag (Var v)  	  = Var v
unTag (Lit l)  	  = Lit l
unTag (Type ty)   = Type ty
unTag (Note n e)  = Note n (unTag e)
unTag (App e1 e2) = App (unTag e1) (unTag e2)
unTag (Lam b e)   = Lam (unTagBndr b) (unTag e)
unTag (Cast e co) = Cast (unTag e) co
unTag (Let (Rec prs) e)    = Let (Rec [(unTagBndr b,unTag r) | (b, r) <- prs]) (unTag e)
unTag (Let (NonRec b r) e) = Let (NonRec (unTagBndr b) (unTag r)) (unTag e)
unTag (Case e b ty alts)   = Case (unTag e) (unTagBndr b) ty
			          [(c, map unTagBndr bs, unTag r) | (c,bs,r) <- alts]
\end{code}

%************************************************************************
%*									*
\subsection{Utility bits for floating stats}
%*									*
%************************************************************************

I didn't implement this with unboxed numbers.  I don't want to be too
strict in this stuff, as it is rarely turned on.  (WDP 95/09)

\begin{code}
data FloatStats
  = FlS	Int  -- Number of top-floats * lambda groups they've been past
	Int  -- Number of non-top-floats * lambda groups they've been past
	Int  -- Number of lambda (groups) seen

get_stats :: FloatStats -> (Int, Int, Int)
get_stats (FlS a b c) = (a, b, c)

zeroStats :: FloatStats
zeroStats = FlS 0 0 0

sum_stats :: [FloatStats] -> FloatStats
sum_stats xs = foldr add_stats zeroStats xs

add_stats :: FloatStats -> FloatStats -> FloatStats
add_stats (FlS a1 b1 c1) (FlS a2 b2 c2)
  = FlS (a1 + a2) (b1 + b2) (c1 + c2)

add_to_stats :: FloatStats -> FloatBinds -> FloatStats
add_to_stats (FlS a b c) (FB tops others)
  = FlS (a + lengthBag tops) (b + lengthBag (flattenMajor others)) (c + 1)
\end{code}


%************************************************************************
%*									*
\subsection{Utility bits for floating}
%*									*
%************************************************************************

Note [Representation of FloatBinds]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The FloatBinds types is somewhat important.  We can get very large numbers
of floating bindings, often all destined for the top level.  A typical example
is     x = [4,2,5,2,5, .... ]
Then we get lots of small expressions like (fromInteger 4), which all get
lifted to top level.

The trouble is that
  (a) we partition these floating bindings *at every binding site*
  (b) SetLevels introduces a new bindings site for every float
So we had better not look at each binding at each binding site!

That is why MajorEnv is represented as a finite map.

We keep the bindings destined for the *top* level separate, because
we float them out even if they don't escape a *value* lambda; see
partitionByMajorLevel.

\begin{code}
type FloatBind = CoreBind      -- INVARIANT: a FloatBind is always lifted

data FloatBinds  = FB !(Bag FloatBind)         -- Destined for top level
                     !MajorEnv                 -- Levels other than top
     -- See Note [Representation of FloatBinds]

type MajorEnv = UniqFM MinorEnv                        -- Keyed by major level
type MinorEnv = UniqFM (Bag FloatBind)         -- Keyed by minor level

flattenFloats :: FloatBinds -> Bag FloatBind
flattenFloats (FB tops others) = tops `unionBags` flattenMajor others

flattenMajor :: MajorEnv -> Bag FloatBind
flattenMajor = foldUFM (unionBags . flattenMinor) emptyBag

flattenMinor :: MinorEnv -> Bag FloatBind
flattenMinor = foldUFM unionBags emptyBag

emptyFloats :: FloatBinds
emptyFloats = FB emptyBag emptyUFM

unitFloat :: Level -> FloatBind -> FloatBinds
unitFloat InlineCtxt b = FB (unitBag b) emptyUFM
unitFloat lvl@(Level major minor) b
  | isTopLvl lvl = FB (unitBag b) emptyUFM
  | otherwise    = FB emptyBag (unitUFM major (unitUFM minor (unitBag b)))

plusFloats :: FloatBinds -> FloatBinds -> FloatBinds
plusFloats (FB t1 b1) (FB t2 b2) = FB (t1 `unionBags` t2) (b1 `plusMajor` b2)

plusMajor :: MajorEnv -> MajorEnv -> MajorEnv
plusMajor = plusUFM_C plusMinor

plusMinor :: MinorEnv -> MinorEnv -> MinorEnv
plusMinor = plusUFM_C unionBags

floatsToBindPairs :: Bag FloatBind -> [(Id,CoreExpr)] -> [(Id,CoreExpr)]
floatsToBindPairs floats binds = foldrBag add binds floats
  where
   add (Rec pairs)         binds = pairs ++ binds
   add (NonRec binder rhs) binds = (binder,rhs) : binds

install :: Bag FloatBind -> CoreExpr -> CoreExpr
install defn_groups expr
  = foldrBag install_group expr defn_groups
  where
    install_group defns body = Let defns body

partitionByMajorLevel, partitionByLevel
       :: Level                -- Partitioning level
       -> FloatBinds           -- Defns to be divided into 2 piles...
       -> (FloatBinds,         -- Defns  with level strictly < partition level,
           Bag FloatBind)      -- The rest

--      ---- partitionByMajorLevel ----
-- Float it if we escape a value lambda, *or* if we get to the top level
-- If we can get to the top level, say "yes" anyway. This means that
--     x = f e
-- transforms to
--    lvl = e
--    x = f lvl
-- which is as it should be

partitionByMajorLevel InlineCtxt (FB tops defns)
  = (FB tops emptyUFM, flattenMajor defns)

partitionByMajorLevel (Level major _) (FB tops defns)
  = (FB tops outer, heres `unionBags` flattenMajor inner)
  where
    (outer, mb_heres, inner) = splitUFM defns major
    heres = case mb_heres of
               Nothing -> emptyBag
               Just h  -> flattenMinor h

partitionByLevel InlineCtxt (FB tops defns)
  = (FB tops emptyUFM, flattenMajor defns)

partitionByLevel (Level major minor) (FB tops defns)
  = (FB tops (outer_maj `plusMajor` unitUFM major outer_min),
     here_min `unionBags` flattenMinor inner_min
              `unionBags` flattenMajor inner_maj)

  where
    (outer_maj, mb_here_maj, inner_maj) = splitUFM defns major
    (outer_min, mb_here_min, inner_min) = case mb_here_maj of
                                            Nothing -> (emptyUFM, Nothing, emptyUFM)
                                            Just min_defns -> splitUFM min_defns minor
    here_min = mb_here_min `orElse` emptyBag

wrapCostCentre :: CostCentre -> FloatBinds -> FloatBinds
wrapCostCentre cc (FB tops defns)
  = FB (wrap_defns tops) (mapUFM (mapUFM wrap_defns) defns)
  where
    wrap_defns = mapBag wrap_one
    wrap_one (NonRec binder rhs) = NonRec binder (mkSCC cc rhs)
    wrap_one (Rec pairs)         = Rec (mapSnd (mkSCC cc) pairs)
\end{code}

