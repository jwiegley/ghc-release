%
% (c) The AQUA Project, Glasgow University, 1994-1998
%
\section[ErrsUtils]{Utilities for error reporting}

\begin{code}
module ErrUtils (
	Message, mkLocMessage, printError,
	Severity(..),

	ErrMsg, WarnMsg,
        ErrorMessages, WarningMessages,
        errMsgSpans, errMsgContext, errMsgShortDoc, errMsgExtraInfo,
	Messages, errorsFound, emptyMessages,
	mkErrMsg, mkPlainErrMsg, mkLongErrMsg, mkWarnMsg, mkPlainWarnMsg,
	printErrorsAndWarnings, printBagOfErrors, printBagOfWarnings,
	warnIsErrorMsg, mkLongWarnMsg,

	ghcExit,
	doIfSet, doIfSet_dyn, 
	dumpIfSet, dumpIf_core, dumpIfSet_core, dumpIfSet_dyn, dumpIfSet_dyn_or,
        mkDumpDoc, dumpSDoc,

	--  * Messages during compilation
	putMsg,
	errorMsg,
	fatalErrorMsg,
	compilationProgressMsg,
	showPass,
	debugTraceMsg,	
    ) where

#include "HsVersions.h"

import Bag		( Bag, bagToList, isEmptyBag, emptyBag )
import Util		( sortLe )
import Outputable
import SrcLoc
import DynFlags		( DynFlags(..), DynFlag(..), dopt )
import StaticFlags	( opt_ErrorSpans )

import Control.Monad
import System.Exit	( ExitCode(..), exitWith )
import Data.List
import System.IO

-- -----------------------------------------------------------------------------
-- Basic error messages: just render a message with a source location.

type Message = SDoc

data Severity
  = SevInfo
  | SevWarning
  | SevError
  | SevFatal

mkLocMessage :: SrcSpan -> Message -> Message
mkLocMessage locn msg
  | opt_ErrorSpans = hang (ppr locn <> colon) 4 msg
  | otherwise      = hang (ppr (srcSpanStart locn) <> colon) 4 msg
  -- always print the location, even if it is unhelpful.  Error messages
  -- are supposed to be in a standard format, and one without a location
  -- would look strange.  Better to say explicitly "<no location info>".

printError :: SrcSpan -> Message -> IO ()
printError span msg = printErrs (mkLocMessage span msg $ defaultErrStyle)


-- -----------------------------------------------------------------------------
-- Collecting up messages for later ordering and printing.

data ErrMsg = ErrMsg { 
	errMsgSpans     :: [SrcSpan],
	errMsgContext   :: PrintUnqualified,
	errMsgShortDoc  :: Message,
	errMsgExtraInfo :: Message
	}
	-- The SrcSpan is used for sorting errors into line-number order

instance Show ErrMsg where
    show em = showSDoc (errMsgShortDoc em)

type WarnMsg = ErrMsg

-- A short (one-line) error message, with context to tell us whether
-- to qualify names in the message or not.
mkErrMsg :: SrcSpan -> PrintUnqualified -> Message -> ErrMsg
mkErrMsg locn print_unqual msg
  = ErrMsg { errMsgSpans = [locn], errMsgContext = print_unqual
           , errMsgShortDoc = msg, errMsgExtraInfo = empty }

-- Variant that doesn't care about qualified/unqualified names
mkPlainErrMsg :: SrcSpan -> Message -> ErrMsg
mkPlainErrMsg locn msg
  = ErrMsg { errMsgSpans = [locn], errMsgContext = alwaysQualify
           , errMsgShortDoc = msg, errMsgExtraInfo = empty }

-- A long (multi-line) error message, with context to tell us whether
-- to qualify names in the message or not.
mkLongErrMsg :: SrcSpan -> PrintUnqualified -> Message -> Message -> ErrMsg
mkLongErrMsg locn print_unqual msg extra 
 = ErrMsg { errMsgSpans = [locn], errMsgContext = print_unqual
          , errMsgShortDoc = msg, errMsgExtraInfo = extra }

mkWarnMsg :: SrcSpan -> PrintUnqualified -> Message -> WarnMsg
mkWarnMsg = mkErrMsg

mkLongWarnMsg :: SrcSpan -> PrintUnqualified -> Message -> Message -> ErrMsg
mkLongWarnMsg = mkLongErrMsg

-- Variant that doesn't care about qualified/unqualified names
mkPlainWarnMsg :: SrcSpan -> Message -> ErrMsg
mkPlainWarnMsg locn msg = mkWarnMsg locn alwaysQualify msg

type Messages = (Bag WarnMsg, Bag ErrMsg)

type WarningMessages = Bag WarnMsg
type ErrorMessages   = Bag ErrMsg

emptyMessages :: Messages
emptyMessages = (emptyBag, emptyBag)

warnIsErrorMsg :: ErrMsg
warnIsErrorMsg = mkPlainErrMsg noSrcSpan (text "\nFailing due to -Werror.\n")

errorsFound :: DynFlags -> Messages -> Bool
-- The dyn-flags are used to see if the user has specified
-- -Werror, which says that warnings should be fatal
errorsFound dflags (warns, errs) 
  | dopt Opt_WarnIsError dflags = not (isEmptyBag errs) || not (isEmptyBag warns)
  | otherwise  		        = not (isEmptyBag errs)

printErrorsAndWarnings :: DynFlags -> Messages -> IO ()
printErrorsAndWarnings dflags (warns, errs)
  | no_errs && no_warns = return ()
  | no_errs             = do printBagOfWarnings dflags warns
                             when (dopt Opt_WarnIsError dflags) $
                                 errorMsg dflags $
                                     text "\nFailing due to -Werror.\n"
                          -- Don't print any warnings if there are errors
  | otherwise           = printBagOfErrors dflags errs
  where
    no_warns = isEmptyBag warns
    no_errs  = isEmptyBag errs

printBagOfErrors :: DynFlags -> Bag ErrMsg -> IO ()
printBagOfErrors dflags bag_of_errors
  = sequence_   [ let style = mkErrStyle unqual
		  in log_action dflags SevError s style (d $$ e)
		| ErrMsg { errMsgSpans = s:_,
			   errMsgShortDoc = d,
			   errMsgExtraInfo = e,
			   errMsgContext = unqual } <- sorted_errs ]
    where
      bag_ls	  = bagToList bag_of_errors
      sorted_errs = sortLe occ'ed_before bag_ls

      occ'ed_before err1 err2 = 
         case compare (head (errMsgSpans err1)) (head (errMsgSpans err2)) of
		LT -> True
		EQ -> True
		GT -> False

printBagOfWarnings :: DynFlags -> Bag ErrMsg -> IO ()
printBagOfWarnings dflags bag_of_warns
  = sequence_   [ let style = mkErrStyle unqual
		  in log_action dflags SevWarning s style (d $$ e)
		| ErrMsg { errMsgSpans = s:_,
			   errMsgShortDoc = d,
			   errMsgExtraInfo = e,
			   errMsgContext = unqual } <- sorted_errs ]
    where
      bag_ls	  = bagToList bag_of_warns
      sorted_errs = sortLe occ'ed_before bag_ls

      occ'ed_before err1 err2 = 
         case compare (head (errMsgSpans err1)) (head (errMsgSpans err2)) of
		LT -> True
		EQ -> True
		GT -> False

ghcExit :: DynFlags -> Int -> IO ()
ghcExit dflags val
  | val == 0  = exitWith ExitSuccess
  | otherwise = do errorMsg dflags (text "\nCompilation had errors\n\n")
	           exitWith (ExitFailure val)

doIfSet :: Bool -> IO () -> IO ()
doIfSet flag action | flag      = action
		    | otherwise = return ()

doIfSet_dyn :: DynFlags -> DynFlag -> IO () -> IO()
doIfSet_dyn dflags flag action | dopt flag dflags = action
		               | otherwise        = return ()

-- -----------------------------------------------------------------------------
-- Dumping

dumpIfSet :: Bool -> String -> SDoc -> IO ()
dumpIfSet flag hdr doc
  | not flag   = return ()
  | otherwise  = printDump (mkDumpDoc hdr doc)

dumpIf_core :: Bool -> DynFlags -> DynFlag -> String -> SDoc -> IO ()
dumpIf_core cond dflags dflag hdr doc
  | cond
    || verbosity dflags >= 4
    || dopt Opt_D_verbose_core2core dflags
  = dumpSDoc dflags dflag hdr doc

  | otherwise = return ()

dumpIfSet_core :: DynFlags -> DynFlag -> String -> SDoc -> IO ()
dumpIfSet_core dflags flag hdr doc
  = dumpIf_core (dopt flag dflags) dflags flag hdr doc

dumpIfSet_dyn :: DynFlags -> DynFlag -> String -> SDoc -> IO ()
dumpIfSet_dyn dflags flag hdr doc
  | dopt flag dflags || verbosity dflags >= 4 
  = dumpSDoc dflags flag hdr doc
  | otherwise
  = return ()

dumpIfSet_dyn_or :: DynFlags -> [DynFlag] -> String -> SDoc -> IO ()
dumpIfSet_dyn_or dflags flags hdr doc
  | or [dopt flag dflags | flag <- flags]
  || verbosity dflags >= 4 
  = printDump (mkDumpDoc hdr doc)
  | otherwise = return ()

mkDumpDoc :: String -> SDoc -> SDoc
mkDumpDoc hdr doc 
   = vcat [text "", 
	   line <+> text hdr <+> line,
	   doc,
	   text ""]
     where 
        line = text (replicate 20 '=')


-- | Write out a dump.
--	If --dump-to-file is set then this goes to a file.
--	otherwise emit to stdout.
dumpSDoc :: DynFlags -> DynFlag -> String -> SDoc -> IO ()
dumpSDoc dflags dflag hdr doc
 = do	let mFile	= chooseDumpFile dflags dflag
 	case mFile of
		-- write the dump to a file
		--	don't add the header in this case, we can see what kind
		--	of dump it is from the filename.
		Just fileName
		 -> do	handle	<- openFile fileName AppendMode
		 	hPrintDump handle doc
		 	hClose handle

		-- write the dump to stdout
		Nothing
		 -> do	printDump (mkDumpDoc hdr doc)


-- | Choose where to put a dump file based on DynFlags
--
chooseDumpFile :: DynFlags -> DynFlag -> Maybe String
chooseDumpFile dflags dflag

	-- dump file location is being forced
	--	by the --ddump-file-prefix flag.
 	| dumpToFile
	, Just prefix	<- dumpPrefixForce dflags
	= Just $ prefix ++ (beautifyDumpName dflag)

	-- dump file location chosen by DriverPipeline.runPipeline
	| dumpToFile
	, Just prefix	<- dumpPrefix dflags
	= Just $ prefix ++ (beautifyDumpName dflag)

	-- we haven't got a place to put a dump file.
	| otherwise
	= Nothing

	where	dumpToFile = dopt Opt_DumpToFile dflags


-- | Build a nice file name from name of a DynFlag constructor
beautifyDumpName :: DynFlag -> String
beautifyDumpName dflag
 = let	str	= show dflag
 	cut	= if isPrefixOf "Opt_D_" str
			 then drop 6 str
			 else str
	dash	= map	(\c -> case c of
				'_'	-> '-'
				_	-> c)
			cut
   in	dash


-- -----------------------------------------------------------------------------
-- Outputting messages from the compiler

-- We want all messages to go through one place, so that we can
-- redirect them if necessary.  For example, when GHC is used as a
-- library we might want to catch all messages that GHC tries to
-- output and do something else with them.

ifVerbose :: DynFlags -> Int -> IO () -> IO ()
ifVerbose dflags val act
  | verbosity dflags >= val = act
  | otherwise               = return ()

putMsg :: DynFlags -> Message -> IO ()
putMsg dflags msg = log_action dflags SevInfo noSrcSpan defaultUserStyle msg

errorMsg :: DynFlags -> Message -> IO ()
errorMsg dflags msg = log_action dflags SevError noSrcSpan defaultErrStyle msg

fatalErrorMsg :: DynFlags -> Message -> IO ()
fatalErrorMsg dflags msg = log_action dflags SevFatal noSrcSpan defaultErrStyle msg

compilationProgressMsg :: DynFlags -> String -> IO ()
compilationProgressMsg dflags msg
  = ifVerbose dflags 1 (log_action dflags SevInfo noSrcSpan defaultUserStyle (text msg))

showPass :: DynFlags -> String -> IO ()
showPass dflags what 
  = ifVerbose dflags 2 (log_action dflags SevInfo noSrcSpan defaultUserStyle (text "***" <+> text what <> colon))

debugTraceMsg :: DynFlags -> Int -> Message -> IO ()
debugTraceMsg dflags val msg
  = ifVerbose dflags val (log_action dflags SevInfo noSrcSpan defaultDumpStyle msg)

\end{code}
