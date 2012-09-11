-----------------------------------------------------------------------------
-- |
-- Module      :  System.Console.Editline
-- Copyright   :  (c) 2008, Judah Jacobson
-- License     :  BSD3
-- 
-- Maintainer  :  judah.jacobson@gmail.com
-- Stability   :  experimental
-- Portability :  non-portable (requires libedit)
-- 
-- A Haskell binding to the editline library.  For more information about that
-- library, see <http://www.thrysoee.dk/editline/>.
-- 
-- The following example illustrates using this library to write a loop that will
-- process input until it reaches EOF or a Ctrl-D is typed.
-- 
-- @
--editlineLoop :: IO ()
-- editlineLoop = do
--    prog <- System.Environment.getProgName
--    el <- elInit prog
--    setPrompt el (return \"input: \")
--    setEditor el Vi
--    let loop = do
--         maybeLine <- elGets el
--         case maybeLine of
--             Nothing -> return () -- ctrl-D
--             Just line -> do
--                 let line\' = init line -- remove trailing \'\\n\'
--                 putStrLn $ \"User input: \" ++ show line\'
--                 loop
--    loop
-- @
-- 
module System.Console.Editline(
                            EditLine(),
                            elInit,
                            reset,
                            elGets,
                            setPrompt,
                            Editor(..),
                            setEditor
                            ) where
    
import Foreign.C
import Foreign.ForeignPtr
import Foreign.Ptr
import Foreign.Marshal
import Foreign.Storable (peek)
import Control.Monad

#include "HsEditline.h"

data EDITLINE
newtype EditLine = EditLine (ForeignPtr EDITLINE)

withEditLine :: EditLine -> (Ptr EDITLINE -> IO a) -> IO a
withEditLine (EditLine fp) = withForeignPtr fp

-- | Initialize the line editor.  
elInit :: String -- ^ The name of the calling program; used when reading the
                 -- @editrc@ file to determine which settings to use.
            -> IO EditLine
elInit prog = do
    el <- withCString prog el_init_from_term
    fmap EditLine $ newForeignPtr el_end el

foreign import ccall el_init_from_term :: CString -> IO (Ptr EDITLINE)

foreign import ccall "&" el_end :: FunPtr (Ptr EDITLINE -> IO ())


-- | Reset the terminal and the parser.  This should be called after an error which
-- may have upset the terminal's state.
reset :: EditLine -> IO ()
reset el = withEditLine el el_reset

foreign import ccall el_reset :: Ptr EDITLINE -> IO ()

-- | Read a line of input from the terminal.  Returns Nothing if no characters
-- were read or if an error occured.
elGets :: EditLine -> IO (Maybe String)
elGets el = withEditLine el $ \el_p -> alloca $ \count_p -> do
    result <- el_gets el_p count_p
    count <- fmap fromEnum $ peek count_p
    if result == nullPtr
        then return Nothing
        else fmap Just $ peekCStringLen (result, count)
    

foreign import ccall el_gets :: Ptr EDITLINE -> Ptr CInt -> IO CString


foreign import ccall el_set_prompt :: Ptr EDITLINE -> FunPtr PromptFunc -> IO CInt

-- | Set a function that will determine the prompt string.
setPrompt :: EditLine -> IO String -> IO ()
setPrompt el f = withEditLine el $ \el_p -> do
    -- Set new function
    f_ptr <- mkPromptFunc $ \_ -> f >>= newCString
    el_set_prompt el_p f_ptr
    return ()
   
type PromptFunc = Ptr EDITLINE -> IO CString
foreign import ccall "wrapper" mkPromptFunc :: PromptFunc -> IO (FunPtr PromptFunc)


 
data Editor = Vi | Emacs
editorString :: Editor -> String
editorString Vi = "vi"
editorString Emacs = "emacs"

-- | Set the editor keymap mode.
setEditor :: EditLine -> Editor -> IO ()
setEditor el editor = withEditLine el $ \el_p -> 
                        withCString (editorString editor) $ \ed_str -> 
                            el_set_editor el_p ed_str >> return ()

foreign import ccall el_set_editor :: Ptr EDITLINE -> CString -> IO CInt



