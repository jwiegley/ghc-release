%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

\begin{code}

-- | CoreSyn holds all the main data types for use by for the Glasgow Haskell Compiler midsection
module CoreSyn (
	-- * Main data types
	Expr(..), Alt, Bind(..), AltCon(..), Arg, Note(..),
	CoreExpr, CoreAlt, CoreBind, CoreArg, CoreBndr,
	TaggedExpr, TaggedAlt, TaggedBind, TaggedArg, TaggedBndr(..),

        -- ** 'Expr' construction
	mkLets, mkLams,
	mkApps, mkTyApps, mkVarApps,
	
	mkIntLit, mkIntLitInt,
	mkWordLit, mkWordLitWord,
	mkCharLit, mkStringLit,
	mkFloatLit, mkFloatLitFloat,
	mkDoubleLit, mkDoubleLitDouble,
	
	mkConApp, mkTyBind,
	varToCoreExpr, varsToCoreExprs,

        isTyVar, isIdVar, cmpAltCon, cmpAlt, ltAlt,
	
	-- ** Simple 'Expr' access functions and predicates
	bindersOf, bindersOfBinds, rhssOfBind, rhssOfAlts, 
	collectBinders, collectTyBinders, collectValBinders, collectTyAndValBinders,
	collectArgs, coreExprCc, flattenBinds, 

	isValArg, isTypeArg, valArgCount, valBndrCount, isRuntimeArg, isRuntimeVar,

	-- * Unfolding data types
	Unfolding(..),	UnfoldingGuidance(..), 	-- Both abstract everywhere but in CoreUnfold.lhs
	
	-- ** Constructing 'Unfolding's
	noUnfolding, evaldUnfolding, mkOtherCon,
	
	-- ** Predicates and deconstruction on 'Unfolding'
	unfoldingTemplate, maybeUnfoldingTemplate, otherCons, 
	isValueUnfolding, isEvaldUnfolding, isCheapUnfolding, isCompulsoryUnfolding,
	hasUnfolding, hasSomeUnfolding, neverUnfold,

	-- * Strictness
	seqExpr, seqExprs, seqUnfolding, 

	-- * Annotated expression data types
	AnnExpr, AnnExpr'(..), AnnBind(..), AnnAlt,
	
	-- ** Operations on annotations
	deAnnotate, deAnnotate', deAnnAlt, collectAnnBndrs,

	-- * Core rule data types
	CoreRule(..),	-- CoreSubst, CoreTidy, CoreFVs, PprCore only
	RuleName, 
	
	-- ** Operations on 'CoreRule's 
	seqRules, ruleArity, ruleName, ruleIdName, ruleActivation_maybe,
	setRuleIdName,
	isBuiltinRule, isLocalRule
    ) where

#include "HsVersions.h"

import CostCentre
import Var
import Type
import Coercion
import Name
import Literal
import DataCon
import BasicTypes
import FastString
import Outputable
import Util

import Data.Word

infixl 4 `mkApps`, `mkTyApps`, `mkVarApps`
-- Left associative, so that we can say (f `mkTyApps` xs `mkVarApps` ys)
\end{code}

%************************************************************************
%*									*
\subsection{The main data types}
%*									*
%************************************************************************

These data types are the heart of the compiler

\begin{code}
infixl 8 `App`	-- App brackets to the left

-- | This is the data type that represents GHCs core intermediate language. Currently
-- GHC uses System FC <http://research.microsoft.com/~simonpj/papers/ext-f/> for this purpose,
-- which is closely related to the simpler and better known System F <http://en.wikipedia.org/wiki/System_F>.
--
-- We get from Haskell source to this Core language in a number of stages:
--
-- 1. The source code is parsed into an abstract syntax tree, which is represented
--    by the data type 'HsExpr.HsExpr' with the names being 'RdrName.RdrNames'
--
-- 2. This syntax tree is /renamed/, which attaches a 'Unique.Unique' to every 'RdrName.RdrName'
--    (yielding a 'Name.Name') to disambiguate identifiers which are lexically identical. 
--    For example, this program:
--
-- @
--      f x = let f x = x + 1
--            in f (x - 2)
-- @
--
--    Would be renamed by having 'Unique's attached so it looked something like this:
--
-- @
--      f_1 x_2 = let f_3 x_4 = x_4 + 1
--                in f_3 (x_2 - 2)
-- @
--
-- 3. The resulting syntax tree undergoes type checking (which also deals with instantiating
--    type class arguments) to yield a 'HsExpr.HsExpr' type that has 'Id.Id' as it's names.
--
-- 4. Finally the syntax tree is /desugared/ from the expressive 'HsExpr.HsExpr' type into
--    this 'Expr' type, which has far fewer constructors and hence is easier to perform
--    optimization, analysis and code generation on.
--
-- The type parameter @b@ is for the type of binders in the expression tree.
data Expr b
  = Var	  Id                            -- ^ Variables
  | Lit   Literal                       -- ^ Primitive literals
  | App   (Expr b) (Arg b)		-- ^ Applications: note that the argument may be a 'Type'.
                                        --
                                        -- See "CoreSyn#let_app_invariant" for another invariant
  | Lam   b (Expr b)                    -- ^ Lambda abstraction
  | Let   (Bind b) (Expr b)		-- ^ Recursive and non recursive @let@s. Operationally
                                        -- this corresponds to allocating a thunk for the things
                                        -- bound and then executing the sub-expression.
                                        -- 
                                        -- #top_level_invariant#
                                        -- #letrec_invariant#
                                        --
                                        -- The right hand sides of all top-level and recursive @let@s
                                        -- /must/ be of lifted type (see "Type#type_classification" for
                                        -- the meaning of /lifted/ vs. /unlifted/).
                                        --
                                        -- #let_app_invariant#
                                        -- The right hand side of of a non-recursive 'Let' _and_ the argument of an 'App',
                                        -- /may/ be of unlifted type, but only if the expression 
                                        -- is ok-for-speculation.  This means that the let can be floated around 
                                        -- without difficulty. For example, this is OK:
                                        --
	                                -- > y::Int# = x +# 1#
	                                --
	                                -- But this is not, as it may affect termination if the expression is floated out:
	                                --
	                                -- > y::Int# = fac 4#
	                                --
	                                -- In this situation you should use @case@ rather than a @let@. The function
	                                -- 'CoreUtils.needsCaseBinding' can help you determine which to generate, or
	                                -- alternatively use 'MkCore.mkCoreLet' rather than this constructor directly,
	                                -- which will generate a @case@ if necessary
	                                --
	                                -- #type_let#
	                                -- We allow a /non-recursive/ let to bind a type variable, thus:
	                                --
	                                -- > Let (NonRec tv (Type ty)) body
	                                --
	                                -- This can be very convenient for postponing type substitutions until
                                        -- the next run of the simplifier.
                                        --
                                        -- At the moment, the rest of the compiler only deals with type-let
                                        -- in a Let expression, rather than at top level.  We may want to revist
                                        -- this choice.
  | Case  (Expr b) b Type [Alt b]  	-- ^ Case split. Operationally this corresponds to evaluating
                                        -- the scrutinee (expression examined) to weak head normal form
                                        -- and then examining at most one level of resulting constructor (i.e. you
                                        -- cannot do nested pattern matching directly with this).
                                        --
                                        -- The binder gets bound to the value of the scrutinee,
                                        -- and the 'Type' must be that of all the case alternatives
					--
					-- #case_invariants#
					-- This is one of the more complicated elements of the Core language, and comes
					-- with a number of restrictions:
					--
					-- The 'DEFAULT' case alternative must be first in the list, if it occurs at all.
					--
					-- The remaining cases are in order of increasing 
		                        --      tag	(for 'DataAlts') or
		                        --      lit	(for 'LitAlts').
	                                -- This makes finding the relevant constructor easy, and makes comparison easier too.
					--
					-- The list of alternatives must be exhaustive. An /exhaustive/ case 
					-- does not necessarily mention all constructors:
					--
					-- @
                                        --      data Foo = Red | Green | Blue
                                        -- ... case x of 
                                        --      Red   -> True
                                        --      other -> f (case x of 
                                        --                      Green -> ...
                                        --                      Blue  -> ... ) ...
                                        -- @
                                        --
                                        -- The inner case does not need a @Red@ alternative, because @x@ can't be @Red@ at
                                        -- that program point.
  | Cast  (Expr b) Coercion             -- ^ Cast an expression to a particular type. This is used to implement @newtype@s
                                        -- (a @newtype@ constructor or destructor just becomes a 'Cast' in Core) and GADTs.
  | Note  Note (Expr b)                 -- ^ Notes. These allow general information to be
                                        -- added to expressions in the syntax tree
  | Type  Type			        -- ^ A type: this should only show up at the top
                                        -- level of an Arg

-- | Type synonym for expressions that occur in function argument positions.
-- Only 'Arg' should contain a 'Type' at top level, general 'Expr' should not
type Arg b = Expr b

-- | A case split alternative. Consists of the constructor leading to the alternative,
-- the variables bound from the constructor, and the expression to be executed given that binding.
-- The default alternative is @(DEFAULT, [], rhs)@
type Alt b = (AltCon, [b], Expr b)

-- | A case alternative constructor (i.e. pattern match)
data AltCon = DataAlt DataCon	-- ^ A plain data constructor: @case e of { Foo x -> ... }@.
                                -- Invariant: the 'DataCon' is always from a @data@ type, and never from a @newtype@
	    | LitAlt  Literal   -- ^ A literal: @case e of { 1 -> ... }@
	    | DEFAULT           -- ^ Trivial alternative: @case e of { _ -> ... }@
	 deriving (Eq, Ord)

-- | Binding, used for top level bindings in a module and local bindings in a @let@.
data Bind b = NonRec b (Expr b)
	    | Rec [(b, (Expr b))]
\end{code}

-------------------------- CoreSyn INVARIANTS ---------------------------

Note [CoreSyn top-level invariant]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
See #toplevel_invariant#

Note [CoreSyn letrec invariant]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
See #letrec_invariant#

Note [CoreSyn let/app invariant]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
See #let_app_invariant#

This is intially enforced by DsUtils.mkCoreLet and mkCoreApp

Note [CoreSyn case invariants]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
See #case_invariants#

Note [CoreSyn let goal]
~~~~~~~~~~~~~~~~~~~~~~~
* The simplifier tries to ensure that if the RHS of a let is a constructor
  application, its arguments are trivial, so that the constructor can be
  inlined vigorously.


Note [Type let]
~~~~~~~~~~~~~~~
See #type_let#

\begin{code}

-- | Allows attaching extra information to points in expressions rather than e.g. identifiers.
data Note
  = SCC CostCentre      -- ^ A cost centre annotation for profiling

  | InlineMe		-- ^ Instructs the core simplifer to treat the enclosed expression
			-- as very small, and inline it at its call sites

  | CoreNote String     -- ^ A generic core annotation, propagated but not used by GHC

-- NOTE: we also treat expressions wrapped in InlineMe as
-- 'cheap' and 'dupable' (in the sense of exprIsCheap, exprIsDupable)
-- What this means is that we obediently inline even things that don't
-- look like valuse.  This is sometimes important:
--	{-# INLINE f #-}
--	f = g . h
-- Here, f looks like a redex, and we aren't going to inline (.) because it's
-- inside an INLINE, so it'll stay looking like a redex.  Nevertheless, we 
-- should inline f even inside lambdas.  In effect, we should trust the programmer.
\end{code}


%************************************************************************
%*									*
\subsection{Transformation rules}
%*									*
%************************************************************************

The CoreRule type and its friends are dealt with mainly in CoreRules,
but CoreFVs, Subst, PprCore, CoreTidy also inspect the representation.

\begin{code}
-- | A 'CoreRule' is:
--
-- * \"Local\" if the function it is a rule for is defined in the
--   same module as the rule itself.
--
-- * \"Orphan\" if nothing on the LHS is defined in the same module
--   as the rule itself
data CoreRule
  = Rule { 
	ru_name :: RuleName,            -- ^ Name of the rule, for communication with the user
	ru_act  :: Activation,          -- ^ When the rule is active
	
	-- Rough-matching stuff
	-- see comments with InstEnv.Instance( is_cls, is_rough )
	ru_fn    :: Name,	        -- ^ Name of the 'Id.Id' at the head of this rule
	ru_rough :: [Maybe Name],	-- ^ Name at the head of each argument to the left hand side
	
	-- Proper-matching stuff
	-- see comments with InstEnv.Instance( is_tvs, is_tys )
	ru_bndrs :: [CoreBndr],         -- ^ Variables quantified over
	ru_args  :: [CoreExpr],         -- ^ Left hand side arguments
	
	-- And the right-hand side
	ru_rhs   :: CoreExpr,           -- ^ Right hand side of the rule

	-- Locality
	ru_local :: Bool	-- ^ @True@ iff the fn at the head of the rule is
				-- defined in the same module as the rule
				-- and is not an implicit 'Id' (like a record selector,
				-- class operation, or data constructor)

		-- NB: ru_local is *not* used to decide orphan-hood
		--	c.g. MkIface.coreRuleToIfaceRule
    }

  -- | Built-in rules are used for constant folding
  -- and suchlike.  They have no free variables.
  | BuiltinRule {               
	ru_name :: RuleName,    -- ^ As above
	ru_fn :: Name,          -- ^ As above
	ru_nargs :: Int,	-- ^ Number of arguments that 'ru_try' expects,
				-- including type arguments
	ru_try  :: [CoreExpr] -> Maybe CoreExpr
		-- ^ This function does the rewrite.  It given too many
		-- arguments, it simply discards them; the returned 'CoreExpr'
		-- is just the rewrite of 'ru_fn' applied to the first 'ru_nargs' args
    }
		-- See Note [Extra args in rule matching] in Rules.lhs

isBuiltinRule :: CoreRule -> Bool
isBuiltinRule (BuiltinRule {}) = True
isBuiltinRule _		       = False

-- | The number of arguments the 'ru_fn' must be applied 
-- to before the rule can match on it
ruleArity :: CoreRule -> Int
ruleArity (BuiltinRule {ru_nargs = n}) = n
ruleArity (Rule {ru_args = args})      = length args

ruleName :: CoreRule -> RuleName
ruleName = ru_name

ruleActivation_maybe :: CoreRule -> Maybe Activation
ruleActivation_maybe (BuiltinRule { })       = Nothing
ruleActivation_maybe (Rule { ru_act = act }) = Just act

-- | The 'Name' of the 'Id.Id' at the head of the rule left hand side
ruleIdName :: CoreRule -> Name
ruleIdName = ru_fn

isLocalRule :: CoreRule -> Bool
isLocalRule = ru_local

-- | Set the 'Name' of the 'Id.Id' at the head of the rule left hand side
setRuleIdName :: Name -> CoreRule -> CoreRule
setRuleIdName nm ru = ru { ru_fn = nm }
\end{code}


%************************************************************************
%*									*
		Unfoldings
%*									*
%************************************************************************

The @Unfolding@ type is declared here to avoid numerous loops

\begin{code}
-- | Records the /unfolding/ of an identifier, which is approximately the form the
-- identifier would have if we substituted its definition in for the identifier.
-- This type should be treated as abstract everywhere except in "CoreUnfold"
data Unfolding
  = NoUnfolding                 -- ^ We have no information about the unfolding

  | OtherCon [AltCon]		-- ^ It ain't one of these constructors.
				-- @OtherCon xs@ also indicates that something has been evaluated
				-- and hence there's no point in re-evaluating it.
				-- @OtherCon []@ is used even for non-data-type values
				-- to indicated evaluated-ness.  Notably:
				--
				-- > data C = C !(Int -> Int)
				-- > case x of { C f -> ... }
				--
				-- Here, @f@ gets an @OtherCon []@ unfolding.

  | CompulsoryUnfolding CoreExpr	-- ^ There is /no original definition/,
					-- so you'd better unfold.

  | CoreUnfolding
		CoreExpr
		Bool
		Bool
		Bool
		UnfoldingGuidance
  -- ^ An unfolding with redundant cached information. Parameters:
  --
  --  1) Template used to perform unfolding; binder-info is correct
  --
  --  2) Is this a top level binding?
  --
  --  3) 'exprIsHNF' template (cached); it is ok to discard a 'seq' on
  --     this variable
  --
  --  4) Does this waste only a little work if we expand it inside an inlining?
  --     Basically this is a cached version of 'exprIsCheap'
  --
  --  5) Tells us about the /size/ of the unfolding template

-- | When unfolding should take place
data UnfoldingGuidance
  = UnfoldNever
  | UnfoldIfGoodArgs	Int	-- and "n" value args

			[Int]	-- Discount if the argument is evaluated.
				-- (i.e., a simplification will definitely
				-- be possible).  One elt of the list per *value* arg.

			Int	-- The "size" of the unfolding; to be elaborated
				-- later. ToDo

			Int	-- Scrutinee discount: the discount to substract if the thing is in
				-- a context (case (thing args) of ...),
				-- (where there are the right number of arguments.)

noUnfolding :: Unfolding
-- ^ There is no known 'Unfolding'
evaldUnfolding :: Unfolding
-- ^ This unfolding marks the associated thing as being evaluated

noUnfolding    = NoUnfolding
evaldUnfolding = OtherCon []

mkOtherCon :: [AltCon] -> Unfolding
mkOtherCon = OtherCon

seqUnfolding :: Unfolding -> ()
seqUnfolding (CoreUnfolding e top b1 b2 g)
  = seqExpr e `seq` top `seq` b1 `seq` b2 `seq` seqGuidance g
seqUnfolding _ = ()

seqGuidance :: UnfoldingGuidance -> ()
seqGuidance (UnfoldIfGoodArgs n ns a b) = n `seq` sum ns `seq` a `seq` b `seq` ()
seqGuidance _                           = ()
\end{code}

\begin{code}
-- | Retrieves the template of an unfolding: panics if none is known
unfoldingTemplate :: Unfolding -> CoreExpr
unfoldingTemplate (CoreUnfolding expr _ _ _ _) = expr
unfoldingTemplate (CompulsoryUnfolding expr)   = expr
unfoldingTemplate _ = panic "getUnfoldingTemplate"

-- | Retrieves the template of an unfolding if possible
maybeUnfoldingTemplate :: Unfolding -> Maybe CoreExpr
maybeUnfoldingTemplate (CoreUnfolding expr _ _ _ _) = Just expr
maybeUnfoldingTemplate (CompulsoryUnfolding expr)   = Just expr
maybeUnfoldingTemplate _                            = Nothing

-- | The constructors that the unfolding could never be: 
-- returns @[]@ if no information is available
otherCons :: Unfolding -> [AltCon]
otherCons (OtherCon cons) = cons
otherCons _               = []

-- | Determines if it is certainly the case that the unfolding will
-- yield a value (something in HNF): returns @False@ if unsure
isValueUnfolding :: Unfolding -> Bool
isValueUnfolding (CoreUnfolding _ _ is_evald _ _) = is_evald
isValueUnfolding _                                = False

-- | Determines if it possibly the case that the unfolding will
-- yield a value. Unlike 'isValueUnfolding' it returns @True@
-- for 'OtherCon'
isEvaldUnfolding :: Unfolding -> Bool
isEvaldUnfolding (OtherCon _)		          = True
isEvaldUnfolding (CoreUnfolding _ _ is_evald _ _) = is_evald
isEvaldUnfolding _                                = False

-- | Is the thing we will unfold into certainly cheap?
isCheapUnfolding :: Unfolding -> Bool
isCheapUnfolding (CoreUnfolding _ _ _ is_cheap _) = is_cheap
isCheapUnfolding _                                = False

-- | Must this unfolding happen for the code to be executable?
isCompulsoryUnfolding :: Unfolding -> Bool
isCompulsoryUnfolding (CompulsoryUnfolding _) = True
isCompulsoryUnfolding _                       = False

-- | Do we have an available or compulsory unfolding?
hasUnfolding :: Unfolding -> Bool
hasUnfolding (CoreUnfolding _ _ _ _ _) = True
hasUnfolding (CompulsoryUnfolding _)   = True
hasUnfolding _                         = False

-- | Only returns False if there is no unfolding information available at all
hasSomeUnfolding :: Unfolding -> Bool
hasSomeUnfolding NoUnfolding = False
hasSomeUnfolding _           = True

-- | Similar to @not . hasUnfolding@, but also returns @True@
-- if it has an unfolding that says it should never occur
neverUnfold :: Unfolding -> Bool
neverUnfold NoUnfolding				= True
neverUnfold (OtherCon _)			= True
neverUnfold (CoreUnfolding _ _ _ _ UnfoldNever) = True
neverUnfold _                                   = False
\end{code}


%************************************************************************
%*									*
\subsection{The main data type}
%*									*
%************************************************************************

\begin{code}
-- The Ord is needed for the FiniteMap used in the lookForConstructor
-- in SimplEnv.  If you declared that lookForConstructor *ignores*
-- constructor-applications with LitArg args, then you could get
-- rid of this Ord.

instance Outputable AltCon where
  ppr (DataAlt dc) = ppr dc
  ppr (LitAlt lit) = ppr lit
  ppr DEFAULT      = ptext (sLit "__DEFAULT")

instance Show AltCon where
  showsPrec p con = showsPrecSDoc p (ppr con)

cmpAlt :: Alt b -> Alt b -> Ordering
cmpAlt (con1, _, _) (con2, _, _) = con1 `cmpAltCon` con2

ltAlt :: Alt b -> Alt b -> Bool
ltAlt a1 a2 = (a1 `cmpAlt` a2) == LT

cmpAltCon :: AltCon -> AltCon -> Ordering
-- ^ Compares 'AltCon's within a single list of alternatives
cmpAltCon DEFAULT      DEFAULT	   = EQ
cmpAltCon DEFAULT      _           = LT

cmpAltCon (DataAlt d1) (DataAlt d2) = dataConTag d1 `compare` dataConTag d2
cmpAltCon (DataAlt _)  DEFAULT      = GT
cmpAltCon (LitAlt  l1) (LitAlt  l2) = l1 `compare` l2
cmpAltCon (LitAlt _)   DEFAULT      = GT

cmpAltCon con1 con2 = WARN( True, text "Comparing incomparable AltCons" <+> 
			 	  ppr con1 <+> ppr con2 )
		      LT
\end{code}

%************************************************************************
%*									*
\subsection{Useful synonyms}
%*									*
%************************************************************************

\begin{code}
-- | The common case for the type of binders and variables when
-- we are manipulating the Core language within GHC
type CoreBndr = Var
-- | Expressions where binders are 'CoreBndr's
type CoreExpr = Expr CoreBndr
-- | Argument expressions where binders are 'CoreBndr's
type CoreArg  = Arg  CoreBndr
-- | Binding groups where binders are 'CoreBndr's
type CoreBind = Bind CoreBndr
-- | Case alternatives where binders are 'CoreBndr's
type CoreAlt  = Alt  CoreBndr
\end{code}

%************************************************************************
%*									*
\subsection{Tagging}
%*									*
%************************************************************************

\begin{code}
-- | Binders are /tagged/ with a t
data TaggedBndr t = TB CoreBndr t	-- TB for "tagged binder"

type TaggedBind t = Bind (TaggedBndr t)
type TaggedExpr t = Expr (TaggedBndr t)
type TaggedArg  t = Arg  (TaggedBndr t)
type TaggedAlt  t = Alt  (TaggedBndr t)

instance Outputable b => Outputable (TaggedBndr b) where
  ppr (TB b l) = char '<' <> ppr b <> comma <> ppr l <> char '>'

instance Outputable b => OutputableBndr (TaggedBndr b) where
  pprBndr _ b = ppr b	-- Simple
\end{code}


%************************************************************************
%*									*
\subsection{Core-constructing functions with checking}
%*									*
%************************************************************************

\begin{code}
-- | Apply a list of argument expressions to a function expression in a nested fashion. Prefer to
-- use 'CoreUtils.mkCoreApps' if possible
mkApps    :: Expr b -> [Arg b]  -> Expr b
-- | Apply a list of type argument expressions to a function expression in a nested fashion
mkTyApps  :: Expr b -> [Type]   -> Expr b
-- | Apply a list of type or value variables to a function expression in a nested fashion
mkVarApps :: Expr b -> [Var] -> Expr b
-- | Apply a list of argument expressions to a data constructor in a nested fashion. Prefer to
-- use 'MkCore.mkCoreConApps' if possible
mkConApp      :: DataCon -> [Arg b] -> Expr b

mkApps    f args = foldl App		  	   f args
mkTyApps  f args = foldl (\ e a -> App e (Type a)) f args
mkVarApps f vars = foldl (\ e a -> App e (varToCoreExpr a)) f vars
mkConApp con args = mkApps (Var (dataConWorkId con)) args


-- | Create a machine integer literal expression of type @Int#@ from an @Integer@.
-- If you want an expression of type @Int@ use 'MkCore.mkIntExpr'
mkIntLit      :: Integer -> Expr b
-- | Create a machine integer literal expression of type @Int#@ from an @Int@.
-- If you want an expression of type @Int@ use 'MkCore.mkIntExpr'
mkIntLitInt   :: Int     -> Expr b

mkIntLit    n = Lit (mkMachInt n)
mkIntLitInt n = Lit (mkMachInt (toInteger n))

-- | Create a machine word literal expression of type  @Word#@ from an @Integer@.
-- If you want an expression of type @Word@ use 'MkCore.mkWordExpr'
mkWordLit     :: Integer -> Expr b
-- | Create a machine word literal expression of type  @Word#@ from a @Word@.
-- If you want an expression of type @Word@ use 'MkCore.mkWordExpr'
mkWordLitWord :: Word -> Expr b

mkWordLit     w = Lit (mkMachWord w)
mkWordLitWord w = Lit (mkMachWord (toInteger w))

-- | Create a machine character literal expression of type @Char#@.
-- If you want an expression of type @Char@ use 'MkCore.mkCharExpr'
mkCharLit :: Char -> Expr b
-- | Create a machine string literal expression of type @Addr#@.
-- If you want an expression of type @String@ use 'MkCore.mkStringExpr'
mkStringLit :: String -> Expr b

mkCharLit   c = Lit (mkMachChar c)
mkStringLit s = Lit (mkMachString s)

-- | Create a machine single precision literal expression of type @Float#@ from a @Rational@.
-- If you want an expression of type @Float@ use 'MkCore.mkFloatExpr'
mkFloatLit :: Rational -> Expr b
-- | Create a machine single precision literal expression of type @Float#@ from a @Float@.
-- If you want an expression of type @Float@ use 'MkCore.mkFloatExpr'
mkFloatLitFloat :: Float -> Expr b

mkFloatLit      f = Lit (mkMachFloat f)
mkFloatLitFloat f = Lit (mkMachFloat (toRational f))

-- | Create a machine double precision literal expression of type @Double#@ from a @Rational@.
-- If you want an expression of type @Double@ use 'MkCore.mkDoubleExpr'
mkDoubleLit :: Rational -> Expr b
-- | Create a machine double precision literal expression of type @Double#@ from a @Double@.
-- If you want an expression of type @Double@ use 'MkCore.mkDoubleExpr'
mkDoubleLitDouble :: Double -> Expr b

mkDoubleLit       d = Lit (mkMachDouble d)
mkDoubleLitDouble d = Lit (mkMachDouble (toRational d))

-- | Bind all supplied binding groups over an expression in a nested let expression. Prefer to
-- use 'CoreUtils.mkCoreLets' if possible
mkLets	      :: [Bind b] -> Expr b -> Expr b
-- | Bind all supplied binders over an expression in a nested lambda expression. Prefer to
-- use 'CoreUtils.mkCoreLams' if possible
mkLams	      :: [b] -> Expr b -> Expr b

mkLams binders body = foldr Lam body binders
mkLets binds body   = foldr Let body binds


-- | Create a binding group where a type variable is bound to a type. Per "CoreSyn#type_let",
-- this can only be used to bind something in a non-recursive @let@ expression
mkTyBind :: TyVar -> Type -> CoreBind
mkTyBind tv ty      = NonRec tv (Type ty)

-- | Convert a binder into either a 'Var' or 'Type' 'Expr' appropriately
varToCoreExpr :: CoreBndr -> Expr b
varToCoreExpr v | isIdVar v = Var v
                | otherwise = Type (mkTyVarTy v)

varsToCoreExprs :: [CoreBndr] -> [Expr b]
varsToCoreExprs vs = map varToCoreExpr vs
\end{code}


%************************************************************************
%*									*
\subsection{Simple access functions}
%*									*
%************************************************************************

\begin{code}
-- | Extract every variable by this group
bindersOf  :: Bind b -> [b]
bindersOf (NonRec binder _) = [binder]
bindersOf (Rec pairs)       = [binder | (binder, _) <- pairs]

-- | 'bindersOf' applied to a list of binding groups
bindersOfBinds :: [Bind b] -> [b]
bindersOfBinds binds = foldr ((++) . bindersOf) [] binds

rhssOfBind :: Bind b -> [Expr b]
rhssOfBind (NonRec _ rhs) = [rhs]
rhssOfBind (Rec pairs)    = [rhs | (_,rhs) <- pairs]

rhssOfAlts :: [Alt b] -> [Expr b]
rhssOfAlts alts = [e | (_,_,e) <- alts]

-- | Collapse all the bindings in the supplied groups into a single
-- list of lhs\/rhs pairs suitable for binding in a 'Rec' binding group
flattenBinds :: [Bind b] -> [(b, Expr b)]
flattenBinds (NonRec b r : binds) = (b,r) : flattenBinds binds
flattenBinds (Rec prs1   : binds) = prs1 ++ flattenBinds binds
flattenBinds []			  = []
\end{code}

\begin{code}
-- | We often want to strip off leading lambdas before getting down to
-- business. This function is your friend.
collectBinders	             :: Expr b -> ([b],         Expr b)
-- | Collect as many type bindings as possible from the front of a nested lambda
collectTyBinders       	     :: CoreExpr -> ([TyVar],     CoreExpr)
-- | Collect as many value bindings as possible from the front of a nested lambda
collectValBinders      	     :: CoreExpr -> ([Id],        CoreExpr)
-- | Collect type binders from the front of the lambda first, 
-- then follow up by collecting as many value bindings as possible
-- from the resulting stripped expression
collectTyAndValBinders 	     :: CoreExpr -> ([TyVar], [Id], CoreExpr)

collectBinders expr
  = go [] expr
  where
    go bs (Lam b e) = go (b:bs) e
    go bs e	     = (reverse bs, e)

collectTyAndValBinders expr
  = (tvs, ids, body)
  where
    (tvs, body1) = collectTyBinders expr
    (ids, body)  = collectValBinders body1

collectTyBinders expr
  = go [] expr
  where
    go tvs (Lam b e) | isTyVar b = go (b:tvs) e
    go tvs e			 = (reverse tvs, e)

collectValBinders expr
  = go [] expr
  where
    go ids (Lam b e) | isIdVar b = go (b:ids) e
    go ids body		         = (reverse ids, body)
\end{code}

\begin{code}
-- | Takes a nested application expression and returns the the function
-- being applied and the arguments to which it is applied
collectArgs :: Expr b -> (Expr b, [Arg b])
collectArgs expr
  = go expr []
  where
    go (App f a) as = go f (a:as)
    go e 	 as = (e, as)
\end{code}

\begin{code}
-- | Gets the cost centre enclosing an expression, if any.
-- It looks inside lambdas because @(scc \"foo\" \\x.e) = \\x. scc \"foo\" e@
coreExprCc :: Expr b -> CostCentre
coreExprCc (Note (SCC cc) _)   = cc
coreExprCc (Note _ e)          = coreExprCc e
coreExprCc (Lam _ e)           = coreExprCc e
coreExprCc _                   = noCostCentre
\end{code}

%************************************************************************
%*									*
\subsection{Predicates}
%*									*
%************************************************************************

At one time we optionally carried type arguments through to runtime.
@isRuntimeVar v@ returns if (Lam v _) really becomes a lambda at runtime,
i.e. if type applications are actual lambdas because types are kept around
at runtime.  Similarly isRuntimeArg.  

\begin{code}
-- | Will this variable exist at runtime?
isRuntimeVar :: Var -> Bool
isRuntimeVar = isIdVar 

-- | Will this argument expression exist at runtime?
isRuntimeArg :: CoreExpr -> Bool
isRuntimeArg = isValArg

-- | Returns @False@ iff the expression is a 'Type' expression at its top level
isValArg :: Expr b -> Bool
isValArg (Type _) = False
isValArg _        = True

-- | Returns @True@ iff the expression is a 'Type' expression at its top level
isTypeArg :: Expr b -> Bool
isTypeArg (Type _) = True
isTypeArg _        = False

-- | The number of binders that bind values rather than types
valBndrCount :: [CoreBndr] -> Int
valBndrCount = count isIdVar

-- | The number of argument expressions that are values rather than types at their top level
valArgCount :: [Arg b] -> Int
valArgCount = count isValArg
\end{code}


%************************************************************************
%*									*
\subsection{Seq stuff}
%*									*
%************************************************************************

\begin{code}
seqExpr :: CoreExpr -> ()
seqExpr (Var v)         = v `seq` ()
seqExpr (Lit lit)       = lit `seq` ()
seqExpr (App f a)       = seqExpr f `seq` seqExpr a
seqExpr (Lam b e)       = seqBndr b `seq` seqExpr e
seqExpr (Let b e)       = seqBind b `seq` seqExpr e
seqExpr (Case e b t as) = seqExpr e `seq` seqBndr b `seq` seqType t `seq` seqAlts as
seqExpr (Cast e co)     = seqExpr e `seq` seqType co
seqExpr (Note n e)      = seqNote n `seq` seqExpr e
seqExpr (Type t)        = seqType t

seqExprs :: [CoreExpr] -> ()
seqExprs [] = ()
seqExprs (e:es) = seqExpr e `seq` seqExprs es

seqNote :: Note -> ()
seqNote (CoreNote s)   = s `seq` ()
seqNote _              = ()

seqBndr :: CoreBndr -> ()
seqBndr b = b `seq` ()

seqBndrs :: [CoreBndr] -> ()
seqBndrs [] = ()
seqBndrs (b:bs) = seqBndr b `seq` seqBndrs bs

seqBind :: Bind CoreBndr -> ()
seqBind (NonRec b e) = seqBndr b `seq` seqExpr e
seqBind (Rec prs)    = seqPairs prs

seqPairs :: [(CoreBndr, CoreExpr)] -> ()
seqPairs [] = ()
seqPairs ((b,e):prs) = seqBndr b `seq` seqExpr e `seq` seqPairs prs

seqAlts :: [CoreAlt] -> ()
seqAlts [] = ()
seqAlts ((c,bs,e):alts) = c `seq` seqBndrs bs `seq` seqExpr e `seq` seqAlts alts

seqRules :: [CoreRule] -> ()
seqRules [] = ()
seqRules (Rule { ru_bndrs = bndrs, ru_args = args, ru_rhs = rhs } : rules) 
  = seqBndrs bndrs `seq` seqExprs (rhs:args) `seq` seqRules rules
seqRules (BuiltinRule {} : rules) = seqRules rules
\end{code}

%************************************************************************
%*									*
\subsection{Annotated core}
%*									*
%************************************************************************

\begin{code}
-- | Annotated core: allows annotation at every node in the tree
type AnnExpr bndr annot = (annot, AnnExpr' bndr annot)

-- | A clone of the 'Expr' type but allowing annotation at every tree node
data AnnExpr' bndr annot
  = AnnVar	Id
  | AnnLit	Literal
  | AnnLam	bndr (AnnExpr bndr annot)
  | AnnApp	(AnnExpr bndr annot) (AnnExpr bndr annot)
  | AnnCase	(AnnExpr bndr annot) bndr Type [AnnAlt bndr annot]
  | AnnLet	(AnnBind bndr annot) (AnnExpr bndr annot)
  | AnnCast     (AnnExpr bndr annot) Coercion
  | AnnNote	Note (AnnExpr bndr annot)
  | AnnType	Type

-- | A clone of the 'Alt' type but allowing annotation at every tree node
type AnnAlt bndr annot = (AltCon, [bndr], AnnExpr bndr annot)

-- | A clone of the 'Bind' type but allowing annotation at every tree node
data AnnBind bndr annot
  = AnnNonRec bndr (AnnExpr bndr annot)
  | AnnRec    [(bndr, AnnExpr bndr annot)]
\end{code}

\begin{code}
deAnnotate :: AnnExpr bndr annot -> Expr bndr
deAnnotate (_, e) = deAnnotate' e

deAnnotate' :: AnnExpr' bndr annot -> Expr bndr
deAnnotate' (AnnType t)           = Type t
deAnnotate' (AnnVar  v)           = Var v
deAnnotate' (AnnLit  lit)         = Lit lit
deAnnotate' (AnnLam  binder body) = Lam binder (deAnnotate body)
deAnnotate' (AnnApp  fun arg)     = App (deAnnotate fun) (deAnnotate arg)
deAnnotate' (AnnCast e co)        = Cast (deAnnotate e) co
deAnnotate' (AnnNote note body)   = Note note (deAnnotate body)

deAnnotate' (AnnLet bind body)
  = Let (deAnnBind bind) (deAnnotate body)
  where
    deAnnBind (AnnNonRec var rhs) = NonRec var (deAnnotate rhs)
    deAnnBind (AnnRec pairs) = Rec [(v,deAnnotate rhs) | (v,rhs) <- pairs]

deAnnotate' (AnnCase scrut v t alts)
  = Case (deAnnotate scrut) v t (map deAnnAlt alts)

deAnnAlt :: AnnAlt bndr annot -> Alt bndr
deAnnAlt (con,args,rhs) = (con,args,deAnnotate rhs)
\end{code}

\begin{code}
-- | As 'collectBinders' but for 'AnnExpr' rather than 'Expr'
collectAnnBndrs :: AnnExpr bndr annot -> ([bndr], AnnExpr bndr annot)
collectAnnBndrs e
  = collect [] e
  where
    collect bs (_, AnnLam b body) = collect (b:bs) body
    collect bs body		  = (reverse bs, body)
\end{code}
