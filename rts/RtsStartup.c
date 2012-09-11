/* -----------------------------------------------------------------------------
 *
 * (c) The GHC Team, 1998-2002
 *
 * Main function for a standalone Haskell program.
 *
 * ---------------------------------------------------------------------------*/

// PAPI uses caddr_t, which is not POSIX
#ifndef USE_PAPI
#include "PosixSource.h"
#endif

#include "Rts.h"
#include "RtsAPI.h"
#include "HsFFI.h"

#include "sm/Storage.h"
#include "RtsUtils.h"
#include "Schedule.h"   /* initScheduler */
#include "Stats.h"      /* initStats */
#include "STM.h"        /* initSTM */
#include "RtsSignals.h"
#include "Weak.h"
#include "Ticky.h"
#include "StgRun.h"
#include "Prelude.h"		/* fixupRTStoPreludeRefs */
#include "ThreadLabels.h"
#include "sm/BlockAlloc.h"
#include "Trace.h"
#include "Stable.h"
#include "Hash.h"
#include "Profiling.h"
#include "Timer.h"
#include "Globals.h"

#if defined(RTS_GTK_FRONTPANEL)
#include "FrontPanel.h"
#endif

#if defined(PROFILING)
# include "ProfHeap.h"
# include "RetainerProfile.h"
#endif

#if defined(mingw32_HOST_OS) && !defined(THREADED_RTS)
#include "win32/AsyncIO.h"
#endif

#if !defined(mingw32_HOST_OS)
#include "posix/TTY.h"
#include "posix/FileLock.h"
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#ifdef HAVE_LOCALE_H
#include <locale.h>
#endif

#if USE_PAPI
#include "Papi.h"
#endif

// Count of how many outstanding hs_init()s there have been.
static int hs_init_count = 0;

/* -----------------------------------------------------------------------------
   Initialise floating point unit on x86 (currently disabled. why?)
   (see comment in ghc/compiler/nativeGen/MachInstrs.lhs).
   -------------------------------------------------------------------------- */

#define X86_INIT_FPU 0

#if X86_INIT_FPU
static void
x86_init_fpu ( void )
{
  __volatile unsigned short int fpu_cw;

  // Grab the control word
  __asm __volatile ("fnstcw %0" : "=m" (fpu_cw));

#if 0
  printf("fpu_cw: %x\n", fpu_cw);
#endif

  // Set bits 8-9 to 10 (64-bit precision).
  fpu_cw = (fpu_cw & 0xfcff) | 0x0200;

  // Store the new control word back
  __asm __volatile ("fldcw %0" : : "m" (fpu_cw));
}
#endif

/* -----------------------------------------------------------------------------
   Starting up the RTS
   -------------------------------------------------------------------------- */

void
hs_init(int *argc, char **argv[])
{
    hs_init_count++;
    if (hs_init_count > 1) {
	// second and subsequent inits are ignored
	return;
    }

    setlocale(LC_CTYPE,"");

    /* Initialise the stats department, phase 0 */
    initStats0();

    /* Next we do is grab the start time...just in case we're
     * collecting timing statistics.
     */
    stat_startInit();

#if defined(DEBUG)
    /* Start off by initialising the allocator debugging so we can
     * use it anywhere */
    initAllocator();
#endif

    /* Set the RTS flags to default values. */

    initRtsFlagsDefaults();

    /* Call the user hook to reset defaults, if present */
    defaultsHook();

    /* Parse the flags, separating the RTS flags from the programs args */
    if (argc != NULL && argv != NULL) {
	setFullProgArgv(*argc,*argv);
	setupRtsFlags(argc, *argv, &rts_argc, rts_argv);
	setProgArgv(*argc,*argv);
    }

    /* Initialise the stats department, phase 1 */
    initStats1();

#ifdef USE_PAPI
    papi_init();
#endif

    /* initTracing must be after setupRtsFlags() */
#ifdef TRACING
    initTracing();
#endif

    /* initialise scheduler data structures (needs to be done before
     * initStorage()).
     */
    initScheduler();

    /* initialize the storage manager */
    initStorage();

    /* initialise the stable pointer table */
    initStablePtrTable();

    /* Add some GC roots for things in the base package that the RTS
     * knows about.  We don't know whether these turn out to be CAFs
     * or refer to CAFs, but we have to assume that they might.
     */
    getStablePtr((StgPtr)base_GHCziTopHandler_runIO_closure);
    getStablePtr((StgPtr)base_GHCziTopHandler_runNonIO_closure);
    getStablePtr((StgPtr)stackOverflow_closure);
    getStablePtr((StgPtr)heapOverflow_closure);
    getStablePtr((StgPtr)runFinalizerBatch_closure);
    getStablePtr((StgPtr)unpackCString_closure);
    getStablePtr((StgPtr)blockedIndefinitelyOnMVar_closure);
    getStablePtr((StgPtr)nonTermination_closure);
    getStablePtr((StgPtr)blockedIndefinitelyOnSTM_closure);

    /* initialise the shared Typeable store */
    initGlobalStore();

    /* initialise file locking, if necessary */
#if !defined(mingw32_HOST_OS)    
    initFileLocking();
#endif

#if defined(DEBUG)
    /* initialise thread label table (tso->char*) */
    initThreadLabelTable();
#endif

    initProfiling1();

    /* start the virtual timer 'subsystem'. */
    initTimer();
    startTimer();

#if defined(RTS_USER_SIGNALS)
    if (RtsFlags.MiscFlags.install_signal_handlers) {
        /* Initialise the user signal handler set */
        initUserSignals();
        /* Set up handler to run on SIGINT, etc. */
        initDefaultHandlers();
    }
#endif
 
#if defined(mingw32_HOST_OS) && !defined(THREADED_RTS)
    startupAsyncIO();
#endif

#ifdef RTS_GTK_FRONTPANEL
    if (RtsFlags.GcFlags.frontpanel) {
	initFrontPanel();
    }
#endif

#if X86_INIT_FPU
    x86_init_fpu();
#endif

    /* Record initialization times */
    stat_endInit();
}

// Compatibility interface
void
startupHaskell(int argc, char *argv[], void (*init_root)(void))
{
    hs_init(&argc, &argv);
    if(init_root)
        hs_add_root(init_root);
}


/* -----------------------------------------------------------------------------
   Per-module initialisation

   This process traverses all the compiled modules in the program
   starting with "Main", and performing per-module initialisation for
   each one.

   So far, two things happen at initialisation time:

      - we register stable names for each foreign-exported function
        in that module.  This prevents foreign-exported entities, and
	things they depend on, from being garbage collected.

      - we supply a unique integer to each statically declared cost
        centre and cost centre stack in the program.

   The code generator inserts a small function "__stginit_<module>" in each
   module and calls the registration functions in each of the modules it
   imports.

   The init* functions are compiled in the same way as STG code,
   i.e. without normal C call/return conventions.  Hence we must use
   StgRun to call this stuff.
   -------------------------------------------------------------------------- */

/* The init functions use an explicit stack... 
 */
#define INIT_STACK_BLOCKS  4
static StgFunPtr *init_stack = NULL;

void
hs_add_root(void (*init_root)(void))
{
    bdescr *bd;
    nat init_sp;
    Capability *cap;

    cap = rts_lock();

    if (hs_init_count <= 0) {
	barf("hs_add_root() must be called after hs_init()");
    }

    /* The initialisation stack grows downward, with sp pointing 
       to the last occupied word */
    init_sp = INIT_STACK_BLOCKS*BLOCK_SIZE_W;
    bd = allocGroup_lock(INIT_STACK_BLOCKS);
    init_stack = (StgFunPtr *)bd->start;
    init_stack[--init_sp] = (StgFunPtr)stg_init_finish;
    if (init_root != NULL) {
	init_stack[--init_sp] = (StgFunPtr)init_root;
    }
    
    cap->r.rSp = (P_)(init_stack + init_sp);
    StgRun((StgFunPtr)stg_init, &cap->r);

    freeGroup_lock(bd);

    startupHpc();

    // This must be done after module initialisation.
    // ToDo: make this work in the presence of multiple hs_add_root()s.
    initProfiling2();

    rts_unlock(cap);

    // ditto.
#if defined(THREADED_RTS)
    ioManagerStart();
#endif
}

/* ----------------------------------------------------------------------------
 * Shutting down the RTS
 *
 * The wait_foreign parameter means:
 *       True  ==> wait for any threads doing foreign calls now.
 *       False ==> threads doing foreign calls may return in the
 *                 future, but will immediately block on a mutex.
 *                 (capability->lock).
 * 
 * If this RTS is a DLL that we're about to unload, then you want
 * safe=True, otherwise the thread might return to code that has been
 * unloaded.  If this is a standalone program that is about to exit,
 * then you can get away with safe=False, which is better because we
 * won't hang on exit if there is a blocked foreign call outstanding.
 *
 ------------------------------------------------------------------------- */

static void
hs_exit_(rtsBool wait_foreign)
{
    if (hs_init_count <= 0) {
	errorBelch("warning: too many hs_exit()s");
	return;
    }
    hs_init_count--;
    if (hs_init_count > 0) {
	// ignore until it's the last one
	return;
    }

    /* start timing the shutdown */
    stat_startExit();
    
    OnExitHook();

#if defined(THREADED_RTS)
    ioManagerDie();
#endif

    /* stop all running tasks */
    exitScheduler(wait_foreign);

    /* run C finalizers for all active weak pointers */
    runAllCFinalizers(weak_ptr_list);
    
#if defined(RTS_USER_SIGNALS)
    if (RtsFlags.MiscFlags.install_signal_handlers) {
        freeSignalHandlers();
    }
#endif

    /* stop the ticker */
    stopTimer();
    exitTimer();

    // set the terminal settings back to what they were
#if !defined(mingw32_HOST_OS)    
    resetTerminalSettings();
#endif

    // uninstall signal handlers
    resetDefaultHandlers();

    /* stop timing the shutdown, we're about to print stats */
    stat_endExit();
    
    /* shutdown the hpc support (if needed) */
    exitHpc();

    // clean up things from the storage manager's point of view.
    // also outputs the stats (+RTS -s) info.
    exitStorage();
    
    /* free the tasks */
    freeScheduler();

    /* free shared Typeable store */
    exitGlobalStore();

    /* free file locking tables, if necessary */
#if !defined(mingw32_HOST_OS)    
    freeFileLocking();
#endif

    /* free the stable pointer table */
    exitStablePtrTable();

#if defined(DEBUG)
    /* free the thread label table */
    freeThreadLabelTable();
#endif

#ifdef RTS_GTK_FRONTPANEL
    if (RtsFlags.GcFlags.frontpanel) {
	stopFrontPanel();
    }
#endif

#if defined(PROFILING) 
    reportCCSProfiling();
#endif

    endProfiling();
    freeProfiling1();

#ifdef PROFILING
    // Originally, this was in report_ccs_profiling().  Now, retainer
    // profiling might tack some extra stuff on to the end of this file
    // during endProfiling().
    if (prof_file != NULL) fclose(prof_file);
#endif

#ifdef TRACING
    endTracing();
    freeTracing();
#endif

#if defined(TICKY_TICKY)
    if (RtsFlags.TickyFlags.showTickyStats) PrintTickyInfo();
#endif

#if defined(mingw32_HOST_OS) && !defined(THREADED_RTS)
    shutdownAsyncIO(wait_foreign);
#endif

    /* free hash table storage */
    exitHashTable();

    // Finally, free all our storage
    freeStorage();

#if defined(DEBUG)
    /* and shut down the allocator debugging */
    shutdownAllocator();
#endif

}

// The real hs_exit():
void
hs_exit(void)
{
    hs_exit_(rtsTrue);
    // be safe; this might be a DLL
}

// Compatibility interfaces
void
shutdownHaskell(void)
{
    hs_exit();
}

void
shutdownHaskellAndExit(int n)
{
    // we're about to exit(), no need to wait for foreign calls to return.
    hs_exit_(rtsFalse);

    if (hs_init_count == 0) {
	stg_exit(n);
    }
}

#ifndef mingw32_HOST_OS
void
shutdownHaskellAndSignal(int sig)
{
    hs_exit_(rtsFalse);
    kill(getpid(),sig);
}
#endif

/* 
 * called from STG-land to exit the program
 */

void (*exitFn)(int) = 0;

void  
stg_exit(int n)
{ 
  if (exitFn)
    (*exitFn)(n);
  exit(n);
}
