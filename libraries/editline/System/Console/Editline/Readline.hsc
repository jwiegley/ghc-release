-----------------------------------------------------------------------------
-- |
-- Module      :  System.Console.Editline.Readline
-- Copyright   :  (c) 2008, Judah Jacobson
--                Copied with permission from the readline package
--                    (originally System.Console.Readline):
--                (c) 2007, Isaac Jones
--                (c) 2002, Simon Marlow 
--                (c) 2001, Marcin Kowalczyk
-- License     :  BSD3
-- 
-- Maintainer  :  judah.jacobson@gmail.com
-- Stability   :  provisional
-- Portability :  non-portable (requires libedit)
--
-- This module provides a subset of the functions from
-- "System.Console.Readline", which is distributed in the readline package.
--  However, because this package links against editline
-- (<http://www.thrysoee.dk/editline/>) instead of readline, programs using
-- this module are not required to be distributed under the GPL.
-- 
-- An example of a typical use of the readline API with history functionality
-- is illustrated in the following read, eval, print loop:
--
-- @
-- readEvalPrintLoop :: IO ()
-- readEvalPrintLoop = do
--   maybeLine <- readline \"% \"
--   case maybeLine of 
--    Nothing     -> return () -- EOF \/ control-d
--    Just \"exit\" -> return ()
--    Just line -> do addHistory line
--                    putStrLn $ \"The user input: \" ++ (show line)
--                    readEvalPrintLoop
-- @
--

-----------------------------------------------------------------------------
#include "HsEditlineConfig.h"

#ifdef HAVE_EDITLINE_READLINE_H
#include <editline/readline.h>
#else
#ifdef HAVE_READLINE_READLINE_H
#include <readline/readline.h>
#else
#ifdef HAVE_EDITLINE_EDITLINE_H
#include <editline/editline.h>
#endif
#endif
#endif


module System.Console.Editline.Readline (
    --------------------------------------------------------------------
    -- Basic Behavior.
    
    readline,   -- :: String -> IO (Maybe String)

    --------------------------------------------------------------------
    -- History Functionality.

    addHistory, -- :: String -> IO ()
    readHistory, -- :: String -> IO Bool
    writeHistory, -- :: String -> IO Bool
    clearHistory, -- :: IO ()
    stifleHistory, -- :: Int -> IO ()
    unstifleHistory, -- :: IO Int
    historyIsStifled, -- :: IO Bool
    historyMaxEntries, -- IO Int
    
    --------------------------------------------------------------------
    -- Readline Variables.
    
    getLineBuffer,        -- :: IO String
    
    -- Functions involving point positions are meaningful only when string
    -- conversion between Haskell and C preserves the length.
    getPoint,             -- :: IO Int
    setPoint,             -- :: Int -> IO ()
    getEnd,               -- :: IO Int
    setEnd,               -- :: Int -> IO ()
    getPrompt,            -- :: IO String
    getLibraryVersion,    -- :: IO String
    getTerminalName,      -- :: IO String
    setReadlineName,      -- :: String -> IO ()
    getInStream,          -- :: IO Handle
    getOutStream,         -- :: IO Handle
    setStartupHook,       -- :: Maybe (IO ()) -> IO ()
    -- rl_getc_function wrapper is not provided because it uses FILE *
    -- and it would be too expensive to convert FILE * to Handle
    -- for each character.
    setRedisplayFunction, -- :: Maybe (IO ()) -> IO ()
    -- Nothing means the original: rl_redisplay.
    
    --------------------------------------------------------------------
    -- Binding Keys.
    
    Callback,           -- type Callback = Int -> Char -> IO Int
    addDefun,           -- :: String -> Callback -> Maybe Char -> IO ()
    bindKey,            -- :: Char -> Callback -> IO ()
    parseAndBind,       -- :: String -> IO ()
    readInitFile,       -- :: String -> IO ()
    
    --------------------------------------------------------------------
    -- Redisplay.

    redisplay,                      -- :: IO ()

    --------------------------------------------------------------------
    -- Utility functions.
    
    readKey,          -- :: IO Char
    stuffChar,        -- :: Char -> IO Bool
    initialize,       -- :: IO ()
    resetTerminal,    -- :: Maybe String -> IO ()
    
    --------------------------------------------------------------------
    -- Alternate Interface.
    
    callbackHandlerInstall, -- :: String -> (String -> IO ()) -> IO (IO ())
    -- Returns the cleanup action.
    callbackReadChar,       -- :: IO ()
    
    --------------------------------------------------------------------
    -- Completion functions.
    
    complete,                         -- :: Int -> Char -> IO Int
    -- readline uses functions that are called multiple times and
    -- return an entry at a time, maintaining their state at which
    -- point they are. This is silly in a functional language so here
    -- we work with functions String -> IO [String].
    completionMatches,
        -- :: String -> (String -> IO [String]) -> IO (Maybe (String, [String]))
    filenameCompletionFunction,       -- :: String -> IO [String]
    usernameCompletionFunction,       -- :: String -> IO [String]
    setCompletionEntryFunction,
        -- :: Maybe (String -> IO [String]) -> IO ()
    setAttemptedCompletionFunction,
        -- :: Maybe (String -> Int -> Int -> IO (Maybe (String, [String]))) -> IO ()
    getCompletionQueryItems,          -- :: IO Int
    setCompletionQueryItems,          -- :: Int -> IO ()
    getBasicWordBreakCharacters,      -- :: IO String
    setBasicWordBreakCharacters,      -- :: String -> IO ()
    getCompleterWordBreakCharacters,  -- :: IO String
    setCompleterWordBreakCharacters,  -- :: String -> IO ()
    getCompleterQuoteCharacters,      -- :: IO String
    setCompleterQuoteCharacters,      -- :: String -> IO ()
    getSpecialPrefixes,               -- :: IO String
    setSpecialPrefixes,               -- :: String -> IO ()
    getCompletionAppendCharacter,     -- :: IO (Maybe Char)
    setCompletionAppendCharacter,     -- :: Maybe Char -> IO ()
    setInhibitCompletion,             -- :: Bool -> IO ()
    getInhibitCompletion,             -- :: IO Bool
    setAttemptedCompletionOver,       -- :: Bool -> IO ()
    getAttemptedCompletionOver,       -- :: IO Bool
    )
    
    where

------------------------------------------------------------------------

import Control.Monad	( liftM, when, unless )
import Data.Char	( chr, ord )
import System.IO	( Handle )
import System.IO.Unsafe ( unsafePerformIO )
import Data.IORef	( newIORef, readIORef, writeIORef )
import Foreign.Ptr	( Ptr, nullPtr, FunPtr, nullFunPtr, freeHaskellFunPtr )
import Foreign.Storable	( Storable(..) )
import Foreign.Marshal.Utils ( maybePeek, maybeWith )
import Foreign.Marshal.Alloc ( free )
import Foreign.Marshal.Array ( mallocArray, peekArray0, pokeArray0 )
import Foreign.C.Types	( CInt, CChar, CFile )
import Foreign.C.String	( newCString, peekCString, withCString,
			  castCharToCChar, castCCharToChar )
import GHC.Handle	( fdToHandle )

{-# CFILES HsReadline_cbits.c #-}

------------------------------------------------------------------------
-- Basic Behavior.

-- | readline is similar to 'System.IO.getLine', but with rich edit
-- functionality and history capability.  readline will read a line
-- from the terminal and return it, using /prompt/ as a prompt.  If
-- prompt is the empty string, no prompt is issued.  The line returned
-- has the final newline removed, so only the text of the line
-- remains.  A blank line returns the empty string.  If EOF is
-- encountered while reading a line, and the line is empty, Nothing is
-- returned.  If an EOF is read with a non-empty line, it is treated
-- as a newline.

readline :: String-- ^prompt
	 -> IO (Maybe String) -- ^returns the line the user input, or Nothing if EOF is encountered.
readline prompt = do
    ptr <- withCString prompt readlineC
    flip maybePeek ptr $ \ptr' -> do
        line <- peekCString ptr'
        free ptr'
        return line
foreign import ccall "readline" readlineC :: Ptr CChar -> IO (Ptr CChar)

--------------------------------------------------------------------------
-- History functionality

-- TODO: older versions of libedit don't return errors correctly...

-- |Add this command to the history.  This allows users to search backward
-- through history with C-r and step through with up and down arrows, among
-- other things.
addHistory :: String -> IO ()
addHistory line = withCString line add_history
foreign import ccall unsafe add_history :: Ptr CChar -> IO ()

-- |Read in a history file.  Returns 'False' on failure
-- (for example, if the file does not exist).
readHistory :: FilePath -- ^ The file to read.
            -> IO Bool
readHistory fp = do
  ok <- withCString fp read_history
  return (histResultIsOK ok)
foreign import ccall unsafe read_history :: Ptr CChar -> IO CInt

-- |Write out a history file.  Returns 'False' if there was a problem writing the file.
writeHistory :: FilePath -- ^ The file to write.
             -> IO Bool
writeHistory fp = do
  ok <- withCString fp write_history
  return (histResultIsOK ok)
foreign import ccall unsafe write_history :: Ptr CChar -> IO CInt

histResultIsOK :: CInt -> Bool
#ifdef NEGATIVE_HIST_ERROR
-- Old way that libedit handled errors; different from readline
histResultIsOK = (>=0)
#else
histResultIsOK = (==0)
#endif

-- |Clear the history.
clearHistory :: IO ()
clearHistory = clear_history
foreign import ccall unsafe clear_history :: IO ()

-- |Stifle the history list, remembering only a certain number of entries.
stifleHistory :: Int -> IO ()
stifleHistory n = stifle_history n
foreign import ccall unsafe stifle_history :: Int -> IO ()

-- |Stop stifling the history, returning the previous amount the history was
--  stifled by. 
unstifleHistory :: IO Int
unstifleHistory = unstifle_history
foreign import ccall unsafe unstifle_history :: IO Int

-- |Check whether the history is stifled or not. True if stifled, False if not.
historyIsStifled :: IO Bool
historyIsStifled = do
  isStifledInt <- history_is_stifled
  let isStifled = case isStifledInt of
                    0 -> False
                    1 -> True
                    _ -> error "historyIsStifled: history_is_stifled returned unexpected value (expected 0 or 1, received other)" -- just for completeness - there is no conceivable way readline would not return either 0 or 1 here
  return isStifled
foreign import ccall unsafe history_is_stifled :: IO Int

-- |Get the maximum number of history entries, returning 0 if the history is 
-- unstifled.
historyMaxEntries :: IO Int
historyMaxEntries = liftM fromIntegral (peek max_input_history)

-- Note: this variable is different than history_max_entries, but has the same
-- use.
foreign import ccall "&" max_input_history :: Ptr CInt


------------------------------------------------------------------------
-- Readline Variables.

getLineBuffer :: IO String
getLineBuffer = peek rl_line_buffer >>= peekCString

foreign import ccall "&"
  rl_line_buffer :: Ptr (Ptr CChar)

-- Functions involving point positions are meaningful only when string
-- conversion between Haskell and C preserves the length.

getPoint :: IO Int
getPoint = liftM fromIntegral (peek rl_point)

setPoint :: Int -> IO ()
setPoint p = poke rl_point (fromIntegral p)

foreign import ccall "&" rl_point :: Ptr CInt

getEnd :: IO Int
getEnd = liftM fromIntegral (peek rl_end)

setEnd :: Int -> IO ()
setEnd p = poke rl_end (fromIntegral p)

foreign import ccall "&" rl_end :: Ptr CInt

getPrompt :: IO String
getPrompt = peek rl_prompt >>= peekCString
foreign import ccall "&" rl_prompt :: Ptr (Ptr CChar)

getLibraryVersion :: IO String
getLibraryVersion = peek rl_library_version >>= peekCString
foreign import ccall "&" rl_library_version :: Ptr (Ptr CChar)

getTerminalName :: IO String
getTerminalName = peek rl_terminal_name >>= peekCString
foreign import ccall "&" rl_terminal_name :: Ptr (Ptr CChar)

setReadlineName :: String -> IO ()
setReadlineName name = newCString name >>= poke rl_readline_name
    -- The memory for name will never be freed. Otherwise we would
    -- have to recognize the original value which is a static string
    -- literal. This function is usually called only once anyway.
foreign import ccall "&" rl_readline_name :: Ptr (Ptr CChar)

getInStream :: IO Handle
getInStream = peek rl_instream >>= hs_fileno >>= fdToHandle . fromIntegral
foreign import ccall "&" rl_instream :: Ptr (Ptr CFile)

getOutStream :: IO Handle
getOutStream = peek rl_outstream >>= hs_fileno >>= fdToHandle . fromIntegral
foreign import ccall "&" rl_outstream :: Ptr (Ptr CFile)

foreign import ccall unsafe "__hscore_hs_fileno"
  hs_fileno :: Ptr CFile -> IO CInt

setStartupHook :: Maybe (IO ()) -> IO ()
setStartupHook hook = setFunPtr rl_startup_hook hook exportHookInt
foreign import ccall "&" rl_startup_hook :: Ptr (FunPtr (IO CInt))

-- rl_getc_function wrapper is not provided because it uses FILE *
-- and it would be too expensive to convert FILE * to Handle
-- for each character.

setRedisplayFunction :: Maybe (IO ()) -> IO ()
-- Nothing means the original: rl_redisplay.
setRedisplayFunction fun = do
    oldPtr <- peek rl_redisplay_function
    when (oldPtr /= nullFunPtr && oldPtr /= rl_redisplay) $
        freeHaskellFunPtr oldPtr
    newPtr <- case fun of
        Nothing -> return rl_redisplay
        Just f  -> exportHookVoid f
    poke rl_redisplay_function newPtr
foreign import ccall "&" rl_redisplay_function :: Ptr (FunPtr (IO ()))
foreign import ccall "&" rl_redisplay :: FunPtr (IO ())
-- rl_redisplay_function can never be NULL.

exportHookInt :: IO () -> IO (FunPtr (IO CInt))
exportHookInt hook = exportHookIntC (hook >> return 0)
foreign import ccall "wrapper"
  exportHookIntC :: IO CInt -> IO (FunPtr (IO CInt))

foreign import ccall "wrapper"
  exportHookVoid :: IO () -> IO (FunPtr (IO ()))

setFunPtr_freeIf :: (FunPtr a -> Bool)
                 -> Ptr (FunPtr a)
                 -> Maybe b
                 -> (b -> IO (FunPtr a))
                 -> IO ()
setFunPtr_freeIf predicate variable newFun makeNewFun = do
    oldPtr <- peek variable
    when (predicate oldPtr) $ freeHaskellFunPtr oldPtr
    newPtr <- case newFun of
        Nothing -> return nullFunPtr
        Just f  -> makeNewFun f
    poke variable newPtr

setFunPtr :: Ptr (FunPtr a)
          -> Maybe b
          -> (b -> IO (FunPtr a))
          -> IO ()
setFunPtr = setFunPtr_freeIf (/= nullFunPtr)


------------------------------------------------------------------------
-- Binding Keys.

type Callback = Int -> Char -> IO Int
type CallbackC = CInt -> CInt -> IO CInt

addDefun :: String -> Callback -> Maybe Char -> IO ()
addDefun name cb key = do
    namePtr <- newCString name
    -- rl_add_defun does *not* make a copy of the function name.
    cbPtr <- exportCallback cb
    -- The memory will never be freed. But readline does not provide
    -- removing defuns anyway.
    rl_add_defun namePtr cbPtr (maybe (-1) (fromIntegral . ord) key)
    return ()
foreign import ccall unsafe "rl_add_defun"
    rl_add_defun :: Ptr CChar -> FunPtr CallbackC -> CInt -> IO CInt

bindKey :: Char -> Callback -> IO ()
bindKey key cb = do
    cbPtr <- exportCallback cb
    -- The memory will never be freed. We should provide a way to
    -- free it, but it's complicated because of multiple keymaps.
    -- It should probably be done explicitly.
    rl_bind_key (fromIntegral (ord key)) cbPtr
    return ()
foreign import ccall unsafe "rl_bind_key"
  rl_bind_key :: CInt -> FunPtr CallbackC -> IO CInt

parseAndBind :: String -> IO ()
parseAndBind s = do
    ok <- withCString s rl_parse_and_bind
    unless (ok == 0) $ ioError (userError "Parse error")
foreign import ccall unsafe "rl_parse_and_bind"
  rl_parse_and_bind :: Ptr CChar -> IO CInt

readInitFile :: String -> IO ()
readInitFile name = do
    ok <- withCString name rl_read_init_file
    unless (ok == 0) $ ioError (userError "Can't read file")
foreign import ccall unsafe "rl_read_init_file"
  rl_read_init_file :: Ptr CChar -> IO CInt

------------------------------------------------------------------------
-- Associating Function Names and Bindings.

exportCallback :: Callback -> IO (FunPtr CallbackC)
exportCallback cb =
    exportCallbackC $ \n key ->
        liftM fromIntegral (cb (fromIntegral n) (chr (fromIntegral key)))
foreign import ccall "wrapper" 
  exportCallbackC :: CallbackC -> IO (FunPtr CallbackC)

------------------------------------------------------------------------
-- Redisplay.

foreign import ccall unsafe "rl_redisplay" redisplay :: IO ()

------------------------------------------------------------------------
-- Utility functions.

readKey :: IO Char
readKey = liftM (chr . fromIntegral) rl_read_key
foreign import ccall unsafe "rl_read_key"
  rl_read_key :: IO CInt

stuffChar :: Char -> IO Bool
stuffChar key = liftM (/= 0) (rl_stuff_char (fromIntegral (ord key)))
foreign import ccall unsafe "rl_stuff_char"
  rl_stuff_char :: CInt -> IO CInt

initialize :: IO ()
initialize = do rl_initialize; return ()
foreign import ccall unsafe "rl_initialize"
  rl_initialize :: IO CInt

resetTerminal :: Maybe String -> IO ()
resetTerminal name = do
    maybeWith withCString name rl_reset_terminal
    return ()
foreign import ccall unsafe "rl_reset_terminal"
  rl_reset_terminal :: Ptr CChar -> IO CInt


------------------------------------------------------------------------
-- Alternate Interface.

type Handler = Ptr CChar -> IO ()

callbackHandlerInstall :: String -> (String -> IO ()) -> IO (IO ())
callbackHandlerInstall prompt lhandler = do
    lhandlerPtr <- exportHandler $ \linePtr -> peekCString linePtr >>= lhandler
    withCString prompt $ \promptPtr -> do
        rl_callback_handler_install promptPtr lhandlerPtr
    return (do rl_callback_handler_remove; freeHaskellFunPtr lhandlerPtr)
foreign import ccall "wrapper"
  exportHandler :: Handler -> IO (FunPtr Handler)
foreign import ccall unsafe "rl_callback_handler_install"
  rl_callback_handler_install :: Ptr CChar -> FunPtr Handler -> IO ()
foreign import ccall unsafe "rl_callback_handler_remove"
  rl_callback_handler_remove :: IO ()

foreign import ccall "rl_callback_read_char" 
  callbackReadChar :: IO ()

------------------------------------------------------------------------
-- Completion functions.

complete :: Int -> Char -> IO Int
complete n key =
    liftM fromIntegral $
        rl_complete (fromIntegral n) (fromIntegral (ord key))
foreign import ccall "rl_complete"
  rl_complete :: CInt -> CInt -> IO CInt


type Generator = Ptr CChar -> CInt -> IO (Ptr CChar)

singleToWhole :: Generator -> String -> IO [String]
singleToWhole f text =
    withCString text $ \textPtr -> let
        loop n = do
            ptr <- f textPtr n
            if ptr == nullPtr
                then return []
                else do
                    str <- peekCString ptr
                    free ptr
                    rest <- loop (n+1)
                    return (str:rest)
        in loop 0

wholeToSingle :: (String -> IO [String]) -> IO Generator
wholeToSingle f = do
    ref <- newIORef []
    return $ \textPtr state -> do
        when (state == 0) $ peekCString textPtr >>= f >>= writeIORef ref
        next <- readIORef ref
        case next of
            []   -> return nullPtr
            x:xs -> do
                writeIORef ref xs
                newCString x

completionMatches
    :: String -> (String -> IO [String]) -> IO (Maybe (String, [String]))
completionMatches text entry =
    withCString text $ \textPtr -> do
        entryPtr <- wholeToSingle entry >>= exportGenerator
        matchesPtr <- rl_completion_matches textPtr entryPtr
        freeHaskellFunPtr entryPtr
        if matchesPtr == nullPtr then return Nothing else do
            matchPtrs <- peekArray0 nullPtr matchesPtr
            (text':matches) <- mapM peekCString matchPtrs
            mapM_ free matchPtrs
            free matchesPtr
            return (Just (text', matches))

#ifdef HAVE_RL_COMPLETION_MATCHES
foreign import ccall "rl_completion_matches"
#else
foreign import ccall "completion_matches"
#endif
    rl_completion_matches :: Ptr CChar -> FunPtr Generator -> IO (Ptr (Ptr CChar))

filenameCompletionFunction :: String -> IO [String]
filenameCompletionFunction = singleToWhole rl_filename_completion_function

foreign import ccall unsafe "filename_completion_function"
    rl_filename_completion_function :: Generator

usernameCompletionFunction :: String -> IO [String]
usernameCompletionFunction = singleToWhole rl_username_completion_function

foreign import ccall unsafe "username_completion_function"
    rl_username_completion_function :: Generator

setCompletionEntryFunction :: Maybe (String -> IO [String]) -> IO ()
setCompletionEntryFunction fun =
    setFunPtr rl_completion_entry_function fun $ \f ->
        wholeToSingle f >>= exportGenerator
foreign import ccall "&" rl_completion_entry_function :: Ptr (FunPtr Generator)

foreign import ccall "wrapper"
    exportGenerator :: Generator -> IO (FunPtr Generator)

type Completer = Ptr CChar -> CInt -> CInt -> IO (Ptr (Ptr CChar))

setAttemptedCompletionFunction
    :: Maybe (String -> Int -> Int -> IO (Maybe (String, [String]))) -> IO ()
setAttemptedCompletionFunction fun =
    setFunPtr rl_attempted_completion_function fun $ \f ->
        exportCompleter $ \textPtr start end -> do
            text <- peekCString textPtr
            found <- f text (fromIntegral start) (fromIntegral end)
            case found of
                Nothing -> return nullPtr
                Just (text', matches) -> do
                    let matches' = if null matches then [text'] else matches
                    matchPtrs <- mapM newCString (text':matches')
                    matchesPtr <- mallocArray (length matchPtrs + 1)
                    pokeArray0 nullPtr matchesPtr matchPtrs
                    return matchesPtr

foreign import ccall "&"   rl_attempted_completion_function :: Ptr (FunPtr Completer)
foreign import ccall "wrapper"
    exportCompleter :: Completer -> IO (FunPtr Completer)


getCompletionQueryItems :: IO Int
getCompletionQueryItems =
    liftM fromIntegral (peek rl_completion_query_items)

setCompletionQueryItems :: Int -> IO ()
setCompletionQueryItems items =
    poke rl_completion_query_items (fromIntegral items)

foreign import ccall "&" rl_completion_query_items :: Ptr CInt

getBasicWordBreakCharacters :: IO String
getBasicWordBreakCharacters = getCharacters rl_basic_word_break_characters

setBasicWordBreakCharacters :: String -> IO ()
setBasicWordBreakCharacters =
    setCharacters_freeIf
        (/= orig_rl_basic_word_break_characters)
        rl_basic_word_break_characters

foreign import ccall "&" rl_basic_word_break_characters :: Ptr (Ptr CChar)

-- Similarly to rl_quote_filename, we must be able to detect the
-- original pointer to a static char array.

{-# NOINLINE orig_rl_basic_word_break_characters #-}
orig_rl_basic_word_break_characters :: Ptr CChar
orig_rl_basic_word_break_characters = unsafePerformIO $
    peek rl_basic_word_break_characters

getCompleterWordBreakCharacters :: IO String
getCompleterWordBreakCharacters = getCharacters rl_completer_word_break_characters

setCompleterWordBreakCharacters :: String -> IO ()
setCompleterWordBreakCharacters =
    setCharacters_freeIf
        (\oldPtr -> oldPtr /= nullPtr &&
                    oldPtr /= orig_rl_basic_word_break_characters)
        rl_completer_word_break_characters

foreign import ccall "&" rl_completer_word_break_characters :: Ptr (Ptr CChar)

getCompleterQuoteCharacters :: IO String
getCompleterQuoteCharacters = getCharacters rl_completer_quote_characters

setCompleterQuoteCharacters :: String -> IO ()
setCompleterQuoteCharacters cs = do
    oldPtr <- peek rl_completer_quote_characters
    when (oldPtr /= nullPtr) $ free oldPtr
    -- I think that rl_completer_quote_characters should never be empty
    -- but can be NULL.
    newPtr <- if null cs
        then return nullPtr
        else do
            ptr <- mallocArray (length cs + 1)
            pokeArray0 0 ptr (map castCharToCChar cs)
            return ptr
    poke rl_completer_quote_characters newPtr

foreign import ccall "&" rl_completer_quote_characters :: Ptr (Ptr CChar)

getSpecialPrefixes :: IO String
getSpecialPrefixes = getCharacters rl_special_prefixes

setSpecialPrefixes :: String -> IO ()
setSpecialPrefixes = setCharacters rl_special_prefixes

foreign import ccall "&" rl_special_prefixes :: Ptr (Ptr CChar)

getCompletionAppendCharacter :: IO (Maybe Char)
getCompletionAppendCharacter = do
    ch <- peek rl_completion_append_character
    return $ if ch == 0 then Nothing else Just (chr (fromIntegral ch))

setCompletionAppendCharacter :: Maybe Char -> IO ()
setCompletionAppendCharacter ch =
    poke rl_completion_append_character (maybe 0 (fromIntegral . ord) ch)

foreign import ccall "&" rl_completion_append_character :: Ptr CInt

setInhibitCompletion :: Bool -> IO ()
setInhibitCompletion inh = poke rl_inhibit_completion (if inh then 1 else 0)

getInhibitCompletion :: IO Bool
getInhibitCompletion = liftM (/= 0) (peek rl_inhibit_completion)

foreign import ccall "&" rl_attempted_completion_over :: Ptr CInt

getAttemptedCompletionOver :: IO Bool
getAttemptedCompletionOver = 
    liftM (/=0) (peek rl_attempted_completion_over)

setAttemptedCompletionOver :: Bool -> IO ()
setAttemptedCompletionOver over = 
    poke rl_attempted_completion_over (if over then 1 else 0)

foreign import ccall "&" rl_inhibit_completion :: Ptr CInt

setCharacters_freeIf :: (Ptr CChar -> Bool) -> Ptr (Ptr CChar) -> String -> IO ()
setCharacters_freeIf predicate variable chars = do
    oldPtr <- peek variable
    when (predicate oldPtr) $ free oldPtr
    newPtr <- mallocArray (length chars + 1)
    pokeArray0 0 newPtr (map castCharToCChar chars)
    poke variable newPtr

setCharacters :: Ptr (Ptr CChar) -> String -> IO ()
setCharacters = setCharacters_freeIf (/= nullPtr)

getCharacters :: Ptr (Ptr CChar) -> IO String
getCharacters variable = do
    ptr <- peek variable
    if ptr == nullPtr then return "" else do
        cs <- peekArray0 0 ptr
        return (map castCCharToChar cs)
