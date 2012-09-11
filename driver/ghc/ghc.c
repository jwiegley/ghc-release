/*
 *
 * ghc wrapper for Win32 only
 * 
 * This wrapper simply invokes ghc.exe
 *
 * (c) The GHC Team 2001
 *
 * ghc.exe is searched for using the 'normal' search rules
 * for DLLs / EXEs (i.e., first in the same dir as this wrapper,
 * then system dirs, then PATH).
 *
 * To compile:
 *
 *   MSVC:    cl /o ghc.exe /c ghc.c
 *   mingw:   gcc -o ghc.exe ghc.c
 *
 * If you want to associate your own icon with the wrapper,
 * here's how to do it:
 *
 *   * Create a one-line .rc file, ghc.rc (say), containing
 *          0 ICON "hsicon.ico"
 *     (subst the string literal for the name of your icon file).
 *   * Compile it up (assuming the .ico file is in the same dir
 *     as the .rc file):
 *
 *         MSVC:    rc /i. /fo ghc.res ghc.rc 
 *         mingw:   windres -o ghc.res -i ghc.rc -O coff
 *
 *   * Add the resulting .res file to the link line of the wrapper:
 *
 *     MSVC:    cl /o ghc.exe /c ghc.c ghc.res
 *     mingw:   gcc -o ghc.exe ghc.c ghc.res
 *
 */

#include <windows.h>
#include <stdio.h>
#include <process.h>
#include <malloc.h>
#include <stdlib.h>
#include <signal.h>
#include <io.h>

#define BINARY_NAME "ghc.exe"

#define errmsg(msg) fprintf(stderr, msg "\n"); fflush(stderr)
#define errmsg1(msg,val) fprintf(stderr, msg "\n",val); fflush(stderr)

int
main(int argc, char** argv)
{
  TCHAR  binPath[FILENAME_MAX+1];
  TCHAR  binPathShort[MAX_PATH+1];
  DWORD  dwSize = FILENAME_MAX;
  TCHAR* szEnd;
  int    i;
  char*  new_cmdline;
  char   *ptr, *src;
  unsigned int cmdline_len = 0;
  char **pp;
  LPTSTR pp1;

  STARTUPINFO si;
  PROCESS_INFORMATION pi;
  
  ZeroMemory(&pi, sizeof(PROCESS_INFORMATION));
  ZeroMemory(&si, sizeof(STARTUPINFO));
  si.cb = sizeof(STARTUPINFO);

  /* Locate the binary we want to start up */
  if ( !SearchPath(NULL,
		   BINARY_NAME,
		   NULL,
		   dwSize,
		   (char*)binPath,
		   &szEnd) ) {
    errmsg1("%s: Unable to locate ghc.exe", argv[0]);
    return 1;
  }
  
  dwSize = MAX_PATH;
  /* Turn the path into short form - LFN form causes problems
     when passed in argv[0]. */
  if ( !(GetShortPathName(binPath, binPathShort, dwSize)) ) {
    errmsg1("%s: Unable to locate ghc.exe", argv[0]);
    return 1;
  }
  
  /* Compute length of the flattened 'argv' */
  for(i=1;i<argc;i++) {
      /* Note: play it safe and quote all argv strings */
      cmdline_len += 1 + strlen(argv[i]) + 2;
  }
  new_cmdline = (char*)malloc(sizeof(char) * (cmdline_len + 1));
  if (!new_cmdline) {
      errmsg1("%s: failed to start up ghc.exe; insufficient memory", argv[0]);
      return 1;
  }
  
  ptr = new_cmdline;
  for(i=1;i<argc;i++) {
      *ptr++ = ' ';
      *ptr++ = '"';
      src = argv[i];
      while(*src) {
	  *ptr++ = *src++;
      }
      *ptr++ = '"';
  }
  *ptr = '\0';
  
  /* Note: Used to use _spawnv(_P_WAIT, ...) here, but it suffered
     from the parent intercepting console events such as Ctrl-C,
     which it shouldn't. Installing an ignore-all console handler
     didn't do the trick either.
     
     Irrespective of this issue, using CreateProcess() is preferable,
     as it makes this wrapper work on both mingw and cygwin.
  */
#if 0
  fprintf(stderr, "Invoking ghc: %s %s\n", binPathShort, new_cmdline); fflush(stderr);
#endif
  if (!CreateProcess(binPathShort,
		     new_cmdline,
		     NULL,
		     NULL,
		     TRUE,
		     0, /* dwCreationFlags */
		     NULL, /* lpEnvironment */
		     NULL, /* lpCurrentDirectory */
		     &si,  /* lpStartupInfo */
		     &pi) ) {
      errmsg1("Unable to start ghc.exe (error code: %lu)", GetLastError());
      return 1;
  }
  /* Disable handling of console events in the parent by dropping its
   * connection to the console. This has the (minor) downside of not being
   * able to subsequently emit any error messages to the console.
   */
  FreeConsole();

  switch (WaitForSingleObject(pi.hProcess, INFINITE) ) {
  case WAIT_OBJECT_0:
      return 0;
  case WAIT_ABANDONED:
  case WAIT_FAILED:
      /* in the event we get any hard errors, bring the child to a halt. */
      TerminateProcess(pi.hProcess,1);
      return 1;
  default:
      return 1;
  }
}
