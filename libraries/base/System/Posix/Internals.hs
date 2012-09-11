{-# OPTIONS_GHC -XNoImplicitPrelude #-}
{-# OPTIONS_GHC -fno-warn-unused-binds #-}
{-# OPTIONS_HADDOCK hide #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  System.Posix.Internals
-- Copyright   :  (c) The University of Glasgow, 1992-2002
-- License     :  see libraries/base/LICENSE
-- 
-- Maintainer  :  cvs-ghc@haskell.org
-- Stability   :  internal
-- Portability :  non-portable (requires POSIX)
--
-- POSIX support layer for the standard libraries.
-- This library is built on *every* platform, including Win32.
--
-- Non-posix compliant in order to support the following features:
--      * S_ISSOCK (no sockets in POSIX)
--
-----------------------------------------------------------------------------

-- #hide
module System.Posix.Internals where

#include "HsBaseConfig.h"

#if ! (defined(mingw32_HOST_OS) || defined(__MINGW32__))
import Control.Monad
#endif
import System.Posix.Types

import Foreign
import Foreign.C

import Data.Bits
import Data.Maybe

#if __GLASGOW_HASKELL__
import GHC.Base
import GHC.Num
import GHC.Real
import GHC.IOBase
#elif __HUGS__
import Hugs.Prelude (IOException(..), IOErrorType(..))
import Hugs.IO (IOMode(..))
#else
import System.IO
#endif

#ifdef __HUGS__
{-# CFILES cbits/PrelIOUtils.c cbits/dirUtils.c cbits/consUtils.c #-}
#endif

-- ---------------------------------------------------------------------------
-- Types

type CDir       = ()
type CDirent    = ()
type CFLock     = ()
type CGroup     = ()
type CLconv     = ()
type CPasswd    = ()
type CSigaction = ()
type CSigset    = ()
type CStat      = ()
type CTermios   = ()
type CTm        = ()
type CTms       = ()
type CUtimbuf   = ()
type CUtsname   = ()

#ifndef __GLASGOW_HASKELL__
type FD = CInt
#endif

-- ---------------------------------------------------------------------------
-- stat()-related stuff

fdFileSize :: FD -> IO Integer
fdFileSize fd = 
  allocaBytes sizeof_stat $ \ p_stat -> do
    throwErrnoIfMinus1Retry "fileSize" $
        c_fstat fd p_stat
    c_mode <- st_mode p_stat :: IO CMode 
    if not (s_isreg c_mode)
        then return (-1)
        else do
    c_size <- st_size p_stat
    return (fromIntegral c_size)

data FDType  = Directory | Stream | RegularFile | RawDevice
               deriving (Eq)

fileType :: FilePath -> IO FDType
fileType file =
  allocaBytes sizeof_stat $ \ p_stat -> do
  withCString file $ \p_file -> do
    throwErrnoIfMinus1Retry "fileType" $
      c_stat p_file p_stat
    statGetType p_stat

-- NOTE: On Win32 platforms, this will only work with file descriptors
-- referring to file handles. i.e., it'll fail for socket FDs.
fdStat :: FD -> IO (FDType, CDev, CIno)
fdStat fd = 
  allocaBytes sizeof_stat $ \ p_stat -> do
    throwErrnoIfMinus1Retry "fdType" $
        c_fstat fd p_stat
    ty <- statGetType p_stat
    dev <- st_dev p_stat
    ino <- st_ino p_stat
    return (ty,dev,ino)
    
fdType :: FD -> IO FDType
fdType fd = do (ty,_,_) <- fdStat fd; return ty

statGetType :: Ptr CStat -> IO FDType
statGetType p_stat = do
  c_mode <- st_mode p_stat :: IO CMode
  case () of
      _ | s_isdir c_mode        -> return Directory
        | s_isfifo c_mode || s_issock c_mode || s_ischr  c_mode
                                -> return Stream
        | s_isreg c_mode        -> return RegularFile
         -- Q: map char devices to RawDevice too?
        | s_isblk c_mode        -> return RawDevice
        | otherwise             -> ioError ioe_unknownfiletype
    
ioe_unknownfiletype :: IOException
ioe_unknownfiletype = IOError Nothing UnsupportedOperation "fdType"
                        "unknown file type" Nothing

#if __GLASGOW_HASKELL__ && (defined(mingw32_HOST_OS) || defined(__MINGW32__))
closeFd :: Bool -> CInt -> IO CInt
closeFd isStream fd 
  | isStream  = c_closesocket fd
  | otherwise = c_close fd

foreign import stdcall unsafe "HsBase.h closesocket"
   c_closesocket :: CInt -> IO CInt
#endif

fdGetMode :: FD -> IO IOMode
#if defined(mingw32_HOST_OS) || defined(__MINGW32__)
fdGetMode _ = do
    -- We don't have a way of finding out which flags are set on FDs
    -- on Windows, so make a handle that thinks that anything goes.
    let flags = o_RDWR
#else
fdGetMode fd = do
    flags <- throwErrnoIfMinus1Retry "fdGetMode" 
                (c_fcntl_read fd const_f_getfl)
#endif
    let
       wH  = (flags .&. o_WRONLY) /= 0
       aH  = (flags .&. o_APPEND) /= 0
       rwH = (flags .&. o_RDWR) /= 0

       mode
         | wH && aH  = AppendMode
         | wH        = WriteMode
         | rwH       = ReadWriteMode
         | otherwise = ReadMode
          
    return mode

-- ---------------------------------------------------------------------------
-- Terminal-related stuff

fdIsTTY :: FD -> IO Bool
fdIsTTY fd = c_isatty fd >>= return.toBool

#if defined(HTYPE_TCFLAG_T)

setEcho :: FD -> Bool -> IO ()
setEcho fd on = do
  tcSetAttr fd $ \ p_tios -> do
    lflag <- c_lflag p_tios :: IO CTcflag
    let new_lflag
         | on        = lflag .|. fromIntegral const_echo
         | otherwise = lflag .&. complement (fromIntegral const_echo)
    poke_c_lflag p_tios (new_lflag :: CTcflag)

getEcho :: FD -> IO Bool
getEcho fd = do
  tcSetAttr fd $ \ p_tios -> do
    lflag <- c_lflag p_tios :: IO CTcflag
    return ((lflag .&. fromIntegral const_echo) /= 0)

setCooked :: FD -> Bool -> IO ()
setCooked fd cooked = 
  tcSetAttr fd $ \ p_tios -> do

    -- turn on/off ICANON
    lflag <- c_lflag p_tios :: IO CTcflag
    let new_lflag | cooked    = lflag .|. (fromIntegral const_icanon)
                  | otherwise = lflag .&. complement (fromIntegral const_icanon)
    poke_c_lflag p_tios (new_lflag :: CTcflag)

    -- set VMIN & VTIME to 1/0 respectively
    when (not cooked) $ do
            c_cc <- ptr_c_cc p_tios
            let vmin  = (c_cc `plusPtr` (fromIntegral const_vmin))  :: Ptr Word8
                vtime = (c_cc `plusPtr` (fromIntegral const_vtime)) :: Ptr Word8
            poke vmin  1
            poke vtime 0

tcSetAttr :: FD -> (Ptr CTermios -> IO a) -> IO a
tcSetAttr fd fun = do
     allocaBytes sizeof_termios  $ \p_tios -> do
        throwErrnoIfMinus1Retry "tcSetAttr"
           (c_tcgetattr fd p_tios)

#ifdef __GLASGOW_HASKELL__
        -- Save a copy of termios, if this is a standard file descriptor.
        -- These terminal settings are restored in hs_exit().
        when (fd <= 2) $ do
          p <- get_saved_termios fd
          when (p == nullPtr) $ do
             saved_tios <- mallocBytes sizeof_termios
             copyBytes saved_tios p_tios sizeof_termios
             set_saved_termios fd saved_tios
#endif

        -- tcsetattr() when invoked by a background process causes the process
        -- to be sent SIGTTOU regardless of whether the process has TOSTOP set
        -- in its terminal flags (try it...).  This function provides a
        -- wrapper which temporarily blocks SIGTTOU around the call, making it
        -- transparent.
        allocaBytes sizeof_sigset_t $ \ p_sigset -> do
        allocaBytes sizeof_sigset_t $ \ p_old_sigset -> do
             c_sigemptyset p_sigset
             c_sigaddset   p_sigset const_sigttou
             c_sigprocmask const_sig_block p_sigset p_old_sigset
             r <- fun p_tios  -- do the business
             throwErrnoIfMinus1Retry_ "tcSetAttr" $
                 c_tcsetattr fd const_tcsanow p_tios
             c_sigprocmask const_sig_setmask p_old_sigset nullPtr
             return r

#ifdef __GLASGOW_HASKELL__
foreign import ccall unsafe "HsBase.h __hscore_get_saved_termios"
   get_saved_termios :: CInt -> IO (Ptr CTermios)

foreign import ccall unsafe "HsBase.h __hscore_set_saved_termios"
   set_saved_termios :: CInt -> (Ptr CTermios) -> IO ()
#endif

#else

-- 'raw' mode for Win32 means turn off 'line input' (=> buffering and
-- character translation for the console.) The Win32 API for doing
-- this is GetConsoleMode(), which also requires echoing to be disabled
-- when turning off 'line input' processing. Notice that turning off
-- 'line input' implies enter/return is reported as '\r' (and it won't
-- report that character until another character is input..odd.) This
-- latter feature doesn't sit too well with IO actions like IO.hGetLine..
-- consider yourself warned.
setCooked :: FD -> Bool -> IO ()
setCooked fd cooked = do
  x <- set_console_buffering fd (if cooked then 1 else 0)
  if (x /= 0)
   then ioError (ioe_unk_error "setCooked" "failed to set buffering")
   else return ()

ioe_unk_error :: String -> String -> IOException
ioe_unk_error loc msg 
 = IOError Nothing OtherError loc msg Nothing

-- Note: echoing goes hand in hand with enabling 'line input' / raw-ness
-- for Win32 consoles, hence setEcho ends up being the inverse of setCooked.
setEcho :: FD -> Bool -> IO ()
setEcho fd on = do
  x <- set_console_echo fd (if on then 1 else 0)
  if (x /= 0)
   then ioError (ioe_unk_error "setEcho" "failed to set echoing")
   else return ()

getEcho :: FD -> IO Bool
getEcho fd = do
  r <- get_console_echo fd
  if (r == (-1))
   then ioError (ioe_unk_error "getEcho" "failed to get echoing")
   else return (r == 1)

foreign import ccall unsafe "consUtils.h set_console_buffering__"
   set_console_buffering :: CInt -> CInt -> IO CInt

foreign import ccall unsafe "consUtils.h set_console_echo__"
   set_console_echo :: CInt -> CInt -> IO CInt

foreign import ccall unsafe "consUtils.h get_console_echo__"
   get_console_echo :: CInt -> IO CInt

#endif

-- ---------------------------------------------------------------------------
-- Turning on non-blocking for a file descriptor

setNonBlockingFD :: FD -> IO ()
#if !defined(mingw32_HOST_OS) && !defined(__MINGW32__)
setNonBlockingFD fd = do
  flags <- throwErrnoIfMinus1Retry "setNonBlockingFD"
                 (c_fcntl_read fd const_f_getfl)
  -- An error when setting O_NONBLOCK isn't fatal: on some systems 
  -- there are certain file handles on which this will fail (eg. /dev/null
  -- on FreeBSD) so we throw away the return code from fcntl_write.
  unless (testBit flags (fromIntegral o_NONBLOCK)) $ do
    c_fcntl_write fd const_f_setfl (fromIntegral (flags .|. o_NONBLOCK))
    return ()
#else

-- bogus defns for win32
setNonBlockingFD _ = return ()

#endif

-- -----------------------------------------------------------------------------
-- Set close-on-exec for a file descriptor

#if !defined(mingw32_HOST_OS) && !defined(__MINGW32__)
setCloseOnExec :: FD -> IO ()
setCloseOnExec fd = do
  throwErrnoIfMinus1 "setCloseOnExec" $
    c_fcntl_write fd const_f_setfd const_fd_cloexec
  return ()
#endif

-- -----------------------------------------------------------------------------
-- foreign imports

foreign import ccall unsafe "HsBase.h access"
   c_access :: CString -> CInt -> IO CInt

foreign import ccall unsafe "HsBase.h chmod"
   c_chmod :: CString -> CMode -> IO CInt

foreign import ccall unsafe "HsBase.h close"
   c_close :: CInt -> IO CInt

foreign import ccall unsafe "HsBase.h closedir" 
   c_closedir :: Ptr CDir -> IO CInt

foreign import ccall unsafe "HsBase.h creat"
   c_creat :: CString -> CMode -> IO CInt

foreign import ccall unsafe "HsBase.h dup"
   c_dup :: CInt -> IO CInt

foreign import ccall unsafe "HsBase.h dup2"
   c_dup2 :: CInt -> CInt -> IO CInt

foreign import ccall unsafe "HsBase.h __hscore_fstat"
   c_fstat :: CInt -> Ptr CStat -> IO CInt

foreign import ccall unsafe "HsBase.h isatty"
   c_isatty :: CInt -> IO CInt

#if defined(mingw32_HOST_OS) || defined(__MINGW32__)
foreign import ccall unsafe "HsBase.h __hscore_lseek"
   c_lseek :: CInt -> Int64 -> CInt -> IO Int64
#else
foreign import ccall unsafe "HsBase.h __hscore_lseek"
   c_lseek :: CInt -> COff -> CInt -> IO COff
#endif

foreign import ccall unsafe "HsBase.h __hscore_lstat"
   lstat :: CString -> Ptr CStat -> IO CInt

foreign import ccall unsafe "HsBase.h __hscore_open"
   c_open :: CString -> CInt -> CMode -> IO CInt

foreign import ccall unsafe "HsBase.h opendir" 
   c_opendir :: CString  -> IO (Ptr CDir)

foreign import ccall unsafe "HsBase.h __hscore_mkdir"
   mkdir :: CString -> CInt -> IO CInt

foreign import ccall unsafe "HsBase.h read" 
   c_read :: CInt -> Ptr CChar -> CSize -> IO CSsize

foreign import ccall unsafe "HsBase.h rewinddir"
   c_rewinddir :: Ptr CDir -> IO ()

foreign import ccall unsafe "HsBase.h __hscore_stat"
   c_stat :: CString -> Ptr CStat -> IO CInt

foreign import ccall unsafe "HsBase.h umask"
   c_umask :: CMode -> IO CMode

foreign import ccall unsafe "HsBase.h write" 
   c_write :: CInt -> Ptr CChar -> CSize -> IO CSsize

foreign import ccall unsafe "HsBase.h __hscore_ftruncate"
   c_ftruncate :: CInt -> COff -> IO CInt

foreign import ccall unsafe "HsBase.h unlink"
   c_unlink :: CString -> IO CInt

foreign import ccall unsafe "HsBase.h getpid"
   c_getpid :: IO CPid

#if !defined(mingw32_HOST_OS) && !defined(__MINGW32__)
foreign import ccall unsafe "HsBase.h fcntl"
   c_fcntl_read  :: CInt -> CInt -> IO CInt

foreign import ccall unsafe "HsBase.h fcntl"
   c_fcntl_write :: CInt -> CInt -> CLong -> IO CInt

foreign import ccall unsafe "HsBase.h fcntl"
   c_fcntl_lock  :: CInt -> CInt -> Ptr CFLock -> IO CInt

foreign import ccall unsafe "HsBase.h fork"
   c_fork :: IO CPid 

foreign import ccall unsafe "HsBase.h link"
   c_link :: CString -> CString -> IO CInt

foreign import ccall unsafe "HsBase.h mkfifo"
   c_mkfifo :: CString -> CMode -> IO CInt

foreign import ccall unsafe "HsBase.h pipe"
   c_pipe :: Ptr CInt -> IO CInt

foreign import ccall unsafe "HsBase.h __hscore_sigemptyset"
   c_sigemptyset :: Ptr CSigset -> IO CInt

foreign import ccall unsafe "HsBase.h __hscore_sigaddset"
   c_sigaddset :: Ptr CSigset -> CInt -> IO CInt

foreign import ccall unsafe "HsBase.h sigprocmask"
   c_sigprocmask :: CInt -> Ptr CSigset -> Ptr CSigset -> IO CInt

foreign import ccall unsafe "HsBase.h tcgetattr"
   c_tcgetattr :: CInt -> Ptr CTermios -> IO CInt

foreign import ccall unsafe "HsBase.h tcsetattr"
   c_tcsetattr :: CInt -> CInt -> Ptr CTermios -> IO CInt

foreign import ccall unsafe "HsBase.h utime"
   c_utime :: CString -> Ptr CUtimbuf -> IO CInt

foreign import ccall unsafe "HsBase.h waitpid"
   c_waitpid :: CPid -> Ptr CInt -> CInt -> IO CPid
#endif

-- traversing directories
foreign import ccall unsafe "dirUtils.h __hscore_readdir"
  readdir  :: Ptr CDir -> Ptr (Ptr CDirent) -> IO CInt
 
foreign import ccall unsafe "HsBase.h __hscore_free_dirent"
  freeDirEnt  :: Ptr CDirent -> IO ()
 
foreign import ccall unsafe "HsBase.h __hscore_end_of_dir"
  end_of_dir :: CInt
 
foreign import ccall unsafe "HsBase.h __hscore_d_name"
  d_name :: Ptr CDirent -> IO CString

-- POSIX flags only:
foreign import ccall unsafe "HsBase.h __hscore_o_rdonly" o_RDONLY :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_wronly" o_WRONLY :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_rdwr"   o_RDWR   :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_append" o_APPEND :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_creat"  o_CREAT  :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_excl"   o_EXCL   :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_trunc"  o_TRUNC  :: CInt

-- non-POSIX flags.
foreign import ccall unsafe "HsBase.h __hscore_o_noctty"   o_NOCTTY   :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_nonblock" o_NONBLOCK :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_binary"   o_BINARY   :: CInt

foreign import ccall unsafe "HsBase.h __hscore_s_isreg"  c_s_isreg  :: CMode -> CInt
foreign import ccall unsafe "HsBase.h __hscore_s_ischr"  c_s_ischr  :: CMode -> CInt
foreign import ccall unsafe "HsBase.h __hscore_s_isblk"  c_s_isblk  :: CMode -> CInt
foreign import ccall unsafe "HsBase.h __hscore_s_isdir"  c_s_isdir  :: CMode -> CInt
foreign import ccall unsafe "HsBase.h __hscore_s_isfifo" c_s_isfifo :: CMode -> CInt

s_isreg  :: CMode -> Bool
s_isreg cm = c_s_isreg cm /= 0
s_ischr  :: CMode -> Bool
s_ischr cm = c_s_ischr cm /= 0
s_isblk  :: CMode -> Bool
s_isblk cm = c_s_isblk cm /= 0
s_isdir  :: CMode -> Bool
s_isdir cm = c_s_isdir cm /= 0
s_isfifo :: CMode -> Bool
s_isfifo cm = c_s_isfifo cm /= 0

foreign import ccall unsafe "HsBase.h __hscore_sizeof_stat" sizeof_stat :: Int
foreign import ccall unsafe "HsBase.h __hscore_st_mtime" st_mtime :: Ptr CStat -> IO CTime
#ifdef mingw32_HOST_OS
foreign import ccall unsafe "HsBase.h __hscore_st_size" st_size :: Ptr CStat -> IO Int64
#else
foreign import ccall unsafe "HsBase.h __hscore_st_size" st_size :: Ptr CStat -> IO COff
#endif
foreign import ccall unsafe "HsBase.h __hscore_st_mode" st_mode :: Ptr CStat -> IO CMode
foreign import ccall unsafe "HsBase.h __hscore_st_dev" st_dev :: Ptr CStat -> IO CDev
foreign import ccall unsafe "HsBase.h __hscore_st_ino" st_ino :: Ptr CStat -> IO CIno

foreign import ccall unsafe "HsBase.h __hscore_echo"         const_echo :: CInt
foreign import ccall unsafe "HsBase.h __hscore_tcsanow"      const_tcsanow :: CInt
foreign import ccall unsafe "HsBase.h __hscore_icanon"       const_icanon :: CInt
foreign import ccall unsafe "HsBase.h __hscore_vmin"         const_vmin   :: CInt
foreign import ccall unsafe "HsBase.h __hscore_vtime"        const_vtime  :: CInt
foreign import ccall unsafe "HsBase.h __hscore_sigttou"      const_sigttou :: CInt
foreign import ccall unsafe "HsBase.h __hscore_sig_block"    const_sig_block :: CInt
foreign import ccall unsafe "HsBase.h __hscore_sig_setmask"  const_sig_setmask :: CInt
foreign import ccall unsafe "HsBase.h __hscore_f_getfl"      const_f_getfl :: CInt
foreign import ccall unsafe "HsBase.h __hscore_f_setfl"      const_f_setfl :: CInt
foreign import ccall unsafe "HsBase.h __hscore_f_setfd"      const_f_setfd :: CInt
foreign import ccall unsafe "HsBase.h __hscore_fd_cloexec"   const_fd_cloexec :: CLong

#if defined(HTYPE_TCFLAG_T)
foreign import ccall unsafe "HsBase.h __hscore_sizeof_termios"  sizeof_termios :: Int
foreign import ccall unsafe "HsBase.h __hscore_sizeof_sigset_t" sizeof_sigset_t :: Int

foreign import ccall unsafe "HsBase.h __hscore_lflag" c_lflag :: Ptr CTermios -> IO CTcflag
foreign import ccall unsafe "HsBase.h __hscore_poke_lflag" poke_c_lflag :: Ptr CTermios -> CTcflag -> IO ()
foreign import ccall unsafe "HsBase.h __hscore_ptr_c_cc" ptr_c_cc  :: Ptr CTermios -> IO (Ptr Word8)
#endif

s_issock :: CMode -> Bool
#if !defined(mingw32_HOST_OS) && !defined(__MINGW32__)
s_issock cmode = c_s_issock cmode /= 0
foreign import ccall unsafe "HsBase.h __hscore_s_issock" c_s_issock :: CMode -> CInt
#else
s_issock _ = False
#endif
