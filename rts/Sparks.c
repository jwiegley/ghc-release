/* ---------------------------------------------------------------------------
 *
 * (c) The GHC Team, 2000-2008
 *
 * Sparking support for PARALLEL_HASKELL and THREADED_RTS versions of the RTS.
 *
 -------------------------------------------------------------------------*/

#include "PosixSource.h"
#include "Rts.h"

#include "Schedule.h"
#include "RtsUtils.h"
#include "Trace.h"
#include "Prelude.h"
#include "Sparks.h"

#if defined(THREADED_RTS)

void
initSparkPools( void )
{
    /* walk over the capabilities, allocating a spark pool for each one */
    nat i;
    for (i = 0; i < n_capabilities; i++) {
      capabilities[i].sparks = newWSDeque(RtsFlags.ParFlags.maxLocalSparks);
    }
}

void
freeSparkPool (SparkPool *pool)
{
    freeWSDeque(pool);
}

/* -----------------------------------------------------------------------------
 * 
 * Turn a spark into a real thread
 *
 * -------------------------------------------------------------------------- */

void
createSparkThread (Capability *cap)
{
    StgTSO *tso;

    tso = createIOThread (cap, RtsFlags.GcFlags.initialStkSize, 
                          &base_GHCziConc_runSparks_closure);

    traceSchedEvent(cap, EVENT_CREATE_SPARK_THREAD, 0, tso->id);

    appendToRunQueue(cap,tso);
}

/* --------------------------------------------------------------------------
 * newSpark: create a new spark, as a result of calling "par"
 * Called directly from STG.
 * -------------------------------------------------------------------------- */

StgInt
newSpark (StgRegTable *reg, StgClosure *p)
{
    Capability *cap = regTableToCapability(reg);
    SparkPool *pool = cap->sparks;

    /* I am not sure whether this is the right thing to do.
     * Maybe it is better to exploit the tag information
     * instead of throwing it away?
     */
    p = UNTAG_CLOSURE(p);

    if (closure_SHOULD_SPARK(p)) {
        pushWSDeque(pool,p);
    }	

    cap->sparks_created++;

    return 1;
}

/* -----------------------------------------------------------------------------
 * 
 * tryStealSpark: try to steal a spark from a Capability.
 *
 * Returns a valid spark, or NULL if the pool was empty, and can
 * occasionally return NULL if there was a race with another thread
 * stealing from the same pool.  In this case, try again later.
 *
 -------------------------------------------------------------------------- */

StgClosure *
tryStealSpark (Capability *cap)
{
  SparkPool *pool = cap->sparks;
  StgClosure *stolen;

  do { 
      stolen = stealWSDeque_(pool); 
      // use the no-loopy version, stealWSDeque_(), since if we get a
      // spurious NULL here the caller may want to try stealing from
      // other pools before trying again.
  } while (stolen != NULL && !closure_SHOULD_SPARK(stolen));

  return stolen;
}

/* --------------------------------------------------------------------------
 * Remove all sparks from the spark queues which should not spark any
 * more.  Called after GC. We assume exclusive access to the structure
 * and replace  all sparks in the queue, see explanation below. At exit,
 * the spark pool only contains sparkable closures.
 * -------------------------------------------------------------------------- */

void
pruneSparkQueue (evac_fn evac, void *user, Capability *cap)
{ 
    SparkPool *pool;
    StgClosurePtr spark, tmp, *elements;
    nat n, pruned_sparks; // stats only
    StgWord botInd,oldBotInd,currInd; // indices in array (always < size)
    const StgInfoTable *info;
    
    n = 0;
    pruned_sparks = 0;
    
    pool = cap->sparks;
    
    // it is possible that top > bottom, indicating an empty pool.  We
    // fix that here; this is only necessary because the loop below
    // assumes it.
    if (pool->top > pool->bottom)
        pool->top = pool->bottom;

    // Take this opportunity to reset top/bottom modulo the size of
    // the array, to avoid overflow.  This is only possible because no
    // stealing is happening during GC.
    pool->bottom  -= pool->top & ~pool->moduloSize;
    pool->top     &= pool->moduloSize;
    pool->topBound = pool->top;

    debugTrace(DEBUG_sparks,
               "markSparkQueue: current spark queue len=%ld; (hd=%ld; tl=%ld)",
               sparkPoolSize(pool), pool->bottom, pool->top);

    ASSERT_WSDEQUE_INVARIANTS(pool);

    elements = (StgClosurePtr *)pool->elements;

    /* We have exclusive access to the structure here, so we can reset
       bottom and top counters, and prune invalid sparks. Contents are
       copied in-place if they are valuable, otherwise discarded. The
       routine uses "real" indices t and b, starts by computing them
       as the modulus size of top and bottom,

       Copying:

       At the beginning, the pool structure can look like this:
       ( bottom % size >= top % size , no wrap-around)
                  t          b
       ___________***********_________________

       or like this ( bottom % size < top % size, wrap-around )
                  b         t
       ***********__________******************
       As we need to remove useless sparks anyway, we make one pass
       between t and b, moving valuable content to b and subsequent
       cells (wrapping around when the size is reached).

                     b      t
       ***********OOO_______XX_X__X?**********
                     ^____move?____/

       After this movement, botInd becomes the new bottom, and old
       bottom becomes the new top index, both as indices in the array
       size range.
    */
    // starting here
    currInd = (pool->top) & (pool->moduloSize); // mod

    // copies of evacuated closures go to space from botInd on
    // we keep oldBotInd to know when to stop
    oldBotInd = botInd = (pool->bottom) & (pool->moduloSize); // mod

    // on entry to loop, we are within the bounds
    ASSERT( currInd < pool->size && botInd  < pool->size );

    while (currInd != oldBotInd ) {
      /* must use != here, wrap-around at size
	 subtle: loop not entered if queue empty
       */

      /* check element at currInd. if valuable, evacuate and move to
	 botInd, otherwise move on */
      spark = elements[currInd];

      // We have to be careful here: in the parallel GC, another
      // thread might evacuate this closure while we're looking at it,
      // so grab the info pointer just once.
      info = spark->header.info;
      if (IS_FORWARDING_PTR(info)) {
          tmp = (StgClosure*)UN_FORWARDING_PTR(info);
          /* if valuable work: shift inside the pool */
          if (closure_SHOULD_SPARK(tmp)) {
              elements[botInd] = tmp; // keep entry (new address)
              botInd++;
              n++;
          } else {
              pruned_sparks++; // discard spark
              cap->sparks_pruned++;
          }
      } else {
          if (!(closure_flags[INFO_PTR_TO_STRUCT(info)->type] & _NS)) {
              elements[botInd] = spark; // keep entry (new address)
              evac (user, &elements[botInd]);
              botInd++;
              n++;
          } else {
              pruned_sparks++; // discard spark
              cap->sparks_pruned++;
          }
      }
      currInd++;

      // in the loop, we may reach the bounds, and instantly wrap around
      ASSERT( currInd <= pool->size && botInd <= pool->size );
      if ( currInd == pool->size ) { currInd = 0; }
      if ( botInd == pool->size )  { botInd = 0;  }

    } // while-loop over spark pool elements

    ASSERT(currInd == oldBotInd);

    pool->top = oldBotInd; // where we started writing
    pool->topBound = pool->top;

    pool->bottom = (oldBotInd <= botInd) ? botInd : (botInd + pool->size); 
    // first free place we did not use (corrected by wraparound)

    debugTrace(DEBUG_sparks, "pruned %d sparks", pruned_sparks);
    
    debugTrace(DEBUG_sparks,
               "new spark queue len=%ld; (hd=%ld; tl=%ld)",
               sparkPoolSize(pool), pool->bottom, pool->top);

    ASSERT_WSDEQUE_INVARIANTS(pool);
}

/* GC for the spark pool, called inside Capability.c for all
   capabilities in turn. Blindly "evac"s complete spark pool. */
void
traverseSparkQueue (evac_fn evac, void *user, Capability *cap)
{
    StgClosure **sparkp;
    SparkPool *pool;
    StgWord top,bottom, modMask;
    
    pool = cap->sparks;

    ASSERT_WSDEQUE_INVARIANTS(pool);

    top = pool->top;
    bottom = pool->bottom;
    sparkp = (StgClosurePtr*)pool->elements;
    modMask = pool->moduloSize;

    while (top < bottom) {
    /* call evac for all closures in range (wrap-around via modulo)
     * In GHC-6.10, evac takes an additional 1st argument to hold a
     * GC-specific register, see rts/sm/GC.c::mark_root()
     */
      evac( user , sparkp + (top & modMask) ); 
      top++;
    }

    debugTrace(DEBUG_sparks,
               "traversed spark queue, len=%ld; (hd=%ld; tl=%ld)",
               sparkPoolSize(pool), pool->bottom, pool->top);
}

/* ----------------------------------------------------------------------------
 * balanceSparkPoolsCaps: takes an array of capabilities (usually: all
 * capabilities) and its size. Accesses all spark pools and equally
 * distributes the sparks among them.
 *
 * Could be called after GC, before Cap. release, from scheduler. 
 * -------------------------------------------------------------------------- */
void balanceSparkPoolsCaps(nat n_caps, Capability caps[])
   GNUC3_ATTRIBUTE(__noreturn__);

void balanceSparkPoolsCaps(nat n_caps STG_UNUSED, 
                           Capability caps[] STG_UNUSED) {
  barf("not implemented");
}

#else

StgInt
newSpark (StgRegTable *reg STG_UNUSED, StgClosure *p STG_UNUSED)
{
    /* nothing */
    return 1;
}

#endif /* THREADED_RTS */
