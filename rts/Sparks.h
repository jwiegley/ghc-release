/* -----------------------------------------------------------------------------
 *
 * (c) The GHC Team, 2000-2006
 *
 * Sparking support for GRAN, PAR and THREADED_RTS versions of the RTS.
 * 
 * ---------------------------------------------------------------------------*/

#ifndef SPARKS_H
#define SPARKS_H

#if defined(THREADED_RTS)
StgClosure * findSpark         (Capability *cap);
void         initSparkPools    (void);
void         freeSparkPool     (StgSparkPool *pool);
void         createSparkThread (Capability *cap, StgClosure *p);
void         pruneSparkQueues  (void);
void         traverseSparkQueue(evac_fn evac, void *user, Capability *cap);

EXTERN_INLINE void     discardSparks  (StgSparkPool *pool);
EXTERN_INLINE nat      sparkPoolSize  (StgSparkPool *pool);
EXTERN_INLINE rtsBool  emptySparkPool (StgSparkPool *pool);

EXTERN_INLINE void     discardSparksCap  (Capability *cap);
EXTERN_INLINE nat      sparkPoolSizeCap  (Capability *cap);
EXTERN_INLINE rtsBool  emptySparkPoolCap (Capability *cap);
#endif

/* -----------------------------------------------------------------------------
 * PRIVATE below here
 * -------------------------------------------------------------------------- */

#if defined(PARALLEL_HASKELL) || defined(THREADED_RTS)

EXTERN_INLINE rtsBool
emptySparkPool (StgSparkPool *pool)
{
    return (pool->hd == pool->tl);
}

EXTERN_INLINE rtsBool
emptySparkPoolCap (Capability *cap) 
{ return emptySparkPool(&cap->r.rSparks); }

EXTERN_INLINE nat
sparkPoolSize (StgSparkPool *pool) 
{
    if (pool->hd <= pool->tl) {
	return (pool->tl - pool->hd);
    } else {
	return (pool->lim - pool->hd + pool->tl - pool->base);
    }
}

EXTERN_INLINE nat
sparkPoolSizeCap (Capability *cap) 
{ return sparkPoolSize(&cap->r.rSparks); }

EXTERN_INLINE void
discardSparks (StgSparkPool *pool)
{
    pool->hd = pool->tl;
}

EXTERN_INLINE void
discardSparksCap (Capability *cap) 
{ return discardSparks(&cap->r.rSparks); }


#elif defined(THREADED_RTS) 

EXTERN_INLINE rtsBool
emptySparkPoolCap (Capability *cap STG_UNUSED)
{ return rtsTrue; }

#endif

#endif /* SPARKS_H */
