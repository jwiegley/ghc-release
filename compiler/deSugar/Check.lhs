%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1997-1998
%
% Author: Juan J. Quintela    <quintela@krilin.dc.fi.udc.es>

\begin{code}
{-# OPTIONS -fno-warn-incomplete-patterns #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

module Check ( check , ExhaustivePat ) where

#include "HsVersions.h"

import HsSyn		
import TcHsSyn
import DsUtils
import MatchLit
import Id
import DataCon
import Name
import TysWiredIn
import PrelNames
import TyCon
import SrcLoc
import UniqSet
import Util
import Outputable
import FastString
\end{code}

This module performs checks about if one list of equations are:
\begin{itemize}
\item Overlapped
\item Non exhaustive
\end{itemize}
To discover that we go through the list of equations in a tree-like fashion.

If you like theory, a similar algorithm is described in:
\begin{quotation}
	{\em Two Techniques for Compiling Lazy Pattern Matching},
	Luc Maranguet,
	INRIA Rocquencourt (RR-2385, 1994)
\end{quotation}
The algorithm is based on the first technique, but there are some differences:
\begin{itemize}
\item We don't generate code
\item We have constructors and literals (not only literals as in the 
	  article)
\item We don't use directions, we must select the columns from 
	  left-to-right
\end{itemize}
(By the way the second technique is really similar to the one used in 
 @Match.lhs@ to generate code)

This function takes the equations of a pattern and returns:
\begin{itemize}
\item The patterns that are not recognized
\item The equations that are not overlapped
\end{itemize}
It simplify the patterns and then call @check'@ (the same semantics), and it 
needs to reconstruct the patterns again ....

The problem appear with things like:
\begin{verbatim}
  f [x,y]   = ....
  f (x:xs)  = .....
\end{verbatim}
We want to put the two patterns with the same syntax, (prefix form) and 
then all the constructors are equal:
\begin{verbatim}
  f (: x (: y []))   = ....
  f (: x xs)         = .....
\end{verbatim}
(more about that in @simplify_eqns@)

We would prefer to have a @WarningPat@ of type @String@, but Strings and the 
Pretty Printer are not friends.

We use @InPat@ in @WarningPat@ instead of @OutPat@
because we need to print the 
warning messages in the same way they are introduced, i.e. if the user 
wrote:
\begin{verbatim}
	f [x,y] = ..
\end{verbatim}
He don't want a warning message written:
\begin{verbatim}
        f (: x (: y [])) ........
\end{verbatim}
Then we need to use InPats.
\begin{quotation}
     Juan Quintela 5 JUL 1998\\
	  User-friendliness and compiler writers are no friends.
\end{quotation}

\begin{code}
type WarningPat = InPat Name
type ExhaustivePat = ([WarningPat], [(Name, [HsLit])])
type EqnNo  = Int
type EqnSet = UniqSet EqnNo


check :: [EquationInfo] -> ([ExhaustivePat], [EquationInfo])
	-- Second result is the shadowed equations
check qs = (untidy_warns, shadowed_eqns)
      where
	(warns, used_nos) = check' ([1..] `zip` map simplify_eqn qs)
	untidy_warns = map untidy_exhaustive warns 
	shadowed_eqns = [eqn | (eqn,i) <- qs `zip` [1..], 
				not (i `elementOfUniqSet` used_nos)]

untidy_exhaustive :: ExhaustivePat -> ExhaustivePat
untidy_exhaustive ([pat], messages) = 
		  ([untidy_no_pars pat], map untidy_message messages)
untidy_exhaustive (pats, messages) = 
		  (map untidy_pars pats, map untidy_message messages)

untidy_message :: (Name, [HsLit]) -> (Name, [HsLit])
untidy_message (string, lits) = (string, map untidy_lit lits)
\end{code}

The function @untidy@ does the reverse work of the @simplify_pat@ funcion.

\begin{code}

type NeedPars = Bool 

untidy_no_pars :: WarningPat -> WarningPat
untidy_no_pars p = untidy False p

untidy_pars :: WarningPat -> WarningPat
untidy_pars p = untidy True p

untidy :: NeedPars -> WarningPat -> WarningPat
untidy b (L loc p) = L loc (untidy' b p)
  where
    untidy' _ p@(WildPat _)          = p
    untidy' _ p@(VarPat _)           = p
    untidy' _ (LitPat lit)           = LitPat (untidy_lit lit)
    untidy' _ p@(ConPatIn _ (PrefixCon [])) = p
    untidy' b (ConPatIn name ps)     = pars b (L loc (ConPatIn name (untidy_con ps)))
    untidy' _ (ListPat pats ty)      = ListPat (map untidy_no_pars pats) ty
    untidy' _ (TuplePat pats box ty) = TuplePat (map untidy_no_pars pats) box ty
    untidy' _ (PArrPat _ _)	     = panic "Check.untidy: Shouldn't get a parallel array here!"
    untidy' _ (SigPatIn _ _) 	     = panic "Check.untidy: SigPat"

untidy_con :: HsConPatDetails Name -> HsConPatDetails Name
untidy_con (PrefixCon pats) = PrefixCon (map untidy_pars pats) 
untidy_con (InfixCon p1 p2) = InfixCon  (untidy_pars p1) (untidy_pars p2)
untidy_con (RecCon (HsRecFields flds dd)) 
  = RecCon (HsRecFields [ fld { hsRecFieldArg = untidy_pars (hsRecFieldArg fld) }
			| fld <- flds ] dd)

pars :: NeedPars -> WarningPat -> Pat Name
pars True p = ParPat p
pars _    p = unLoc p

untidy_lit :: HsLit -> HsLit
untidy_lit (HsCharPrim c) = HsChar c
untidy_lit lit 		  = lit
\end{code}

This equation is the same that check, the only difference is that the
boring work is done, that work needs to be done only once, this is
the reason top have two functions, check is the external interface,
@check'@ is called recursively.

There are several cases:

\begin{itemize} 
\item There are no equations: Everything is OK. 
\item There are only one equation, that can fail, and all the patterns are
      variables. Then that equation is used and the same equation is 
      non-exhaustive.
\item All the patterns are variables, and the match can fail, there are 
      more equations then the results is the result of the rest of equations 
      and this equation is used also.

\item The general case, if all the patterns are variables (here the match 
      can't fail) then the result is that this equation is used and this 
      equation doesn't generate non-exhaustive cases.

\item In the general case, there can exist literals ,constructors or only 
      vars in the first column, we actuate in consequence.

\end{itemize}


\begin{code}

check' :: [(EqnNo, EquationInfo)] 
	-> ([ExhaustivePat], 	-- Pattern scheme that might not be matched at all
	    EqnSet)  		-- Eqns that are used (others are overlapped)

check' [] = ([([],[])],emptyUniqSet)

check' ((n, EqnInfo { eqn_pats = ps, eqn_rhs = MatchResult can_fail _ }) : rs) 
   | first_eqn_all_vars && case can_fail of { CantFail -> True; CanFail -> False }
   = ([], unitUniqSet n)	-- One eqn, which can't fail

   | first_eqn_all_vars && null rs	-- One eqn, but it can fail
   = ([(takeList ps (repeat nlWildPat),[])], unitUniqSet n)

   | first_eqn_all_vars		-- Several eqns, first can fail
   = (pats, addOneToUniqSet indexs n)
  where
    first_eqn_all_vars = all_vars ps
    (pats,indexs) = check' rs

check' qs
   | literals     = split_by_literals qs
   | constructors = split_by_constructor qs
   | only_vars    = first_column_only_vars qs
-- FIXME: hack to get view patterns through for now
   | otherwise    = ([([],[])],emptyUniqSet)
-- pprPanic "Check.check': Not implemented :-(" (ppr first_pats)
  where
     -- Note: RecPats will have been simplified to ConPats
     --       at this stage.
    first_pats   = ASSERT2( okGroup qs, pprGroup qs ) map firstPatN qs
    constructors = any is_con first_pats
    literals     = any is_lit first_pats
    only_vars    = all is_var first_pats
\end{code}

Here begins the code to deal with literals, we need to split the matrix
in different matrix beginning by each literal and a last matrix with the 
rest of values.

\begin{code}
split_by_literals :: [(EqnNo, EquationInfo)] -> ([ExhaustivePat], EqnSet)
split_by_literals qs = process_literals used_lits qs
           where
             used_lits = get_used_lits qs
\end{code}

@process_explicit_literals@ is a function that process each literal that appears 
in the column of the matrix. 

\begin{code}
process_explicit_literals :: [HsLit] -> [(EqnNo, EquationInfo)] -> ([ExhaustivePat],EqnSet)
process_explicit_literals lits qs = (concat pats, unionManyUniqSets indexs)
    where                  
      pats_indexs   = map (\x -> construct_literal_matrix x qs) lits
      (pats,indexs) = unzip pats_indexs 
\end{code}


@process_literals@ calls @process_explicit_literals@ to deal with the literals 
that appears in the matrix and deal also with the rest of the cases. It 
must be one Variable to be complete.

\begin{code}

process_literals :: [HsLit] -> [(EqnNo, EquationInfo)] -> ([ExhaustivePat],EqnSet)
process_literals used_lits qs 
  | null default_eqns  = ASSERT( not (null qs) ) ([make_row_vars used_lits (head qs)] ++ pats,indexs)
  | otherwise          = (pats_default,indexs_default)
     where
       (pats,indexs)   = process_explicit_literals used_lits qs
       default_eqns    = ASSERT2( okGroup qs, pprGroup qs ) 
			 [remove_var q | q <- qs, is_var (firstPatN q)]
       (pats',indexs') = check' default_eqns 
       pats_default    = [(nlWildPat:ps,constraints) | (ps,constraints) <- (pats')] ++ pats 
       indexs_default  = unionUniqSets indexs' indexs
\end{code}

Here we have selected the literal and we will select all the equations that 
begins for that literal and create a new matrix.

\begin{code}
construct_literal_matrix :: HsLit -> [(EqnNo, EquationInfo)] -> ([ExhaustivePat],EqnSet)
construct_literal_matrix lit qs =
    (map (\ (xs,ys) -> (new_lit:xs,ys)) pats,indexs) 
  where
    (pats,indexs) = (check' (remove_first_column_lit lit qs)) 
    new_lit = nlLitPat lit

remove_first_column_lit :: HsLit
                        -> [(EqnNo, EquationInfo)] 
                        -> [(EqnNo, EquationInfo)]
remove_first_column_lit lit qs
  = ASSERT2( okGroup qs, pprGroup qs ) 
    [(n, shift_pat eqn) | q@(n,eqn) <- qs, is_var_lit lit (firstPatN q)]
  where
     shift_pat eqn@(EqnInfo { eqn_pats = _:ps}) = eqn { eqn_pats = ps }
     shift_pat _                                = panic "Check.shift_var: no patterns"
\end{code}

This function splits the equations @qs@ in groups that deal with the 
same constructor.

\begin{code}
split_by_constructor :: [(EqnNo, EquationInfo)] -> ([ExhaustivePat], EqnSet)
split_by_constructor qs 
  | notNull unused_cons = need_default_case used_cons unused_cons qs 
  | otherwise           = no_need_default_case used_cons qs 
                       where 
                          used_cons   = get_used_cons qs 
                          unused_cons = get_unused_cons used_cons 
\end{code}

The first column of the patterns matrix only have vars, then there is 
nothing to do.

\begin{code}
first_column_only_vars :: [(EqnNo, EquationInfo)] -> ([ExhaustivePat],EqnSet)
first_column_only_vars qs = (map (\ (xs,ys) -> (nlWildPat:xs,ys)) pats,indexs)
                          where
                            (pats, indexs) = check' (map remove_var qs)
\end{code}

This equation takes a matrix of patterns and split the equations by 
constructor, using all the constructors that appears in the first column 
of the pattern matching.

We can need a default clause or not ...., it depends if we used all the 
constructors or not explicitly. The reasoning is similar to @process_literals@,
the difference is that here the default case is not always needed.

\begin{code}
no_need_default_case :: [Pat Id] -> [(EqnNo, EquationInfo)] -> ([ExhaustivePat],EqnSet)
no_need_default_case cons qs = (concat pats, unionManyUniqSets indexs)
    where                  
      pats_indexs   = map (\x -> construct_matrix x qs) cons
      (pats,indexs) = unzip pats_indexs 

need_default_case :: [Pat Id] -> [DataCon] -> [(EqnNo, EquationInfo)] -> ([ExhaustivePat],EqnSet)
need_default_case used_cons unused_cons qs 
  | null default_eqns  = (pats_default_no_eqns,indexs)
  | otherwise          = (pats_default,indexs_default)
     where
       (pats,indexs)   = no_need_default_case used_cons qs
       default_eqns    = ASSERT2( okGroup qs, pprGroup qs ) 
			 [remove_var q | q <- qs, is_var (firstPatN q)]
       (pats',indexs') = check' default_eqns 
       pats_default    = [(make_whole_con c:ps,constraints) | 
                          c <- unused_cons, (ps,constraints) <- pats'] ++ pats
       new_wilds       = ASSERT( not (null qs) ) make_row_vars_for_constructor (head qs)
       pats_default_no_eqns =  [(make_whole_con c:new_wilds,[]) | c <- unused_cons] ++ pats
       indexs_default  = unionUniqSets indexs' indexs

construct_matrix :: Pat Id -> [(EqnNo, EquationInfo)] -> ([ExhaustivePat],EqnSet)
construct_matrix con qs =
    (map (make_con con) pats,indexs) 
  where
    (pats,indexs) = (check' (remove_first_column con qs)) 
\end{code}

Here remove first column is more difficult that with literals due to the fact 
that constructors can have arguments.

For instance, the matrix
\begin{verbatim}
 (: x xs) y
 z        y
\end{verbatim}
is transformed in:
\begin{verbatim}
 x xs y
 _ _  y
\end{verbatim}

\begin{code}
remove_first_column :: Pat Id                -- Constructor 
                    -> [(EqnNo, EquationInfo)] 
                    -> [(EqnNo, EquationInfo)]
remove_first_column (ConPatOut{ pat_con = L _ con, pat_args = PrefixCon con_pats }) qs
  = ASSERT2( okGroup qs, pprGroup qs ) 
    [(n, shift_var eqn) | q@(n, eqn) <- qs, is_var_con con (firstPatN q)]
  where
     new_wilds = [WildPat (hsLPatType arg_pat) | arg_pat <- con_pats]
     shift_var eqn@(EqnInfo { eqn_pats = ConPatOut{ pat_args = PrefixCon ps' } : ps}) 
 	= eqn { eqn_pats = map unLoc ps' ++ ps }
     shift_var eqn@(EqnInfo { eqn_pats = WildPat _ : ps })
  	= eqn { eqn_pats = new_wilds ++ ps }
     shift_var _ = panic "Check.Shift_var:No done"

make_row_vars :: [HsLit] -> (EqnNo, EquationInfo) -> ExhaustivePat
make_row_vars used_lits (_, EqnInfo { eqn_pats = pats})
   = (nlVarPat new_var:takeList (tail pats) (repeat nlWildPat),[(new_var,used_lits)])
  where 
     new_var = hash_x

hash_x :: Name
hash_x = mkInternalName unboundKey {- doesn't matter much -}
		     (mkVarOccFS (fsLit "#x"))
		     noSrcSpan

make_row_vars_for_constructor :: (EqnNo, EquationInfo) -> [WarningPat]
make_row_vars_for_constructor (_, EqnInfo { eqn_pats = pats}) 
  = takeList (tail pats) (repeat nlWildPat)

compare_cons :: Pat Id -> Pat Id -> Bool
compare_cons (ConPatOut{ pat_con = L _ id1 }) (ConPatOut { pat_con = L _ id2 }) = id1 == id2  

remove_dups :: [Pat Id] -> [Pat Id]
remove_dups []     = []
remove_dups (x:xs) | or (map (\y -> compare_cons x y) xs) = remove_dups  xs
                   | otherwise                            = x : remove_dups xs

get_used_cons :: [(EqnNo, EquationInfo)] -> [Pat Id]
get_used_cons qs = remove_dups [pat | q <- qs, let pat = firstPatN q, 
				      isConPatOut pat]

isConPatOut :: Pat Id -> Bool
isConPatOut (ConPatOut {}) = True
isConPatOut _              = False

remove_dups' :: [HsLit] -> [HsLit] 
remove_dups' []                   = []
remove_dups' (x:xs) | x `elem` xs = remove_dups' xs
                    | otherwise   = x : remove_dups' xs 


get_used_lits :: [(EqnNo, EquationInfo)] -> [HsLit]
get_used_lits qs = remove_dups' all_literals
	         where
	           all_literals = get_used_lits' qs

get_used_lits' :: [(EqnNo, EquationInfo)] -> [HsLit]
get_used_lits' [] = []
get_used_lits' (q:qs) 
  | Just lit <- get_lit (firstPatN q) = lit : get_used_lits' qs
  | otherwise		              = get_used_lits qs

get_lit :: Pat id -> Maybe HsLit 
-- Get a representative HsLit to stand for the OverLit
-- It doesn't matter which one, because they will only be compared
-- with other HsLits gotten in the same way
get_lit (LitPat lit)				          = Just lit
get_lit (NPat (OverLit { ol_val = HsIntegral i})    mb _) = Just (HsIntPrim   (mb_neg mb i))
get_lit (NPat (OverLit { ol_val = HsFractional f }) mb _) = Just (HsFloatPrim (mb_neg mb f))
get_lit (NPat (OverLit { ol_val = HsIsString s })   _  _) = Just (HsStringPrim s)
get_lit _                                	          = Nothing

mb_neg :: Num a => Maybe b -> a -> a
mb_neg Nothing  v = v
mb_neg (Just _) v = -v

get_unused_cons :: [Pat Id] -> [DataCon]
get_unused_cons used_cons = ASSERT( not (null used_cons) ) unused_cons
     where
       (ConPatOut { pat_con = l_con }) = head used_cons
       ty_con 	       = dataConTyCon (unLoc l_con)	-- Newtype observable
       all_cons        = tyConDataCons ty_con
       used_cons_as_id = map (\ (ConPatOut{ pat_con = L _ d}) -> d) used_cons
       unused_cons     = uniqSetToList
			 (mkUniqSet all_cons `minusUniqSet` mkUniqSet used_cons_as_id) 

all_vars :: [Pat Id] -> Bool
all_vars []             = True
all_vars (WildPat _:ps) = all_vars ps
all_vars _              = False

remove_var :: (EqnNo, EquationInfo) -> (EqnNo, EquationInfo)
remove_var (n, eqn@(EqnInfo { eqn_pats = WildPat _ : ps})) = (n, eqn { eqn_pats = ps })
remove_var _  = panic "Check.remove_var: equation does not begin with a variable"

-----------------------
eqnPats :: (EqnNo, EquationInfo) -> [Pat Id]
eqnPats (_, eqn) = eqn_pats eqn

okGroup :: [(EqnNo, EquationInfo)] -> Bool
-- True if all equations have at least one pattern, and
-- all have the same number of patterns
okGroup [] = True
okGroup (e:es) = n_pats > 0 && and [length (eqnPats e) == n_pats | e <- es]
	       where
		 n_pats = length (eqnPats e)

-- Half-baked print
pprGroup :: [(EqnNo, EquationInfo)] -> SDoc
pprEqnInfo :: (EqnNo, EquationInfo) -> SDoc
pprGroup es = vcat (map pprEqnInfo es)
pprEqnInfo e = ppr (eqnPats e)


firstPatN :: (EqnNo, EquationInfo) -> Pat Id
firstPatN (_, eqn) = firstPat eqn

is_con :: Pat Id -> Bool
is_con (ConPatOut {}) = True
is_con _              = False

is_lit :: Pat Id -> Bool
is_lit (LitPat _)      = True
is_lit (NPat _ _ _)  = True
is_lit _               = False

is_var :: Pat Id -> Bool
is_var (WildPat _) = True
is_var _           = False

is_var_con :: DataCon -> Pat Id -> Bool
is_var_con _   (WildPat _)                                 = True
is_var_con con (ConPatOut{ pat_con = L _ id }) | id == con = True
is_var_con _   _                                           = False

is_var_lit :: HsLit -> Pat Id -> Bool
is_var_lit _   (WildPat _)   = True
is_var_lit lit pat 
  | Just lit' <- get_lit pat = lit == lit'
  | otherwise		     = False
\end{code}

The difference beteewn @make_con@ and @make_whole_con@ is that
@make_wole_con@ creates a new constructor with all their arguments, and
@make_con@ takes a list of argumntes, creates the contructor getting their
arguments from the list. See where \fbox{\ ???\ } are used for details.

We need to reconstruct the patterns (make the constructors infix and
similar) at the same time that we create the constructors.

You can tell tuple constructors using
\begin{verbatim}
        Id.isTupleCon
\end{verbatim}
You can see if one constructor is infix with this clearer code :-))))))))))
\begin{verbatim}
        Lex.isLexConSym (Name.occNameString (Name.getOccName con))
\end{verbatim}

       Rather clumsy but it works. (Simon Peyton Jones)


We don't mind the @nilDataCon@ because it doesn't change the way to
print the messsage, we are searching only for things like: @[1,2,3]@,
not @x:xs@ ....

In @reconstruct_pat@ we want to ``undo'' the work
that we have done in @simplify_pat@.
In particular:
\begin{tabular}{lll}
	@((,) x y)@   & returns to be & @(x, y)@
\\      @((:) x xs)@  & returns to be & @(x:xs)@
\\      @(x:(...:[])@ & returns to be & @[x,...]@
\end{tabular}
%
The difficult case is the third one becouse we need to follow all the
contructors until the @[]@ to know that we need to use the second case,
not the second. \fbox{\ ???\ }
%
\begin{code}
isInfixCon :: DataCon -> Bool
isInfixCon con = isDataSymOcc (getOccName con)

is_nil :: Pat Name -> Bool
is_nil (ConPatIn con (PrefixCon [])) = unLoc con == getName nilDataCon
is_nil _               		     = False

is_list :: Pat Name -> Bool
is_list (ListPat _ _) = True
is_list _             = False

return_list :: DataCon -> Pat Name -> Bool
return_list id q = id == consDataCon && (is_nil q || is_list q) 

make_list :: LPat Name -> Pat Name -> Pat Name
make_list p q | is_nil q    = ListPat [p] placeHolderType
make_list p (ListPat ps ty) = ListPat (p:ps) ty
make_list _ _               = panic "Check.make_list: Invalid argument"

make_con :: Pat Id -> ExhaustivePat -> ExhaustivePat           
make_con (ConPatOut{ pat_con = L _ id }) (lp:lq:ps, constraints) 
     | return_list id q = (noLoc (make_list lp q) : ps, constraints)
     | isInfixCon id    = (nlInfixConPat (getName id) lp lq : ps, constraints) 
   where q  = unLoc lq	

make_con (ConPatOut{ pat_con = L _ id, pat_args = PrefixCon pats, pat_ty = ty }) (ps, constraints) 
      | isTupleTyCon tc  = (noLoc (TuplePat pats_con (tupleTyConBoxity tc) ty) : rest_pats, constraints) 
      | isPArrFakeCon id = (noLoc (PArrPat pats_con placeHolderType)           : rest_pats, constraints) 
      | otherwise        = (nlConPat name pats_con      : rest_pats, constraints)
    where 
	name     	      = getName id
	(pats_con, rest_pats) = splitAtList pats ps
	tc	    	      = dataConTyCon id

-- reconstruct parallel array pattern
--
--  * don't check for the type only; we need to make sure that we are really
--   dealing with one of the fake constructors and not with the real
--   representation 

make_whole_con :: DataCon -> WarningPat
make_whole_con con | isInfixCon con = nlInfixConPat name nlWildPat nlWildPat
                   | otherwise      = nlConPat name pats
                where 
                  name   = getName con
                  pats   = [nlWildPat | _ <- dataConOrigArgTys con]
\end{code}

This equation makes the same thing as @tidy@ in @Match.lhs@, the
difference is that here we can do all the tidy in one place and in the
@Match@ tidy it must be done one column each time due to bookkeeping 
constraints.

\begin{code}

simplify_eqn :: EquationInfo -> EquationInfo
simplify_eqn eqn = eqn { eqn_pats = map simplify_pat (eqn_pats eqn), 
		         eqn_rhs  = simplify_rhs (eqn_rhs eqn) }
  where
	-- Horrible hack.  The simplify_pat stuff converts NPlusK pats to WildPats
	-- which of course loses the info that they can fail to match.  So we 
	-- stick in a CanFail as if it were a guard.
	-- The Right Thing to do is for the whole system to treat NPlusK pats properly
    simplify_rhs (MatchResult can_fail body)
	| any has_nplusk_pat (eqn_pats eqn) = MatchResult CanFail body
	| otherwise			    = MatchResult can_fail body

has_nplusk_lpat :: LPat Id -> Bool
has_nplusk_lpat (L _ p) = has_nplusk_pat p

has_nplusk_pat :: Pat Id -> Bool
has_nplusk_pat (NPlusKPat _ _ _ _) 	     = True
has_nplusk_pat (ParPat p)  	   	     = has_nplusk_lpat p
has_nplusk_pat (AsPat _ p) 	   	     = has_nplusk_lpat p
has_nplusk_pat (ViewPat _ p _)               = has_nplusk_lpat p
has_nplusk_pat (SigPatOut p _ )    	     = has_nplusk_lpat p
has_nplusk_pat (ListPat ps _)  	   	     = any has_nplusk_lpat ps
has_nplusk_pat (TuplePat ps _ _)   	     = any has_nplusk_lpat ps
has_nplusk_pat (PArrPat ps _)  	   	     = any has_nplusk_lpat ps
has_nplusk_pat (LazyPat _)                   = False    -- Why?
has_nplusk_pat (BangPat p)     	   	     = has_nplusk_lpat p	-- I think
has_nplusk_pat (ConPatOut { pat_args = ps }) = any has_nplusk_lpat (hsConPatArgs ps)
has_nplusk_pat _                             = False -- VarPat, VarPatOut, WildPat, LitPat, NPat, TypePat

simplify_lpat :: LPat Id -> LPat Id  
simplify_lpat p = fmap simplify_pat p

simplify_pat :: Pat Id -> Pat Id
simplify_pat pat@(WildPat _)  = pat
simplify_pat (VarPat id)      = WildPat (idType id) 
simplify_pat (VarPatOut id _) = WildPat (idType id) 	-- Ignore the bindings
simplify_pat (ParPat p)       = unLoc (simplify_lpat p)
simplify_pat (LazyPat p)      = WildPat (hsLPatType p)	-- For overlap and exhaustiveness checking
							-- purposes, a ~pat is like a wildcard
simplify_pat (BangPat p)      = unLoc (simplify_lpat p)
simplify_pat (AsPat _ p)      = unLoc (simplify_lpat p)

simplify_pat (ViewPat expr p ty)     = ViewPat expr (simplify_lpat p) ty

simplify_pat (SigPatOut p _)  = unLoc (simplify_lpat p)	-- I'm not sure this is right

simplify_pat pat@(ConPatOut { pat_con = L _ id, pat_args = ps })
  = pat { pat_args = simplify_con id ps }

simplify_pat (ListPat ps ty) = 
  unLoc $ foldr (\ x y -> mkPrefixConPat consDataCon [x,y] list_ty)
	                          (mkNilPat list_ty)
	                          (map simplify_lpat ps)
         where list_ty = mkListTy ty

-- introduce fake parallel array constructors to be able to handle parallel
-- arrays with the existing machinery for constructor pattern
--
simplify_pat (PArrPat ps ty)
  = unLoc $ mkPrefixConPat (parrFakeCon (length ps))
			   (map simplify_lpat ps) 
			   (mkPArrTy ty)

simplify_pat (TuplePat ps boxity ty)
  = unLoc $ mkPrefixConPat (tupleCon boxity arity)
		           (map simplify_lpat ps) ty
  where
    arity = length ps

-- unpack string patterns fully, so we can see when they overlap with
-- each other, or even explicit lists of Chars.
simplify_pat (LitPat (HsString s)) =
   unLoc $ foldr (\c pat -> mkPrefixConPat consDataCon [mk_char_lit c, pat] stringTy)
		 (mkPrefixConPat nilDataCon [] stringTy) (unpackFS s)
  where
    mk_char_lit c = mkPrefixConPat charDataCon [nlLitPat (HsCharPrim c)] charTy

simplify_pat (LitPat lit)		 = tidyLitPat lit 
simplify_pat (NPat lit mb_neg eq) = tidyNPat lit mb_neg eq

simplify_pat (NPlusKPat id _ _ _)
   = WildPat (idType (unLoc id))

simplify_pat (CoPat _ pat _) = simplify_pat pat

-----------------
simplify_con :: DataCon -> HsConPatDetails Id -> HsConPatDetails Id
simplify_con _   (PrefixCon ps)   = PrefixCon (map simplify_lpat ps)
simplify_con _   (InfixCon p1 p2) = PrefixCon [simplify_lpat p1, simplify_lpat p2]
simplify_con con (RecCon (HsRecFields fs _))      
  | null fs   = PrefixCon [nlWildPat | _ <- dataConOrigArgTys con]
		-- Special case for null patterns; maybe not a record at all
  | otherwise = PrefixCon (map (simplify_lpat.snd) all_pats)
  where
     -- pad out all the missing fields with WildPats.
    field_pats = map (\ f -> (f, nlWildPat)) (dataConFieldLabels con)
    all_pats = foldr (\(HsRecField id p _) acc -> insertNm (getName (unLoc id)) p acc)
		     field_pats fs
       
    insertNm nm p [] = [(nm,p)]
    insertNm nm p (x@(n,_):xs)
      | nm == n    = (nm,p):xs
      | otherwise  = x : insertNm nm p xs
\end{code}