-----------------------------------------------------------------------------
-- |
-- Module      :  Text.PrettyPrint.HughesPJ
-- Copyright   :  (c) The University of Glasgow 2001
-- License     :  BSD-style (see the file libraries/base/LICENSE)
--
-- Maintainer  :  libraries@haskell.org
-- Stability   :  provisional
-- Portability :  portable
--
-- John Hughes's and Simon Peyton Jones's Pretty Printer Combinators
--
-- Based on /The Design of a Pretty-printing Library/
-- in Advanced Functional Programming,
-- Johan Jeuring and Erik Meijer (eds), LNCS 925
-- <http://www.cs.chalmers.se/~rjmh/Papers/pretty.ps>
--
-- Heavily modified by Simon Peyton Jones, Dec 96
--
-----------------------------------------------------------------------------

{-
Version 3.0     28 May 1997
  * Cured massive performance bug.  If you write

        foldl <> empty (map (text.show) [1..10000])

    you get quadratic behaviour with V2.0.  Why?  For just the same
    reason as you get quadratic behaviour with left-associated (++)
    chains.

    This is really bad news.  One thing a pretty-printer abstraction
    should certainly guarantee is insensivity to associativity.  It
    matters: suddenly GHC's compilation times went up by a factor of
    100 when I switched to the new pretty printer.

    I fixed it with a bit of a hack (because I wanted to get GHC back
    on the road).  I added two new constructors to the Doc type, Above
    and Beside:

         <> = Beside
         $$ = Above

    Then, where I need to get to a "TextBeside" or "NilAbove" form I
    "force" the Doc to squeeze out these suspended calls to Beside and
    Above; but in so doing I re-associate. It's quite simple, but I'm
    not satisfied that I've done the best possible job.  I'll send you
    the code if you are interested.

  * Added new exports:
        punctuate, hang
        int, integer, float, double, rational,
        lparen, rparen, lbrack, rbrack, lbrace, rbrace,

  * fullRender's type signature has changed.  Rather than producing a
    string it now takes an extra couple of arguments that tells it how
    to glue fragments of output together:

        fullRender :: Mode
                   -> Int                       -- Line length
                   -> Float                     -- Ribbons per line
                   -> (TextDetails -> a -> a)   -- What to do with text
                   -> a                         -- What to do at the end
                   -> Doc
                   -> a                         -- Result

    The "fragments" are encapsulated in the TextDetails data type:

        data TextDetails = Chr  Char
                         | Str  String
                         | PStr FAST_STRING

    The Chr and Str constructors are obvious enough.  The PStr
    constructor has a packed string (FAST_STRING) inside it.  It's
    generated by using the new "ptext" export.

    An advantage of this new setup is that you can get the renderer to
    do output directly (by passing in a function of type (TextDetails
    -> IO () -> IO ()), rather than producing a string that you then
    print.


Version 2.0     24 April 1997
  * Made empty into a left unit for <> as well as a right unit;
    it is also now true that
        nest k empty = empty
    which wasn't true before.

  * Fixed an obscure bug in sep that occassionally gave very weird behaviour

  * Added $+$

  * Corrected and tidied up the laws and invariants

======================================================================
Relative to John's original paper, there are the following new features:

1.  There's an empty document, "empty".  It's a left and right unit for
    both <> and $$, and anywhere in the argument list for
    sep, hcat, hsep, vcat, fcat etc.

    It is Really Useful in practice.

2.  There is a paragraph-fill combinator, fsep, that's much like sep,
    only it keeps fitting things on one line until it can't fit any more.

3.  Some random useful extra combinators are provided.
        <+> puts its arguments beside each other with a space between them,
            unless either argument is empty in which case it returns the other


        hcat is a list version of <>
        hsep is a list version of <+>
        vcat is a list version of $$

        sep (separate) is either like hsep or like vcat, depending on what fits

        cat  behaves like sep,  but it uses <> for horizontal conposition
        fcat behaves like fsep, but it uses <> for horizontal conposition

        These new ones do the obvious things:
                char, semi, comma, colon, space,
                parens, brackets, braces,
                quotes, doubleQuotes

4.  The "above" combinator, $$, now overlaps its two arguments if the
    last line of the top argument stops before the first line of the
    second begins.

        For example:  text "hi" $$ nest 5 (text "there")
        lays out as
                        hi   there
        rather than
                        hi
                             there

        There are two places this is really useful

        a) When making labelled blocks, like this:
                Left ->   code for left
                Right ->  code for right
                LongLongLongLabel ->
                          code for longlonglonglabel
           The block is on the same line as the label if the label is
           short, but on the next line otherwise.

        b) When laying out lists like this:
                [ first
                , second
                , third
                ]
           which some people like.  But if the list fits on one line
           you want [first, second, third].  You can't do this with
           John's original combinators, but it's quite easy with the
           new $$.

        The combinator $+$ gives the original "never-overlap" behaviour.

5.      Several different renderers are provided:
                * a standard one
                * one that uses cut-marks to avoid deeply-nested documents
                        simply piling up in the right-hand margin
                * one that ignores indentation
                        (fewer chars output; good for machines)
                * one that ignores indentation and newlines
                        (ditto, only more so)

6.      Numerous implementation tidy-ups
        Use of unboxed data types to speed up the implementation
-}

module Text.PrettyPrint.HughesPJ (

        -- * The document type
        Doc,            -- Abstract

        -- * Constructing documents

        -- ** Converting values into documents
        char, text, ptext, sizedText, zeroWidthText,
        int, integer, float, double, rational,

        -- ** Simple derived documents
        semi, comma, colon, space, equals,
        lparen, rparen, lbrack, rbrack, lbrace, rbrace,

        -- ** Wrapping documents in delimiters
        parens, brackets, braces, quotes, doubleQuotes,

        -- ** Combining documents
        empty,
        (<>), (<+>), hcat, hsep,
        ($$), ($+$), vcat,
        sep, cat,
        fsep, fcat,
        nest,
        hang, punctuate,

        -- * Predicates on documents
        isEmpty,

        -- * Rendering documents

        -- ** Default rendering
        render,

        -- ** Rendering with a particular style
        Style(..),
        style,
        renderStyle,

        -- ** General rendering
        fullRender,
        Mode(..), TextDetails(..),

  ) where


import Prelude
import Data.Monoid ( Monoid(mempty, mappend) )
import Data.String ( IsString(fromString) )

infixl 6 <>
infixl 6 <+>
infixl 5 $$, $+$

-- ---------------------------------------------------------------------------
-- The interface

-- The primitive Doc values

isEmpty :: Doc    -> Bool;  -- ^ Returns 'True' if the document is empty

-- | The empty document, with no height and no width.
-- 'empty' is the identity for '<>', '<+>', '$$' and '$+$', and anywhere
-- in the argument list for 'sep', 'hcat', 'hsep', 'vcat', 'fcat' etc.
empty   :: Doc

semi    :: Doc;                 -- ^ A ';' character
comma   :: Doc;                 -- ^ A ',' character
colon   :: Doc;                 -- ^ A ':' character
space   :: Doc;                 -- ^ A space character
equals  :: Doc;                 -- ^ A '=' character
lparen  :: Doc;                 -- ^ A '(' character
rparen  :: Doc;                 -- ^ A ')' character
lbrack  :: Doc;                 -- ^ A '[' character
rbrack  :: Doc;                 -- ^ A ']' character
lbrace  :: Doc;                 -- ^ A '{' character
rbrace  :: Doc;                 -- ^ A '}' character

-- | A document of height and width 1, containing a literal character.
char     :: Char     -> Doc

-- | A document of height 1 containing a literal string.
-- 'text' satisfies the following laws:
--
-- * @'text' s '<>' 'text' t = 'text' (s'++'t)@
--
-- * @'text' \"\" '<>' x = x@, if @x@ non-empty
--
-- The side condition on the last law is necessary because @'text' \"\"@
-- has height 1, while 'empty' has no height.
text     :: String   -> Doc

instance IsString Doc where
    fromString = text

-- | An obsolete function, now identical to 'text'.
ptext    :: String   -> Doc

-- | Some text with any width. (@text s = sizedText (length s) s@)
sizedText :: Int -> String -> Doc

-- | Some text, but without any width. Use for non-printing text
-- such as a HTML or Latex tags
zeroWidthText :: String   -> Doc

int      :: Int      -> Doc;    -- ^ @int n = text (show n)@
integer  :: Integer  -> Doc;    -- ^ @integer n = text (show n)@
float    :: Float    -> Doc;    -- ^ @float n = text (show n)@
double   :: Double   -> Doc;    -- ^ @double n = text (show n)@
rational :: Rational -> Doc;    -- ^ @rational n = text (show n)@

parens       :: Doc -> Doc;     -- ^ Wrap document in @(...)@
brackets     :: Doc -> Doc;     -- ^ Wrap document in @[...]@
braces       :: Doc -> Doc;     -- ^ Wrap document in @{...}@
quotes       :: Doc -> Doc;     -- ^ Wrap document in @\'...\'@
doubleQuotes :: Doc -> Doc;     -- ^ Wrap document in @\"...\"@

-- Combining @Doc@ values

instance Monoid Doc where
    mempty  = empty
    mappend = (<>)

-- | Beside.
-- '<>' is associative, with identity 'empty'.
(<>)   :: Doc -> Doc -> Doc

-- | Beside, separated by space, unless one of the arguments is 'empty'.
-- '<+>' is associative, with identity 'empty'.
(<+>)  :: Doc -> Doc -> Doc

-- | Above, except that if the last line of the first argument stops
-- at least one position before the first line of the second begins,
-- these two lines are overlapped.  For example:
--
-- >    text "hi" $$ nest 5 (text "there")
--
-- lays out as
--
-- >    hi   there
--
-- rather than
--
-- >    hi
-- >         there
--
-- '$$' is associative, with identity 'empty', and also satisfies
--
-- * @(x '$$' y) '<>' z = x '$$' (y '<>' z)@, if @y@ non-empty.
--
($$)   :: Doc -> Doc -> Doc

-- | Above, with no overlapping.
-- '$+$' is associative, with identity 'empty'.
($+$)   :: Doc -> Doc -> Doc

hcat   :: [Doc] -> Doc;          -- ^List version of '<>'.
hsep   :: [Doc] -> Doc;          -- ^List version of '<+>'.
vcat   :: [Doc] -> Doc;          -- ^List version of '$$'.

cat    :: [Doc] -> Doc;          -- ^ Either 'hcat' or 'vcat'.
sep    :: [Doc] -> Doc;          -- ^ Either 'hsep' or 'vcat'.
fcat   :: [Doc] -> Doc;          -- ^ \"Paragraph fill\" version of 'cat'.
fsep   :: [Doc] -> Doc;          -- ^ \"Paragraph fill\" version of 'sep'.

-- | Nest (or indent) a document by a given number of positions
-- (which may also be negative).  'nest' satisfies the laws:
--
-- * @'nest' 0 x = x@
--
-- * @'nest' k ('nest' k' x) = 'nest' (k+k') x@
--
-- * @'nest' k (x '<>' y) = 'nest' k z '<>' 'nest' k y@
--
-- * @'nest' k (x '$$' y) = 'nest' k x '$$' 'nest' k y@
--
-- * @'nest' k 'empty' = 'empty'@
--
-- * @x '<>' 'nest' k y = x '<>' y@, if @x@ non-empty
--
-- The side condition on the last law is needed because
-- 'empty' is a left identity for '<>'.
nest   :: Int -> Doc -> Doc

-- GHC-specific ones.

-- | @hang d1 n d2 = sep [d1, nest n d2]@
hang :: Doc -> Int -> Doc -> Doc

-- | @punctuate p [d1, ... dn] = [d1 \<> p, d2 \<> p, ... dn-1 \<> p, dn]@
punctuate :: Doc -> [Doc] -> [Doc]


-- Displaying @Doc@ values.

instance Show Doc where
  showsPrec _ doc cont = showDoc doc cont

-- | Renders the document as a string using the default 'style'.
render     :: Doc -> String

-- | The general rendering interface.
fullRender :: Mode                      -- ^Rendering mode
           -> Int                       -- ^Line length
           -> Float                     -- ^Ribbons per line
           -> (TextDetails -> a -> a)   -- ^What to do with text
           -> a                         -- ^What to do at the end
           -> Doc                       -- ^The document
           -> a                         -- ^Result

-- | Render the document as a string using a specified style.
renderStyle  :: Style -> Doc -> String

-- | A rendering style.
data Style
 = Style { mode           :: Mode     -- ^ The rendering mode
         , lineLength     :: Int      -- ^ Length of line, in chars
         , ribbonsPerLine :: Float    -- ^ Ratio of ribbon length to line length
         }

-- | The default style (@mode=PageMode, lineLength=100, ribbonsPerLine=1.5@).
style :: Style
style = Style { lineLength = 100, ribbonsPerLine = 1.5, mode = PageMode }

-- | Rendering mode.
data Mode = PageMode            -- ^Normal
          | ZigZagMode          -- ^With zig-zag cuts
          | LeftMode            -- ^No indentation, infinitely long lines
          | OneLineMode         -- ^All on one line

-- ---------------------------------------------------------------------------
-- The Doc calculus

-- The Doc combinators satisfy the following laws:

{-
Laws for $$
~~~~~~~~~~~
<a1>    (x $$ y) $$ z   = x $$ (y $$ z)
<a2>    empty $$ x      = x
<a3>    x $$ empty      = x

        ...ditto $+$...

Laws for <>
~~~~~~~~~~~
<b1>    (x <> y) <> z   = x <> (y <> z)
<b2>    empty <> x      = empty
<b3>    x <> empty      = x

        ...ditto <+>...

Laws for text
~~~~~~~~~~~~~
<t1>    text s <> text t        = text (s++t)
<t2>    text "" <> x            = x, if x non-empty

** because of law n6, t2 only holds if x doesn't
** start with `nest'.


Laws for nest
~~~~~~~~~~~~~
<n1>    nest 0 x                = x
<n2>    nest k (nest k' x)      = nest (k+k') x
<n3>    nest k (x <> y)         = nest k x <> nest k y
<n4>    nest k (x $$ y)         = nest k x $$ nest k y
<n5>    nest k empty            = empty
<n6>    x <> nest k y           = x <> y, if x non-empty

** Note the side condition on <n6>!  It is this that
** makes it OK for empty to be a left unit for <>.

Miscellaneous
~~~~~~~~~~~~~
<m1>    (text s <> x) $$ y = text s <> ((text "" <> x) $$
                                         nest (-length s) y)

<m2>    (x $$ y) <> z = x $$ (y <> z)
        if y non-empty


Laws for list versions
~~~~~~~~~~~~~~~~~~~~~~
<l1>    sep (ps++[empty]++qs)   = sep (ps ++ qs)
        ...ditto hsep, hcat, vcat, fill...

<l2>    nest k (sep ps) = sep (map (nest k) ps)
        ...ditto hsep, hcat, vcat, fill...

Laws for oneLiner
~~~~~~~~~~~~~~~~~
<o1>    oneLiner (nest k p) = nest k (oneLiner p)
<o2>    oneLiner (x <> y)   = oneLiner x <> oneLiner y

You might think that the following verion of <m1> would
be neater:

<3 NO>  (text s <> x) $$ y = text s <> ((empty <> x)) $$
                                         nest (-length s) y)

But it doesn't work, for if x=empty, we would have

        text s $$ y = text s <> (empty $$ nest (-length s) y)
                    = text s <> nest (-length s) y
-}

-- ---------------------------------------------------------------------------
-- Simple derived definitions

semi  = char ';'
colon = char ':'
comma = char ','
space = char ' '
equals = char '='
lparen = char '('
rparen = char ')'
lbrack = char '['
rbrack = char ']'
lbrace = char '{'
rbrace = char '}'

int      n = text (show n)
integer  n = text (show n)
float    n = text (show n)
double   n = text (show n)
rational n = text (show n)
-- SIGBJORN wrote instead:
-- rational n = text (show (fromRationalX n))

quotes p        = char '\'' <> p <> char '\''
doubleQuotes p  = char '"' <> p <> char '"'
parens p        = char '(' <> p <> char ')'
brackets p      = char '[' <> p <> char ']'
braces p        = char '{' <> p <> char '}'

-- lazy list versions
hcat = reduceAB . foldr (beside_' False) empty
hsep = reduceAB . foldr (beside_' True)  empty
vcat = reduceAB . foldr (above_' False) empty

beside_' :: Bool -> Doc -> Doc -> Doc
beside_' _ p Empty = p
beside_' g p q = Beside p g q

above_' :: Bool -> Doc -> Doc -> Doc
above_' _ p Empty = p
above_' g p q = Above p g q

reduceAB :: Doc -> Doc
reduceAB (Above Empty _ q) = q
reduceAB (Beside Empty _ q) = q
reduceAB doc = doc

hang d1 n d2 = sep [d1, nest n d2]

punctuate _ []     = []
punctuate p (d:ds) = go d ds
                   where
                     go d' [] = [d']
                     go d' (e:es) = (d' <> p) : go e es

-- ---------------------------------------------------------------------------
-- The Doc data type

-- A Doc represents a *set* of layouts.  A Doc with
-- no occurrences of Union or NoDoc represents just one layout.

-- | The abstract type of documents.
-- The 'Show' instance is equivalent to using 'render'.
data Doc
 = Empty                                -- empty
 | NilAbove Doc                         -- text "" $$ x
 | TextBeside TextDetails !Int Doc      -- text s <> x
 | Nest !Int Doc                        -- nest k x
 | Union Doc Doc                        -- ul `union` ur
 | NoDoc                                -- The empty set of documents
 | Beside Doc Bool Doc                  -- True <=> space between
 | Above  Doc Bool Doc                  -- True <=> never overlap

-- RDoc is a "reduced Doc", guaranteed not to have a top-level Above or Beside
type RDoc = Doc


reduceDoc :: Doc -> RDoc
reduceDoc (Beside p g q) = beside p g (reduceDoc q)
reduceDoc (Above  p g q) = above  p g (reduceDoc q)
reduceDoc p              = p


data TextDetails = Chr  Char
                 | Str  String
                 | PStr String
space_text, nl_text :: TextDetails
space_text = Chr ' '
nl_text    = Chr '\n'

{-
  Here are the invariants:

  1) The argument of NilAbove is never Empty. Therefore
     a NilAbove occupies at least two lines.

  2) The argument of @TextBeside@ is never @Nest@.


  3) The layouts of the two arguments of @Union@ both flatten to the same
     string.

  4) The arguments of @Union@ are either @TextBeside@, or @NilAbove@.

  5) A @NoDoc@ may only appear on the first line of the left argument of an
     union. Therefore, the right argument of an union can never be equivalent
     to the empty set (@NoDoc@).

  6) An empty document is always represented by @Empty@.  It can't be
     hidden inside a @Nest@, or a @Union@ of two @Empty@s.

  7) The first line of every layout in the left argument of @Union@ is
     longer than the first line of any layout in the right argument.
     (1) ensures that the left argument has a first line.  In view of
     (3), this invariant means that the right argument must have at
     least two lines.
-}

-- Invariant: Args to the 4 functions below are always RDocs
nilAbove_ :: RDoc -> RDoc
nilAbove_ p = NilAbove p

        -- Arg of a TextBeside is always an RDoc
textBeside_ :: TextDetails -> Int -> RDoc -> RDoc
textBeside_ s sl p = TextBeside s sl p

nest_ :: Int -> RDoc -> RDoc
nest_ k p = Nest k p

union_ :: RDoc -> RDoc -> RDoc
union_ p q = Union p q


-- Notice the difference between
--         * NoDoc (no documents)
--         * Empty (one empty document; no height and no width)
--         * text "" (a document containing the empty string;
--                    one line high, but has no width)


-- ---------------------------------------------------------------------------
-- @empty@, @text@, @nest@, @union@

empty = Empty

isEmpty Empty = True
isEmpty _     = False

char  c = textBeside_ (Chr c) 1 Empty
text  s = case length s of {sl -> textBeside_ (Str s)  sl Empty}
ptext s = case length s of {sl -> textBeside_ (PStr s) sl Empty}
sizedText l s = textBeside_ (Str s) l Empty
zeroWidthText = sizedText 0

nest k  p = mkNest k (reduceDoc p)        -- Externally callable version

-- mkNest checks for Nest's invariant that it doesn't have an Empty inside it
mkNest :: Int -> Doc -> Doc
mkNest k       _           | k `seq` False = undefined
mkNest k       (Nest k1 p) = mkNest (k + k1) p
mkNest _       NoDoc       = NoDoc
mkNest _       Empty       = Empty
mkNest 0       p           = p                  -- Worth a try!
mkNest k       p           = nest_ k p

-- mkUnion checks for an empty document
mkUnion :: Doc -> Doc -> Doc
mkUnion Empty _ = Empty
mkUnion p q     = p `union_` q

-- ---------------------------------------------------------------------------
-- Vertical composition @$$@

above_ :: Doc -> Bool -> Doc -> Doc
above_ p _ Empty = p
above_ Empty _ q = q
above_ p g q = Above p g q

p $$  q = above_ p False q
p $+$ q = above_ p True q

above :: Doc -> Bool -> RDoc -> RDoc
above (Above p g1 q1)  g2 q2 = above p g1 (above q1 g2 q2)
above p@(Beside _ _ _) g  q  = aboveNest (reduceDoc p) g 0 (reduceDoc q)
above p g q                  = aboveNest p             g 0 (reduceDoc q)

aboveNest :: RDoc -> Bool -> Int -> RDoc -> RDoc
-- Specfication: aboveNest p g k q = p $g$ (nest k q)

aboveNest _                   _ k _ | k `seq` False = undefined
aboveNest NoDoc               _ _ _ = NoDoc
aboveNest (p1 `Union` p2)     g k q = aboveNest p1 g k q `union_`
                                      aboveNest p2 g k q

aboveNest Empty               _ k q = mkNest k q
aboveNest (Nest k1 p)         g k q = nest_ k1 (aboveNest p g (k - k1) q)
                                  -- p can't be Empty, so no need for mkNest

aboveNest (NilAbove p)        g k q = nilAbove_ (aboveNest p g k q)
aboveNest (TextBeside s sl p) g k q = k1 `seq` textBeside_ s sl rest
                                    where
                                      k1   = k - sl
                                      rest = case p of
                                                Empty -> nilAboveNest g k1 q
                                                _     -> aboveNest  p g k1 q
aboveNest (Above {})          _ _ _ = error "aboveNest Above"
aboveNest (Beside {})         _ _ _ = error "aboveNest Beside"


nilAboveNest :: Bool -> Int -> RDoc -> RDoc
-- Specification: text s <> nilaboveNest g k q
--              = text s <> (text "" $g$ nest k q)

nilAboveNest _ k _           | k `seq` False = undefined
nilAboveNest _ _ Empty       = Empty
                               -- Here's why the "text s <>" is in the spec!
nilAboveNest g k (Nest k1 q) = nilAboveNest g (k + k1) q

nilAboveNest g k q           | not g && k > 0      -- No newline if no overlap
                             = textBeside_ (Str (indent k)) k q
                             | otherwise           -- Put them really above
                             = nilAbove_ (mkNest k q)

-- ---------------------------------------------------------------------------
-- Horizontal composition @<>@

beside_ :: Doc -> Bool -> Doc -> Doc
beside_ p _ Empty = p
beside_ Empty _ q = q
beside_ p g q = Beside p g q

p <>  q = beside_ p False q
p <+> q = beside_ p True  q

beside :: Doc -> Bool -> RDoc -> RDoc
-- Specification: beside g p q = p <g> q

beside NoDoc               _ _   = NoDoc
beside (p1 `Union` p2)     g q   = beside p1 g q `union_` beside p2 g q
beside Empty               _ q   = q
beside (Nest k p)          g q   = nest_ k (beside p g q)       -- p non-empty
beside p@(Beside p1 g1 q1) g2 q2
           {- (A `op1` B) `op2` C == A `op1` (B `op2` C)  iff op1 == op2
                                             [ && (op1 == <> || op1 == <+>) ] -}
         | g1 == g2              = beside p1 g1 (beside q1 g2 q2)
         | otherwise             = beside (reduceDoc p) g2 q2
beside p@(Above _ _ _)     g q   = beside (reduceDoc p) g q
beside (NilAbove p)        g q   = nilAbove_ (beside p g q)
beside (TextBeside s sl p) g q   = textBeside_ s sl rest
                               where
                                  rest = case p of
                                           Empty -> nilBeside g q
                                           _     -> beside p g q


nilBeside :: Bool -> RDoc -> RDoc
-- Specification: text "" <> nilBeside g p
--              = text "" <g> p

nilBeside _ Empty      = Empty  -- Hence the text "" in the spec
nilBeside g (Nest _ p) = nilBeside g p
nilBeside g p          | g         = textBeside_ space_text 1 p
                       | otherwise = p

-- ---------------------------------------------------------------------------
-- Separate, @sep@, Hughes version

-- Specification: sep ps  = oneLiner (hsep ps)
--                         `union`
--                          vcat ps

sep = sepX True         -- Separate with spaces
cat = sepX False        -- Don't

sepX :: Bool -> [Doc] -> Doc
sepX _ []     = empty
sepX x (p:ps) = sep1 x (reduceDoc p) 0 ps


-- Specification: sep1 g k ys = sep (x : map (nest k) ys)
--                            = oneLiner (x <g> nest k (hsep ys))
--                              `union` x $$ nest k (vcat ys)

sep1 :: Bool -> RDoc -> Int -> [Doc] -> RDoc
sep1 _ _                   k _  | k `seq` False = undefined
sep1 _ NoDoc               _ _  = NoDoc
sep1 g (p `Union` q)       k ys = sep1 g p k ys
                                  `union_`
                                  aboveNest q False k (reduceDoc (vcat ys))

sep1 g Empty               k ys = mkNest k (sepX g ys)
sep1 g (Nest n p)          k ys = nest_ n (sep1 g p (k - n) ys)

sep1 _ (NilAbove p)        k ys = nilAbove_
                                  (aboveNest p False k (reduceDoc (vcat ys)))
sep1 g (TextBeside s sl p) k ys = textBeside_ s sl (sepNB g p (k - sl) ys)
sep1 _ (Above {})          _ _  = error "sep1 Above"
sep1 _ (Beside {})         _ _  = error "sep1 Beside"

-- Specification: sepNB p k ys = sep1 (text "" <> p) k ys
-- Called when we have already found some text in the first item
-- We have to eat up nests

sepNB :: Bool -> Doc -> Int -> [Doc] -> Doc

sepNB g (Nest _ p)  k ys  = sepNB g p k ys
                            -- Never triggered, because of invariant (2)

sepNB g Empty k ys        = oneLiner (nilBeside g (reduceDoc rest))
                                `mkUnion`
                            nilAboveNest True k (reduceDoc (vcat ys))
                          where
                            rest | g         = hsep ys
                                 | otherwise = hcat ys

sepNB g p k ys            = sep1 g p k ys

-- ---------------------------------------------------------------------------
-- @fill@

fsep = fill True
fcat = fill False

-- Specification:
--
-- fill g docs = fillIndent 0 docs
--
-- fillIndent k [] = []
-- fillIndent k [p] = p
-- fillIndent k (p1:p2:ps) =
--    oneLiner p1 <g> fillIndent (k + length p1 + g ? 1 : 0)
--                               (remove_nests (oneLiner p2) : ps)
--     `Union`
--    (p1 $*$ nest (-k) (fillIndent 0 ps))
--
-- $*$ is defined for layouts (not Docs) as
-- layout1 $*$ layout2 | hasMoreThanOneLine layout1 = layout1 $$ layout2
--                     | otherwise                  = layout1 $+$ layout2

fill :: Bool -> [Doc] -> RDoc
fill _ []     = empty
fill g (p:ps) = fill1 g (reduceDoc p) 0 ps


fill1 :: Bool -> RDoc -> Int -> [Doc] -> Doc
fill1 _ _                   k _  | k `seq` False = undefined
fill1 _ NoDoc               _ _  = NoDoc
fill1 g (p `Union` q)       k ys = fill1 g p k ys
                                   `union_`
                                   aboveNest q False k (fill g ys)

fill1 g Empty               k ys = mkNest k (fill g ys)
fill1 g (Nest n p)          k ys = nest_ n (fill1 g p (k - n) ys)

fill1 g (NilAbove p)        k ys = nilAbove_ (aboveNest p False k (fill g ys))
fill1 g (TextBeside s sl p) k ys = textBeside_ s sl (fillNB g p (k - sl) ys)
fill1 _ (Above {})          _ _  = error "fill1 Above"
fill1 _ (Beside {})         _ _  = error "fill1 Beside"

fillNB :: Bool -> Doc -> Int -> [Doc] -> Doc
fillNB _ _           k _  | k `seq` False = undefined
fillNB g (Nest _ p)  k ys  = fillNB g p k ys
                             -- Never triggered, because of invariant (2)
fillNB _ Empty _ []        = Empty
fillNB g Empty k (Empty:ys)  = fillNB g Empty k ys
fillNB g Empty k (y:ys)    = fillNBE g k y ys
fillNB g p k ys            = fill1 g p k ys

fillNBE :: Bool -> Int -> Doc -> [Doc] -> Doc
fillNBE g k y ys           = nilBeside g
                             (fill1 g ((elideNest . oneLiner . reduceDoc) y)
                                      k1 ys)
                             `mkUnion`
                             nilAboveNest True k (fill g (y:ys))
                           where
                             k1 | g         = k - 1
                                | otherwise = k

elideNest :: Doc -> Doc
elideNest (Nest _ d) = d
elideNest d = d

-- ---------------------------------------------------------------------------
-- Selecting the best layout

best :: Mode
     -> Int             -- Line length
     -> Int             -- Ribbon length
     -> RDoc
     -> RDoc            -- No unions in here!

best OneLineMode _ _ p0
  = get p0 -- unused, due to the use of easy_display in full_render
  where
    get Empty               = Empty
    get NoDoc               = NoDoc
    get (NilAbove p)        = nilAbove_ (get p)
    get (TextBeside s sl p) = textBeside_ s sl (get p)
    get (Nest _ p)          = get p             -- Elide nest
    get (p `Union` q)       = first (get p) (get q)
    get (Above {})          = error "best OneLineMode get Above"
    get (Beside {})         = error "best OneLineMode get Beside"

best _ w0 r p0
  = get w0 p0
  where
    get :: Int          -- (Remaining) width of line
        -> Doc -> Doc
    get w _ | w==0 && False   = undefined
    get _ Empty               = Empty
    get _ NoDoc               = NoDoc
    get w (NilAbove p)        = nilAbove_ (get w p)
    get w (TextBeside s sl p) = textBeside_ s sl (get1 w sl p)
    get w (Nest k p)          = nest_ k (get (w - k) p)
    get w (p `Union` q)       = nicest w r (get w p) (get w q)
    get _ (Above {})          = error "best get Above"
    get _ (Beside {})         = error "best get Beside"

    get1 :: Int         -- (Remaining) width of line
         -> Int         -- Amount of first line already eaten up
         -> Doc         -- This is an argument to TextBeside => eat Nests
         -> Doc         -- No unions in here!

    get1 w _ _ | w==0 && False = undefined
    get1 _ _  Empty               = Empty
    get1 _ _  NoDoc               = NoDoc
    get1 w sl (NilAbove p)        = nilAbove_ (get (w - sl) p)
    get1 w sl (TextBeside t tl p) = textBeside_ t tl (get1 w (sl + tl) p)
    get1 w sl (Nest _ p)          = get1 w sl p
    get1 w sl (p `Union` q)       = nicest1 w r sl (get1 w sl p)
                                                   (get1 w sl q)
    get1 _ _  (Above {})          = error "best get1 Above"
    get1 _ _  (Beside {})         = error "best get1 Beside"

nicest :: Int -> Int -> Doc -> Doc -> Doc
nicest w r p q = nicest1 w r 0 p q

nicest1 :: Int -> Int -> Int -> Doc -> Doc -> Doc
nicest1 w r sl p q | fits ((w `minn` r) - sl) p = p
                   | otherwise                   = q

fits :: Int     -- Space available
     -> Doc
     -> Bool    -- True if *first line* of Doc fits in space available

fits n _    | n < 0 = False
fits _ NoDoc               = False
fits _ Empty               = True
fits _ (NilAbove _)        = True
fits n (TextBeside _ sl p) = fits (n - sl) p
fits _ (Above {})          = error "fits Above"
fits _ (Beside {})         = error "fits Beside"
fits _ (Union {})          = error "fits Union"
fits _ (Nest {})           = error "fits Nest"

minn :: Int -> Int -> Int
minn x y | x < y    = x
         | otherwise = y

-- @first@ and @nonEmptySet@ are similar to @nicest@ and @fits@, only simpler.
-- @first@ returns its first argument if it is non-empty, otherwise its second.

first :: Doc -> Doc -> Doc
first p q | nonEmptySet p = p -- unused, because (get OneLineMode) is unused
          | otherwise     = q

nonEmptySet :: Doc -> Bool
nonEmptySet NoDoc           = False
nonEmptySet (_ `Union` _)      = True
nonEmptySet Empty              = True
nonEmptySet (NilAbove _)       = True           -- NoDoc always in first line
nonEmptySet (TextBeside _ _ p) = nonEmptySet p
nonEmptySet (Nest _ p)         = nonEmptySet p
nonEmptySet (Above {})         = error "nonEmptySet Above"
nonEmptySet (Beside {})        = error "nonEmptySet Beside"

-- @oneLiner@ returns the one-line members of the given set of @Doc@s.

oneLiner :: Doc -> Doc
oneLiner NoDoc               = NoDoc
oneLiner Empty               = Empty
oneLiner (NilAbove _)        = NoDoc
oneLiner (TextBeside s sl p) = textBeside_ s sl (oneLiner p)
oneLiner (Nest k p)          = nest_ k (oneLiner p)
oneLiner (p `Union` _)       = oneLiner p
oneLiner (Above {})          = error "oneLiner Above"
oneLiner (Beside {})         = error "oneLiner Beside"


-- ---------------------------------------------------------------------------
-- Displaying the best layout

renderStyle the_style doc
  = fullRender (mode the_style)
               (lineLength the_style)
               (ribbonsPerLine the_style)
               string_txt
               ""
               doc

render doc       = showDoc doc ""

showDoc :: Doc -> String -> String
showDoc doc rest = fullRender PageMode 100 1.5 string_txt rest doc

string_txt :: TextDetails -> String -> String
string_txt (Chr c)   s  = c:s
string_txt (Str s1)  s2 = s1 ++ s2
string_txt (PStr s1) s2 = s1 ++ s2


fullRender OneLineMode _ _ txt end doc
  = easy_display space_text txt end (reduceDoc doc)
fullRender LeftMode    _ _ txt end doc
  = easy_display nl_text    txt end (reduceDoc doc)

fullRender the_mode line_length ribbons_per_line txt end doc
  = display the_mode line_length ribbon_length txt end best_doc
  where
    best_doc = best the_mode hacked_line_length ribbon_length (reduceDoc doc)

    hacked_line_length, ribbon_length :: Int
    ribbon_length = round (fromIntegral line_length / ribbons_per_line)
    hacked_line_length = case the_mode of
                         ZigZagMode -> maxBound
                         _ -> line_length

display :: Mode -> Int -> Int -> (TextDetails -> a -> a) -> a -> Doc -> a
display the_mode page_width ribbon_width txt end doc
  = case page_width - ribbon_width of { gap_width ->
    case gap_width `quot` 2 of { shift ->
    let
        lay k _            | k `seq` False = undefined
        lay k (Nest k1 p)  = lay (k + k1) p
        lay _ Empty        = end
        lay _ (Above {})   = error "display lay Above"
        lay _ (Beside {})  = error "display lay Beside"
        lay _ NoDoc        = error "display lay NoDoc"
        lay _ (Union {})   = error "display lay Union"

        lay k (NilAbove p) = nl_text `txt` lay k p

        lay k (TextBeside s sl p)
            = case the_mode of
                    ZigZagMode |  k >= gap_width
                               -> nl_text `txt` (
                                  Str (replicate shift '/') `txt` (
                                  nl_text `txt`
                                  lay1 (k - shift) s sl p ))

                               |  k < 0
                               -> nl_text `txt` (
                                  Str (replicate shift '\\') `txt` (
                                  nl_text `txt`
                                  lay1 (k + shift) s sl p ))

                    _ -> lay1 k s sl p

        lay1 k _ sl _ | k+sl `seq` False = undefined
        lay1 k s sl p = Str (indent k) `txt` (s `txt` lay2 (k + sl) p)

        lay2 k _ | k `seq` False = undefined
        lay2 k (NilAbove p)        = nl_text `txt` lay k p
        lay2 k (TextBeside s sl p) = s `txt` lay2 (k + sl) p
        lay2 k (Nest _ p)          = lay2 k p
        lay2 _ Empty               = end
        lay2 _ (Above {})          = error "display lay2 Above"
        lay2 _ (Beside {})         = error "display lay2 Beside"
        lay2 _ NoDoc               = error "display lay2 NoDoc"
        lay2 _ (Union {})          = error "display lay2 Union"
    in
    lay 0 doc
    }}

cant_fail :: a
cant_fail = error "easy_display: NoDoc"

easy_display :: TextDetails -> (TextDetails -> a -> a) -> a -> Doc -> a
easy_display nl_space_text txt end doc
  = lay doc cant_fail
  where
    lay NoDoc               no_doc = no_doc
    lay (Union _p q)        _      = {- lay p -} lay q cant_fail
        -- Second arg can't be NoDoc
    lay (Nest _ p)          no_doc = lay p no_doc
    lay Empty               _      = end
    lay (NilAbove p)        _      = nl_space_text `txt` lay p cant_fail
        -- NoDoc always on first line
    lay (TextBeside s _ p)  no_doc = s `txt` lay p no_doc
    lay (Above {}) _ = error "easy_display Above"
    lay (Beside {}) _ = error "easy_display Beside"

-- an old version inserted tabs being 8 columns apart in the output.
indent :: Int -> String
indent n = replicate n ' '

{-
Q: What is the reason for negative indentation (i.e. argument to indent
   is < 0) ?

A:
This indicates an error in the library client's code.
If we compose a <> b, and the first line of b is more indented than some
other lines of b, the law <n6> (<> eats nests) may cause the pretty
printer to produce an invalid layout:

doc       |0123345
------------------
d1        |a...|
d2        |...b|
          |c...|

d1<>d2    |ab..|
         c|....|

Consider a <> b, let `s' be the length of the last line of `a', `k' the
indentation of the first line of b, and `k0' the indentation of the
left-most line b_i of b.

The produced layout will have negative indentation if `k - k0 > s', as
the first line of b will be put on the (s+1)th column, effectively
translating b horizontally by (k-s). Now if the i^th line of b has an
indentation k0 < (k-s), it is translated out-of-page, causing
`negative indentation'.
-}

