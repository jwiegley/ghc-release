{-# OPTIONS -fno-warn-incomplete-patterns #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and fix
-- any warnings in the module. See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#Warnings
-- for details

-----------------------------------------------------------------------------
--
-- Parsing the top of a Haskell source file to get its module name,
-- imports and options.
--
-- (c) Simon Marlow 2005
-- (c) Lemmih 2006
--
-----------------------------------------------------------------------------

module HeaderInfo ( getImports
                  , getOptionsFromFile, getOptions
                  , optionsErrorMsgs,
                    checkProcessArgsResult ) where

#include "HsVersions.h"

import HscTypes
import Parser		( parseHeader )
import Lexer
import FastString
import HsSyn		( ImportDecl(..), HsModule(..) )
import Module		( ModuleName, moduleName )
import PrelNames        ( gHC_PRIM, mAIN_NAME )
import StringBuffer	( StringBuffer(..), hGetStringBufferBlock
                        , appendStringBuffers )
import SrcLoc
import DynFlags
import ErrUtils
import Util
import Outputable
import Pretty           ()
import Panic
import Maybes
import Bag		( emptyBag, listToBag )

import Exception
import Control.Monad
import System.Exit
import System.IO
import Data.List

getImports :: DynFlags -> StringBuffer -> FilePath -> FilePath
    -> IO ([Located ModuleName], [Located ModuleName], Located ModuleName)
getImports dflags buf filename source_filename = do
  let loc  = mkSrcLoc (mkFastString filename) 1 0
  case unP parseHeader (mkPState buf loc dflags) of
	PFailed span err -> parseError span err
	POk pst rdr_module -> do
          let ms = getMessages pst
          printErrorsAndWarnings dflags ms
          when (errorsFound dflags ms) $ exitWith (ExitFailure 1)
	  case rdr_module of
	    L _ (HsModule mb_mod _ imps _ _ _ _) ->
	      let
                main_loc = mkSrcLoc (mkFastString source_filename) 1 0
		mod = mb_mod `orElse` L (srcLocSpan main_loc) mAIN_NAME
                imps' = filter isHomeImp (map unLoc imps)
	        (src_idecls, ord_idecls) = partition isSourceIdecl imps'
		source_imps   = map getImpMod src_idecls
		ordinary_imps = filter ((/= moduleName gHC_PRIM) . unLoc) 
					(map getImpMod ord_idecls)
		     -- GHC.Prim doesn't exist physically, so don't go looking for it.
	      in
	      return (source_imps, ordinary_imps, mod)
  
parseError :: SrcSpan -> Message -> IO a
parseError span err = throwOneError $ mkPlainErrMsg span err

-- we aren't interested in package imports here, filter them out
isHomeImp :: ImportDecl name -> Bool
isHomeImp (ImportDecl _ (Just p) _ _ _ _) = p == fsLit "this"
isHomeImp (ImportDecl _ Nothing  _ _ _ _) = True

isSourceIdecl :: ImportDecl name -> Bool
isSourceIdecl (ImportDecl _ _ s _ _ _) = s

getImpMod :: ImportDecl name -> Located ModuleName
getImpMod (ImportDecl located_mod _ _ _ _ _) = located_mod

--------------------------------------------------------------
-- Get options
--------------------------------------------------------------


getOptionsFromFile :: DynFlags
                   -> FilePath            -- input file
                   -> IO [Located String] -- options, if any
getOptionsFromFile dflags filename
    = Exception.bracket
	      (openBinaryFile filename ReadMode)
              (hClose)
              (\handle ->
                   do buf <- hGetStringBufferBlock handle blockSize
                      loop handle buf)
    where blockSize = 1024
          loop handle buf
              | len buf == 0 = return []
              | otherwise
              = case getOptions' dflags buf filename of
                  (Nothing, opts) -> return opts
                  (Just buf', opts) -> do nextBlock <- hGetStringBufferBlock handle blockSize
                                          newBuf <- appendStringBuffers buf' nextBlock
                                          if len newBuf == len buf
                                             then return opts
                                             else do opts' <- loop handle newBuf
                                                     return (opts++opts')

getOptions :: DynFlags -> StringBuffer -> FilePath -> [Located String]
getOptions dflags buf filename
    = case getOptions' dflags buf filename of
        (_,opts) -> opts

-- The token parser is written manually because Happy can't
-- return a partial result when it encounters a lexer error.
-- We want to extract options before the buffer is passed through
-- CPP, so we can't use the same trick as 'getImports'.
getOptions' :: DynFlags
            -> StringBuffer         -- Input buffer
            -> FilePath             -- Source file. Used for msgs only.
            -> ( Maybe StringBuffer -- Just => we can use more input
               , [Located String]   -- Options.
               )
getOptions' dflags buf filename
    = parseToks (lexAll (pragState dflags buf loc))
    where loc  = mkSrcLoc (mkFastString filename) 1 0

          getToken (_buf,L _loc tok) = tok
          getLoc (_buf,L loc _tok) = loc
          getBuf (buf,_tok) = buf
          combine opts (flag, opts') = (flag, opts++opts')
          add opt (flag, opts) = (flag, opt:opts)

          parseToks (open:close:xs)
              | IToptions_prag str <- getToken open
              , ITclose_prag       <- getToken close
              = map (L (getLoc open)) (words str) `combine`
                parseToks xs
          parseToks (open:close:xs)
              | ITinclude_prag str <- getToken open
              , ITclose_prag       <- getToken close
              = map (L (getLoc open)) ["-#include",removeSpaces str] `combine`
                parseToks xs
          parseToks (open:close:xs)
              | ITdocOptions str <- getToken open
              , ITclose_prag     <- getToken close
              = map (L (getLoc open)) ["-haddock-opts", removeSpaces str]
                `combine` parseToks xs
          parseToks (open:xs)
              | ITdocOptionsOld str <- getToken open
              = map (L (getLoc open)) ["-haddock-opts", removeSpaces str]
                `combine` parseToks xs
          parseToks (open:xs)
              | ITlanguage_prag <- getToken open
              = parseLanguage xs
          -- The last token before EOF could have been truncated.
          -- We ignore it to be on the safe side.
          parseToks [tok,eof]
              | ITeof <- getToken eof
              = (Just (getBuf tok),[])
          parseToks (eof:_)
              | ITeof <- getToken eof
              = (Just (getBuf eof),[])
          parseToks _ = (Nothing,[])
          parseLanguage ((_buf,L loc (ITconid fs)):rest)
              = checkExtension (L loc fs) `add`
                case rest of
                  (_,L _loc ITcomma):more -> parseLanguage more
                  (_,L _loc ITclose_prag):more -> parseToks more
                  (_,L loc _):_ -> languagePragParseError loc
          parseLanguage (tok:_)
              = languagePragParseError (getLoc tok)
          lexToken t = return t
          lexAll state = case unP (lexer lexToken) state of
                           POk _      t@(L _ ITeof) -> [(buffer state,t)]
                           POk state' t -> (buffer state,t):lexAll state'
                           _ -> [(buffer state,L (last_loc state) ITeof)]

-----------------------------------------------------------------------------
-- Complain about non-dynamic flags in OPTIONS pragmas

checkProcessArgsResult :: [Located String] -> IO ()
checkProcessArgsResult flags
  = when (notNull flags) $
        ghcError $ ProgramError $ showSDoc $ vcat $ map f flags
    where f (L loc flag)
              = hang (ppr loc <> char ':') 4
                     (text "unknown flag in  {-# OPTIONS #-} pragma:" <+>
                      text flag)

-----------------------------------------------------------------------------

checkExtension :: Located FastString -> Located String
checkExtension (L l ext)
-- Checks if a given extension is valid, and if so returns
-- its corresponding flag. Otherwise it throws an exception.
 =  let ext' = unpackFS ext in
    if ext' `elem` supportedLanguages
       || ext' `elem` (map ("No"++) supportedLanguages)
    then L l ("-X"++ext')
    else unsupportedExtnError l ext'

languagePragParseError :: SrcSpan -> a
languagePragParseError loc =
  pgmError 
   (showSDoc (mkLocMessage loc (
     text "cannot parse LANGUAGE pragma: comma-separated list expected")))

unsupportedExtnError :: SrcSpan -> String -> a
unsupportedExtnError loc unsup =
  pgmError (showSDoc (mkLocMessage loc (
                text "unsupported extension: " <>
                text unsup)))


optionsErrorMsgs :: [String] -> [Located String] -> FilePath -> Messages
optionsErrorMsgs unhandled_flags flags_lines _filename
  = (emptyBag, listToBag (map mkMsg unhandled_flags_lines))
  where	unhandled_flags_lines = [ L l f | f <- unhandled_flags, 
					  L l f' <- flags_lines, f == f' ]
        mkMsg (L flagSpan flag) = 
            ErrUtils.mkPlainErrMsg flagSpan $
                    text "unknown flag in  {-# OPTIONS #-} pragma:" <+> text flag

