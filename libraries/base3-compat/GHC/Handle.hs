{-# LANGUAGE ForeignFunctionInterface #-}
module GHC.Handle (
  withHandle, withHandle', withHandle_,
  wantWritableHandle, wantReadableHandle, wantSeekableHandle,

  --newEmptyBuffer, allocateBuffer, readCharFromBuffer, writeCharIntoBuffer,
  --flushWriteBufferOnly, 
  flushWriteBuffer, --flushReadBuffer,
  --fillReadBuffer, fillReadBufferWithoutBlocking,
  --readRawBuffer, readRawBufferPtr,
  --readRawBufferNoBlock, readRawBufferPtrNoBlock,
  --writeRawBuffer, writeRawBufferPtr,

#ifndef mingw32_HOST_OS
  unlockFile,
#endif

  ioe_closedHandle, ioe_EOF, ioe_notReadable, ioe_notWritable,

  stdin, stdout, stderr,
  IOMode(..), openFile, openBinaryFile,
  --fdToHandle_stat, 
  fdToHandle, fdToHandle',
  hFileSize, hSetFileSize, hIsEOF, isEOF, hLookAhead, hSetBuffering, hSetBinaryMode,
  -- hLookAhead', 
  hFlush, hDuplicate, hDuplicateTo,

  hClose, hClose_help,

  HandlePosition, HandlePosn(..), hGetPosn, hSetPosn,
  SeekMode(..), hSeek, hTell,

  hIsOpen, hIsClosed, hIsReadable, hIsWritable, hGetBuffering, hIsSeekable,
  hSetEcho, hGetEcho, hIsTerminalDevice,

  hShow,

 ) where

import "base" GHC.IO.IOMode
import "base" GHC.IO.Handle
import "base" GHC.IO.Handle.Internals
import "base" GHC.IO.Handle.FD
#ifndef mingw32_HOST_OS
import "base" Foreign.C
#endif

#ifndef mingw32_HOST_OS
foreign import ccall unsafe "unlockFile"
  unlockFile :: CInt -> IO CInt
#endif

