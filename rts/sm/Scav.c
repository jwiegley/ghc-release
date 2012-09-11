/* -----------------------------------------------------------------------------
 *
 * (c) The GHC Team 1998-2008
 *
 * Generational garbage collector: scavenging functions
 *
 * Documentation on the architecture of the Garbage Collector can be
 * found in the online commentary:
 * 
 *   http://hackage.haskell.org/trac/ghc/wiki/Commentary/Rts/Storage/GC
 *
 * ---------------------------------------------------------------------------*/

#include "Rts.h"
#include "RtsFlags.h"
#include "Storage.h"
#include "MBlock.h"
#include "GC.h"
#include "GCThread.h"
#include "GCUtils.h"
#include "Compact.h"
#include "Evac.h"
#include "Scav.h"
#include "Apply.h"
#include "Trace.h"
#include "LdvProfile.h"
#include "Sanity.h"

static void scavenge_stack (StgPtr p, StgPtr stack_end);

static void scavenge_large_bitmap (StgPtr p, 
				   StgLargeBitmap *large_bitmap, 
				   nat size );

#if defined(THREADED_RTS) && !defined(PARALLEL_GC)
# define evacuate(a) evacuate1(a)
# define recordMutableGen_GC(a,b) recordMutableGen(a,b)
# define scavenge_loop(a) scavenge_loop1(a)
# define scavenge_mutable_list(g) scavenge_mutable_list1(g)
#endif

/* -----------------------------------------------------------------------------
   Scavenge a TSO.
   -------------------------------------------------------------------------- */

STATIC_INLINE void
scavenge_TSO_link (StgTSO *tso)
{
    // We don't always chase the link field: TSOs on the blackhole
    // queue are not automatically alive, so the link field is a
    // "weak" pointer in that case.
    if (tso->why_blocked != BlockedOnBlackHole) {
        evacuate((StgClosure **)&tso->_link);
    }
}

static void
scavengeTSO (StgTSO *tso)
{
    rtsBool saved_eager;

    if (tso->what_next == ThreadRelocated) {
        // the only way this can happen is if the old TSO was on the
        // mutable list.  We might have other links to this defunct
        // TSO, so we must update its link field.
        evacuate((StgClosure**)&tso->_link);
        return;
    }

    saved_eager = gct->eager_promotion;
    gct->eager_promotion = rtsFalse;

    if (   tso->why_blocked == BlockedOnMVar
	|| tso->why_blocked == BlockedOnBlackHole
	|| tso->why_blocked == BlockedOnException
	) {
	evacuate(&tso->block_info.closure);
    }
    evacuate((StgClosure **)&tso->blocked_exceptions);
    
    // scavange current transaction record
    evacuate((StgClosure **)&tso->trec);
    
    // scavenge this thread's stack 
    scavenge_stack(tso->sp, &(tso->stack[tso->stack_size]));

    if (gct->failed_to_evac) {
        tso->flags |= TSO_DIRTY;
        scavenge_TSO_link(tso);
    } else {
        tso->flags &= ~TSO_DIRTY;
        scavenge_TSO_link(tso);
        if (gct->failed_to_evac) {
            tso->flags |= TSO_LINK_DIRTY;
        } else {
            tso->flags &= ~TSO_LINK_DIRTY;
        }
    }

    gct->eager_promotion = saved_eager;
}

/* -----------------------------------------------------------------------------
   Blocks of function args occur on the stack (at the top) and
   in PAPs.
   -------------------------------------------------------------------------- */

STATIC_INLINE StgPtr
scavenge_arg_block (StgFunInfoTable *fun_info, StgClosure **args)
{
    StgPtr p;
    StgWord bitmap;
    nat size;

    p = (StgPtr)args;
    switch (fun_info->f.fun_type) {
    case ARG_GEN:
	bitmap = BITMAP_BITS(fun_info->f.b.bitmap);
	size = BITMAP_SIZE(fun_info->f.b.bitmap);
	goto small_bitmap;
    case ARG_GEN_BIG:
	size = GET_FUN_LARGE_BITMAP(fun_info)->size;
	scavenge_large_bitmap(p, GET_FUN_LARGE_BITMAP(fun_info), size);
	p += size;
	break;
    default:
	bitmap = BITMAP_BITS(stg_arg_bitmaps[fun_info->f.fun_type]);
	size = BITMAP_SIZE(stg_arg_bitmaps[fun_info->f.fun_type]);
    small_bitmap:
	while (size > 0) {
	    if ((bitmap & 1) == 0) {
		evacuate((StgClosure **)p);
	    }
	    p++;
	    bitmap = bitmap >> 1;
	    size--;
	}
	break;
    }
    return p;
}

STATIC_INLINE GNUC_ATTR_HOT StgPtr
scavenge_PAP_payload (StgClosure *fun, StgClosure **payload, StgWord size)
{
    StgPtr p;
    StgWord bitmap;
    StgFunInfoTable *fun_info;
    
    fun_info = get_fun_itbl(UNTAG_CLOSURE(fun));
    ASSERT(fun_info->i.type != PAP);
    p = (StgPtr)payload;

    switch (fun_info->f.fun_type) {
    case ARG_GEN:
	bitmap = BITMAP_BITS(fun_info->f.b.bitmap);
	goto small_bitmap;
    case ARG_GEN_BIG:
	scavenge_large_bitmap(p, GET_FUN_LARGE_BITMAP(fun_info), size);
	p += size;
	break;
    case ARG_BCO:
	scavenge_large_bitmap((StgPtr)payload, BCO_BITMAP(fun), size);
	p += size;
	break;
    default:
	bitmap = BITMAP_BITS(stg_arg_bitmaps[fun_info->f.fun_type]);
    small_bitmap:
	while (size > 0) {
	    if ((bitmap & 1) == 0) {
		evacuate((StgClosure **)p);
	    }
	    p++;
	    bitmap = bitmap >> 1;
	    size--;
	}
	break;
    }
    return p;
}

STATIC_INLINE GNUC_ATTR_HOT StgPtr
scavenge_PAP (StgPAP *pap)
{
    evacuate(&pap->fun);
    return scavenge_PAP_payload (pap->fun, pap->payload, pap->n_args);
}

STATIC_INLINE StgPtr
scavenge_AP (StgAP *ap)
{
    evacuate(&ap->fun);
    return scavenge_PAP_payload (ap->fun, ap->payload, ap->n_args);
}

/* -----------------------------------------------------------------------------
   Scavenge SRTs
   -------------------------------------------------------------------------- */

/* Similar to scavenge_large_bitmap(), but we don't write back the
 * pointers we get back from evacuate().
 */
static void
scavenge_large_srt_bitmap( StgLargeSRT *large_srt )
{
    nat i, b, size;
    StgWord bitmap;
    StgClosure **p;
    
    b = 0;
    bitmap = large_srt->l.bitmap[b];
    size   = (nat)large_srt->l.size;
    p      = (StgClosure **)large_srt->srt;
    for (i = 0; i < size; ) {
	if ((bitmap & 1) != 0) {
	    evacuate(p);
	}
	i++;
	p++;
	if (i % BITS_IN(W_) == 0) {
	    b++;
	    bitmap = large_srt->l.bitmap[b];
	} else {
	    bitmap = bitmap >> 1;
	}
    }
}

/* evacuate the SRT.  If srt_bitmap is zero, then there isn't an
 * srt field in the info table.  That's ok, because we'll
 * never dereference it.
 */
STATIC_INLINE GNUC_ATTR_HOT void
scavenge_srt (StgClosure **srt, nat srt_bitmap)
{
  nat bitmap;
  StgClosure **p;

  bitmap = srt_bitmap;
  p = srt;

  if (bitmap == (StgHalfWord)(-1)) {  
      scavenge_large_srt_bitmap( (StgLargeSRT *)srt );
      return;
  }

  while (bitmap != 0) {
      if ((bitmap & 1) != 0) {
#if defined(__PIC__) && defined(mingw32_TARGET_OS)
	  // Special-case to handle references to closures hiding out in DLLs, since
	  // double indirections required to get at those. The code generator knows
	  // which is which when generating the SRT, so it stores the (indirect)
	  // reference to the DLL closure in the table by first adding one to it.
	  // We check for this here, and undo the addition before evacuating it.
	  // 
	  // If the SRT entry hasn't got bit 0 set, the SRT entry points to a
	  // closure that's fixed at link-time, and no extra magic is required.
	  if ( (unsigned long)(*srt) & 0x1 ) {
	      evacuate(stgCast(StgClosure**,(stgCast(unsigned long, *srt) & ~0x1)));
	  } else {
	      evacuate(p);
	  }
#else
	  evacuate(p);
#endif
      }
      p++;
      bitmap = bitmap >> 1;
  }
}


STATIC_INLINE GNUC_ATTR_HOT void
scavenge_thunk_srt(const StgInfoTable *info)
{
    StgThunkInfoTable *thunk_info;

    if (!major_gc) return;

    thunk_info = itbl_to_thunk_itbl(info);
    scavenge_srt((StgClosure **)GET_SRT(thunk_info), thunk_info->i.srt_bitmap);
}

STATIC_INLINE GNUC_ATTR_HOT void
scavenge_fun_srt(const StgInfoTable *info)
{
    StgFunInfoTable *fun_info;

    if (!major_gc) return;
  
    fun_info = itbl_to_fun_itbl(info);
    scavenge_srt((StgClosure **)GET_FUN_SRT(fun_info), fun_info->i.srt_bitmap);
}

/* -----------------------------------------------------------------------------
   Scavenge a block from the given scan pointer up to bd->free.

   evac_step is set by the caller to be either zero (for a step in a
   generation < N) or G where G is the generation of the step being
   scavenged.  

   We sometimes temporarily change evac_step back to zero if we're
   scavenging a mutable object where eager promotion isn't such a good
   idea.  
   -------------------------------------------------------------------------- */

static GNUC_ATTR_HOT void
scavenge_block (bdescr *bd)
{
  StgPtr p, q;
  StgInfoTable *info;
  step *saved_evac_step;
  rtsBool saved_eager_promotion;
  step_workspace *ws;

  debugTrace(DEBUG_gc, "scavenging block %p (gen %d, step %d) @ %p",
	     bd->start, bd->gen_no, bd->step->no, bd->u.scan);

  gct->scan_bd = bd;
  gct->evac_step = bd->step;
  saved_evac_step = gct->evac_step;
  saved_eager_promotion = gct->eager_promotion;
  gct->failed_to_evac = rtsFalse;

  ws = &gct->steps[bd->step->abs_no];

  p = bd->u.scan;
  
  // we might be evacuating into the very object that we're
  // scavenging, so we have to check the real bd->free pointer each
  // time around the loop.
  while (p < bd->free || (bd == ws->todo_bd && p < ws->todo_free)) {

    ASSERT(LOOKS_LIKE_CLOSURE_PTR(p));
    info = get_itbl((StgClosure *)p);
    
    ASSERT(gct->thunk_selector_depth == 0);

    q = p;
    switch (info->type) {

    case MVAR_CLEAN:
    case MVAR_DIRTY:
    { 
	StgMVar *mvar = ((StgMVar *)p);
	gct->eager_promotion = rtsFalse;
	evacuate((StgClosure **)&mvar->head);
	evacuate((StgClosure **)&mvar->tail);
	evacuate((StgClosure **)&mvar->value);
	gct->eager_promotion = saved_eager_promotion;

	if (gct->failed_to_evac) {
	    mvar->header.info = &stg_MVAR_DIRTY_info;
	} else {
	    mvar->header.info = &stg_MVAR_CLEAN_info;
	}
	p += sizeofW(StgMVar);
	break;
    }

    case FUN_2_0:
	scavenge_fun_srt(info);
	evacuate(&((StgClosure *)p)->payload[1]);
	evacuate(&((StgClosure *)p)->payload[0]);
	p += sizeofW(StgHeader) + 2;
	break;

    case THUNK_2_0:
	scavenge_thunk_srt(info);
	evacuate(&((StgThunk *)p)->payload[1]);
	evacuate(&((StgThunk *)p)->payload[0]);
	p += sizeofW(StgThunk) + 2;
	break;

    case CONSTR_2_0:
	evacuate(&((StgClosure *)p)->payload[1]);
	evacuate(&((StgClosure *)p)->payload[0]);
	p += sizeofW(StgHeader) + 2;
	break;
	
    case THUNK_1_0:
	scavenge_thunk_srt(info);
	evacuate(&((StgThunk *)p)->payload[0]);
	p += sizeofW(StgThunk) + 1;
	break;
	
    case FUN_1_0:
	scavenge_fun_srt(info);
    case CONSTR_1_0:
	evacuate(&((StgClosure *)p)->payload[0]);
	p += sizeofW(StgHeader) + 1;
	break;
	
    case THUNK_0_1:
	scavenge_thunk_srt(info);
	p += sizeofW(StgThunk) + 1;
	break;
	
    case FUN_0_1:
	scavenge_fun_srt(info);
    case CONSTR_0_1:
	p += sizeofW(StgHeader) + 1;
	break;
	
    case THUNK_0_2:
	scavenge_thunk_srt(info);
	p += sizeofW(StgThunk) + 2;
	break;
	
    case FUN_0_2:
	scavenge_fun_srt(info);
    case CONSTR_0_2:
	p += sizeofW(StgHeader) + 2;
	break;
	
    case THUNK_1_1:
	scavenge_thunk_srt(info);
	evacuate(&((StgThunk *)p)->payload[0]);
	p += sizeofW(StgThunk) + 2;
	break;

    case FUN_1_1:
	scavenge_fun_srt(info);
    case CONSTR_1_1:
	evacuate(&((StgClosure *)p)->payload[0]);
	p += sizeofW(StgHeader) + 2;
	break;
	
    case FUN:
	scavenge_fun_srt(info);
	goto gen_obj;

    case THUNK:
    {
	StgPtr end;

	scavenge_thunk_srt(info);
	end = (P_)((StgThunk *)p)->payload + info->layout.payload.ptrs;
	for (p = (P_)((StgThunk *)p)->payload; p < end; p++) {
	    evacuate((StgClosure **)p);
	}
	p += info->layout.payload.nptrs;
	break;
    }
	
    gen_obj:
    case CONSTR:
    case WEAK:
    case STABLE_NAME:
    {
	StgPtr end;

	end = (P_)((StgClosure *)p)->payload + info->layout.payload.ptrs;
	for (p = (P_)((StgClosure *)p)->payload; p < end; p++) {
	    evacuate((StgClosure **)p);
	}
	p += info->layout.payload.nptrs;
	break;
    }

    case BCO: {
	StgBCO *bco = (StgBCO *)p;
	evacuate((StgClosure **)&bco->instrs);
	evacuate((StgClosure **)&bco->literals);
	evacuate((StgClosure **)&bco->ptrs);
	p += bco_sizeW(bco);
	break;
    }

    case IND_PERM:
      if (bd->gen_no != 0) {
#ifdef PROFILING
        // @LDV profiling
        // No need to call LDV_recordDead_FILL_SLOP_DYNAMIC() because an 
        // IND_OLDGEN_PERM closure is larger than an IND_PERM closure.
        LDV_recordDead((StgClosure *)p, sizeofW(StgInd));
#endif        
        // 
        // Todo: maybe use SET_HDR() and remove LDV_RECORD_CREATE()?
        //
	SET_INFO(((StgClosure *)p), &stg_IND_OLDGEN_PERM_info);

        // We pretend that p has just been created.
        LDV_RECORD_CREATE((StgClosure *)p);
      }
	// fall through 
    case IND_OLDGEN_PERM:
	evacuate(&((StgInd *)p)->indirectee);
	p += sizeofW(StgInd);
	break;

    case MUT_VAR_CLEAN:
    case MUT_VAR_DIRTY:
	gct->eager_promotion = rtsFalse;
	evacuate(&((StgMutVar *)p)->var);
	gct->eager_promotion = saved_eager_promotion;

	if (gct->failed_to_evac) {
	    ((StgClosure *)q)->header.info = &stg_MUT_VAR_DIRTY_info;
	} else {
	    ((StgClosure *)q)->header.info = &stg_MUT_VAR_CLEAN_info;
	}
	p += sizeofW(StgMutVar);
	break;

    case CAF_BLACKHOLE:
    case SE_CAF_BLACKHOLE:
    case SE_BLACKHOLE:
    case BLACKHOLE:
	p += BLACKHOLE_sizeW();
	break;

    case THUNK_SELECTOR:
    { 
	StgSelector *s = (StgSelector *)p;
	evacuate(&s->selectee);
	p += THUNK_SELECTOR_sizeW();
	break;
    }

    // A chunk of stack saved in a heap object
    case AP_STACK:
    {
	StgAP_STACK *ap = (StgAP_STACK *)p;

	evacuate(&ap->fun);
	scavenge_stack((StgPtr)ap->payload, (StgPtr)ap->payload + ap->size);
	p = (StgPtr)ap->payload + ap->size;
	break;
    }

    case PAP:
	p = scavenge_PAP((StgPAP *)p);
	break;

    case AP:
	p = scavenge_AP((StgAP *)p);
	break;

    case ARR_WORDS:
	// nothing to follow 
	p += arr_words_sizeW((StgArrWords *)p);
	break;

    case MUT_ARR_PTRS_CLEAN:
    case MUT_ARR_PTRS_DIRTY:
	// follow everything 
    {
	StgPtr next;

	// We don't eagerly promote objects pointed to by a mutable
	// array, but if we find the array only points to objects in
	// the same or an older generation, we mark it "clean" and
	// avoid traversing it during minor GCs.
	gct->eager_promotion = rtsFalse;
	next = p + mut_arr_ptrs_sizeW((StgMutArrPtrs*)p);
	for (p = (P_)((StgMutArrPtrs *)p)->payload; p < next; p++) {
	    evacuate((StgClosure **)p);
	}
	gct->eager_promotion = saved_eager_promotion;

	if (gct->failed_to_evac) {
	    ((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_DIRTY_info;
	} else {
	    ((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_CLEAN_info;
	}

	gct->failed_to_evac = rtsTrue; // always put it on the mutable list.
	break;
    }

    case MUT_ARR_PTRS_FROZEN:
    case MUT_ARR_PTRS_FROZEN0:
	// follow everything 
    {
	StgPtr next;

	next = p + mut_arr_ptrs_sizeW((StgMutArrPtrs*)p);
	for (p = (P_)((StgMutArrPtrs *)p)->payload; p < next; p++) {
	    evacuate((StgClosure **)p);
	}

	// If we're going to put this object on the mutable list, then
	// set its info ptr to MUT_ARR_PTRS_FROZEN0 to indicate that.
	if (gct->failed_to_evac) {
	    ((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_FROZEN0_info;
	} else {
	    ((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_FROZEN_info;
	}
	break;
    }

    case TSO:
    { 
	StgTSO *tso = (StgTSO *)p;
        scavengeTSO(tso);
	p += tso_sizeW(tso);
	break;
    }

    case TVAR_WATCH_QUEUE:
      {
	StgTVarWatchQueue *wq = ((StgTVarWatchQueue *) p);
	gct->evac_step = 0;
	evacuate((StgClosure **)&wq->closure);
	evacuate((StgClosure **)&wq->next_queue_entry);
	evacuate((StgClosure **)&wq->prev_queue_entry);
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	p += sizeofW(StgTVarWatchQueue);
	break;
      }

    case TVAR:
      {
	StgTVar *tvar = ((StgTVar *) p);
	gct->evac_step = 0;
	evacuate((StgClosure **)&tvar->current_value);
	evacuate((StgClosure **)&tvar->first_watch_queue_entry);
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	p += sizeofW(StgTVar);
	break;
      }

    case TREC_HEADER:
      {
        StgTRecHeader *trec = ((StgTRecHeader *) p);
        gct->evac_step = 0;
	evacuate((StgClosure **)&trec->enclosing_trec);
	evacuate((StgClosure **)&trec->current_chunk);
	evacuate((StgClosure **)&trec->invariants_to_check);
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	p += sizeofW(StgTRecHeader);
        break;
      }

    case TREC_CHUNK:
      {
	StgWord i;
	StgTRecChunk *tc = ((StgTRecChunk *) p);
	TRecEntry *e = &(tc -> entries[0]);
	gct->evac_step = 0;
	evacuate((StgClosure **)&tc->prev_chunk);
	for (i = 0; i < tc -> next_entry_idx; i ++, e++ ) {
	  evacuate((StgClosure **)&e->tvar);
	  evacuate((StgClosure **)&e->expected_value);
	  evacuate((StgClosure **)&e->new_value);
	}
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	p += sizeofW(StgTRecChunk);
	break;
      }

    case ATOMIC_INVARIANT:
      {
        StgAtomicInvariant *invariant = ((StgAtomicInvariant *) p);
        gct->evac_step = 0;
	evacuate(&invariant->code);
	evacuate((StgClosure **)&invariant->last_execution);
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	p += sizeofW(StgAtomicInvariant);
        break;
      }

    case INVARIANT_CHECK_QUEUE:
      {
        StgInvariantCheckQueue *queue = ((StgInvariantCheckQueue *) p);
        gct->evac_step = 0;
	evacuate((StgClosure **)&queue->invariant);
	evacuate((StgClosure **)&queue->my_execution);
	evacuate((StgClosure **)&queue->next_queue_entry);
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	p += sizeofW(StgInvariantCheckQueue);
        break;
      }

    default:
	barf("scavenge: unimplemented/strange closure type %d @ %p", 
	     info->type, p);
    }

    /*
     * We need to record the current object on the mutable list if
     *  (a) It is actually mutable, or 
     *  (b) It contains pointers to a younger generation.
     * Case (b) arises if we didn't manage to promote everything that
     * the current object points to into the current generation.
     */
    if (gct->failed_to_evac) {
	gct->failed_to_evac = rtsFalse;
	if (bd->gen_no > 0) {
	    recordMutableGen_GC((StgClosure *)q, &generations[bd->gen_no]);
	}
    }
  }

  if (p > bd->free)  {
      gct->copied += ws->todo_free - bd->free;
      bd->free = p;
  }

  debugTrace(DEBUG_gc, "   scavenged %ld bytes",
             (unsigned long)((bd->free - bd->u.scan) * sizeof(W_)));

  // update stats: this is a block that has been scavenged
  gct->scanned += bd->free - bd->u.scan;
  bd->u.scan = bd->free;

  if (bd != ws->todo_bd) {
      // we're not going to evac any more objects into
      // this block, so push it now.
      push_scanned_block(bd, ws);
  }

  gct->scan_bd = NULL;
}
/* -----------------------------------------------------------------------------
   Scavenge everything on the mark stack.

   This is slightly different from scavenge():
      - we don't walk linearly through the objects, so the scavenger
        doesn't need to advance the pointer on to the next object.
   -------------------------------------------------------------------------- */

static void
scavenge_mark_stack(void)
{
    StgPtr p, q;
    StgInfoTable *info;
    step *saved_evac_step;

    gct->evac_step = &oldest_gen->steps[0];
    saved_evac_step = gct->evac_step;

linear_scan:
    while (!mark_stack_empty()) {
	p = pop_mark_stack();

	ASSERT(LOOKS_LIKE_CLOSURE_PTR(p));
	info = get_itbl((StgClosure *)p);
	
	q = p;
        switch (info->type) {
	    
        case MVAR_CLEAN:
        case MVAR_DIRTY:
        { 
            rtsBool saved_eager_promotion = gct->eager_promotion;
            
            StgMVar *mvar = ((StgMVar *)p);
            gct->eager_promotion = rtsFalse;
            evacuate((StgClosure **)&mvar->head);
            evacuate((StgClosure **)&mvar->tail);
            evacuate((StgClosure **)&mvar->value);
            gct->eager_promotion = saved_eager_promotion;
            
            if (gct->failed_to_evac) {
                mvar->header.info = &stg_MVAR_DIRTY_info;
            } else {
                mvar->header.info = &stg_MVAR_CLEAN_info;
            }
            break;
        }

	case FUN_2_0:
	    scavenge_fun_srt(info);
	    evacuate(&((StgClosure *)p)->payload[1]);
	    evacuate(&((StgClosure *)p)->payload[0]);
	    break;

	case THUNK_2_0:
	    scavenge_thunk_srt(info);
	    evacuate(&((StgThunk *)p)->payload[1]);
	    evacuate(&((StgThunk *)p)->payload[0]);
	    break;

	case CONSTR_2_0:
	    evacuate(&((StgClosure *)p)->payload[1]);
	    evacuate(&((StgClosure *)p)->payload[0]);
	    break;
	
	case FUN_1_0:
	case FUN_1_1:
	    scavenge_fun_srt(info);
	    evacuate(&((StgClosure *)p)->payload[0]);
	    break;

	case THUNK_1_0:
	case THUNK_1_1:
	    scavenge_thunk_srt(info);
	    evacuate(&((StgThunk *)p)->payload[0]);
	    break;

	case CONSTR_1_0:
	case CONSTR_1_1:
	    evacuate(&((StgClosure *)p)->payload[0]);
	    break;
	
	case FUN_0_1:
	case FUN_0_2:
	    scavenge_fun_srt(info);
	    break;

	case THUNK_0_1:
	case THUNK_0_2:
	    scavenge_thunk_srt(info);
	    break;

	case CONSTR_0_1:
	case CONSTR_0_2:
	    break;
	
	case FUN:
	    scavenge_fun_srt(info);
	    goto gen_obj;

	case THUNK:
	{
	    StgPtr end;
	    
	    scavenge_thunk_srt(info);
	    end = (P_)((StgThunk *)p)->payload + info->layout.payload.ptrs;
	    for (p = (P_)((StgThunk *)p)->payload; p < end; p++) {
		evacuate((StgClosure **)p);
	    }
	    break;
	}
	
	gen_obj:
	case CONSTR:
	case WEAK:
	case STABLE_NAME:
	{
	    StgPtr end;
	    
	    end = (P_)((StgClosure *)p)->payload + info->layout.payload.ptrs;
	    for (p = (P_)((StgClosure *)p)->payload; p < end; p++) {
		evacuate((StgClosure **)p);
	    }
	    break;
	}

	case BCO: {
	    StgBCO *bco = (StgBCO *)p;
	    evacuate((StgClosure **)&bco->instrs);
	    evacuate((StgClosure **)&bco->literals);
	    evacuate((StgClosure **)&bco->ptrs);
	    break;
	}

	case IND_PERM:
	    // don't need to do anything here: the only possible case
	    // is that we're in a 1-space compacting collector, with
	    // no "old" generation.
	    break;

	case IND_OLDGEN:
	case IND_OLDGEN_PERM:
	    evacuate(&((StgInd *)p)->indirectee);
	    break;

	case MUT_VAR_CLEAN:
	case MUT_VAR_DIRTY: {
	    rtsBool saved_eager_promotion = gct->eager_promotion;
	    
	    gct->eager_promotion = rtsFalse;
	    evacuate(&((StgMutVar *)p)->var);
	    gct->eager_promotion = saved_eager_promotion;
	    
	    if (gct->failed_to_evac) {
		((StgClosure *)q)->header.info = &stg_MUT_VAR_DIRTY_info;
	    } else {
		((StgClosure *)q)->header.info = &stg_MUT_VAR_CLEAN_info;
	    }
	    break;
	}

	case CAF_BLACKHOLE:
	case SE_CAF_BLACKHOLE:
	case SE_BLACKHOLE:
	case BLACKHOLE:
	case ARR_WORDS:
	    break;

	case THUNK_SELECTOR:
	{ 
	    StgSelector *s = (StgSelector *)p;
	    evacuate(&s->selectee);
	    break;
	}

	// A chunk of stack saved in a heap object
	case AP_STACK:
	{
	    StgAP_STACK *ap = (StgAP_STACK *)p;
	    
	    evacuate(&ap->fun);
	    scavenge_stack((StgPtr)ap->payload, (StgPtr)ap->payload + ap->size);
	    break;
	}

	case PAP:
	    scavenge_PAP((StgPAP *)p);
	    break;

	case AP:
	    scavenge_AP((StgAP *)p);
	    break;
      
	case MUT_ARR_PTRS_CLEAN:
	case MUT_ARR_PTRS_DIRTY:
	    // follow everything 
	{
	    StgPtr next;
	    rtsBool saved_eager;

	    // We don't eagerly promote objects pointed to by a mutable
	    // array, but if we find the array only points to objects in
	    // the same or an older generation, we mark it "clean" and
	    // avoid traversing it during minor GCs.
	    saved_eager = gct->eager_promotion;
	    gct->eager_promotion = rtsFalse;
	    next = p + mut_arr_ptrs_sizeW((StgMutArrPtrs*)p);
	    for (p = (P_)((StgMutArrPtrs *)p)->payload; p < next; p++) {
		evacuate((StgClosure **)p);
	    }
	    gct->eager_promotion = saved_eager;

	    if (gct->failed_to_evac) {
		((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_DIRTY_info;
	    } else {
		((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_CLEAN_info;
	    }

	    gct->failed_to_evac = rtsTrue; // mutable anyhow.
	    break;
	}

	case MUT_ARR_PTRS_FROZEN:
	case MUT_ARR_PTRS_FROZEN0:
	    // follow everything 
	{
	    StgPtr next, q = p;
	    
	    next = p + mut_arr_ptrs_sizeW((StgMutArrPtrs*)p);
	    for (p = (P_)((StgMutArrPtrs *)p)->payload; p < next; p++) {
		evacuate((StgClosure **)p);
	    }

	    // If we're going to put this object on the mutable list, then
	    // set its info ptr to MUT_ARR_PTRS_FROZEN0 to indicate that.
	    if (gct->failed_to_evac) {
		((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_FROZEN0_info;
	    } else {
		((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_FROZEN_info;
	    }
	    break;
	}

	case TSO:
	{ 
            scavengeTSO((StgTSO*)p);
	    break;
	}

	case TVAR_WATCH_QUEUE:
	  {
	    StgTVarWatchQueue *wq = ((StgTVarWatchQueue *) p);
	    gct->evac_step = 0;
            evacuate((StgClosure **)&wq->closure);
	    evacuate((StgClosure **)&wq->next_queue_entry);
	    evacuate((StgClosure **)&wq->prev_queue_entry);
	    gct->evac_step = saved_evac_step;
	    gct->failed_to_evac = rtsTrue; // mutable
	    break;
	  }
	  
	case TVAR:
	  {
	    StgTVar *tvar = ((StgTVar *) p);
	    gct->evac_step = 0;
	    evacuate((StgClosure **)&tvar->current_value);
	    evacuate((StgClosure **)&tvar->first_watch_queue_entry);
	    gct->evac_step = saved_evac_step;
	    gct->failed_to_evac = rtsTrue; // mutable
	    break;
	  }
	  
	case TREC_CHUNK:
	  {
	    StgWord i;
	    StgTRecChunk *tc = ((StgTRecChunk *) p);
	    TRecEntry *e = &(tc -> entries[0]);
	    gct->evac_step = 0;
	    evacuate((StgClosure **)&tc->prev_chunk);
	    for (i = 0; i < tc -> next_entry_idx; i ++, e++ ) {
	      evacuate((StgClosure **)&e->tvar);
	      evacuate((StgClosure **)&e->expected_value);
	      evacuate((StgClosure **)&e->new_value);
	    }
	    gct->evac_step = saved_evac_step;
	    gct->failed_to_evac = rtsTrue; // mutable
	    break;
	  }

	case TREC_HEADER:
	  {
	    StgTRecHeader *trec = ((StgTRecHeader *) p);
	    gct->evac_step = 0;
	    evacuate((StgClosure **)&trec->enclosing_trec);
	    evacuate((StgClosure **)&trec->current_chunk);
  	    evacuate((StgClosure **)&trec->invariants_to_check);
	    gct->evac_step = saved_evac_step;
	    gct->failed_to_evac = rtsTrue; // mutable
	    break;
	  }

        case ATOMIC_INVARIANT:
          {
            StgAtomicInvariant *invariant = ((StgAtomicInvariant *) p);
            gct->evac_step = 0;
	    evacuate(&invariant->code);
    	    evacuate((StgClosure **)&invariant->last_execution);
	    gct->evac_step = saved_evac_step;
	    gct->failed_to_evac = rtsTrue; // mutable
            break;
          }

        case INVARIANT_CHECK_QUEUE:
          {
            StgInvariantCheckQueue *queue = ((StgInvariantCheckQueue *) p);
            gct->evac_step = 0;
    	    evacuate((StgClosure **)&queue->invariant);
	    evacuate((StgClosure **)&queue->my_execution);
            evacuate((StgClosure **)&queue->next_queue_entry);
	    gct->evac_step = saved_evac_step;
	    gct->failed_to_evac = rtsTrue; // mutable
            break;
          }

	default:
	    barf("scavenge_mark_stack: unimplemented/strange closure type %d @ %p", 
		 info->type, p);
	}

	if (gct->failed_to_evac) {
	    gct->failed_to_evac = rtsFalse;
	    if (gct->evac_step) {
		recordMutableGen_GC((StgClosure *)q, gct->evac_step->gen);
	    }
	}
	
	// mark the next bit to indicate "scavenged"
	mark(q+1, Bdescr(q));

    } // while (!mark_stack_empty())

    // start a new linear scan if the mark stack overflowed at some point
    if (mark_stack_overflowed && oldgen_scan_bd == NULL) {
	debugTrace(DEBUG_gc, "scavenge_mark_stack: starting linear scan");
	mark_stack_overflowed = rtsFalse;
	oldgen_scan_bd = oldest_gen->steps[0].old_blocks;
	oldgen_scan = oldgen_scan_bd->start;
    }

    if (oldgen_scan_bd) {
	// push a new thing on the mark stack
    loop:
	// find a closure that is marked but not scavenged, and start
	// from there.
	while (oldgen_scan < oldgen_scan_bd->free 
	       && !is_marked(oldgen_scan,oldgen_scan_bd)) {
	    oldgen_scan++;
	}

	if (oldgen_scan < oldgen_scan_bd->free) {

	    // already scavenged?
	    if (is_marked(oldgen_scan+1,oldgen_scan_bd)) {
		oldgen_scan += sizeofW(StgHeader) + MIN_PAYLOAD_SIZE;
		goto loop;
	    }
	    push_mark_stack(oldgen_scan);
	    // ToDo: bump the linear scan by the actual size of the object
	    oldgen_scan += sizeofW(StgHeader) + MIN_PAYLOAD_SIZE;
	    goto linear_scan;
	}

	oldgen_scan_bd = oldgen_scan_bd->link;
	if (oldgen_scan_bd != NULL) {
	    oldgen_scan = oldgen_scan_bd->start;
	    goto loop;
	}
    }
}

/* -----------------------------------------------------------------------------
   Scavenge one object.

   This is used for objects that are temporarily marked as mutable
   because they contain old-to-new generation pointers.  Only certain
   objects can have this property.
   -------------------------------------------------------------------------- */

static rtsBool
scavenge_one(StgPtr p)
{
    const StgInfoTable *info;
    step *saved_evac_step = gct->evac_step;
    rtsBool no_luck;
    
    ASSERT(LOOKS_LIKE_CLOSURE_PTR(p));
    info = get_itbl((StgClosure *)p);
    
    switch (info->type) {
	
    case MVAR_CLEAN:
    case MVAR_DIRTY:
    { 
	rtsBool saved_eager_promotion = gct->eager_promotion;

	StgMVar *mvar = ((StgMVar *)p);
	gct->eager_promotion = rtsFalse;
	evacuate((StgClosure **)&mvar->head);
	evacuate((StgClosure **)&mvar->tail);
	evacuate((StgClosure **)&mvar->value);
	gct->eager_promotion = saved_eager_promotion;

	if (gct->failed_to_evac) {
	    mvar->header.info = &stg_MVAR_DIRTY_info;
	} else {
	    mvar->header.info = &stg_MVAR_CLEAN_info;
	}
	break;
    }

    case THUNK:
    case THUNK_1_0:
    case THUNK_0_1:
    case THUNK_1_1:
    case THUNK_0_2:
    case THUNK_2_0:
    {
	StgPtr q, end;
	
	end = (StgPtr)((StgThunk *)p)->payload + info->layout.payload.ptrs;
	for (q = (StgPtr)((StgThunk *)p)->payload; q < end; q++) {
	    evacuate((StgClosure **)q);
	}
	break;
    }

    case FUN:
    case FUN_1_0:			// hardly worth specialising these guys
    case FUN_0_1:
    case FUN_1_1:
    case FUN_0_2:
    case FUN_2_0:
    case CONSTR:
    case CONSTR_1_0:
    case CONSTR_0_1:
    case CONSTR_1_1:
    case CONSTR_0_2:
    case CONSTR_2_0:
    case WEAK:
    case IND_PERM:
    {
	StgPtr q, end;
	
	end = (StgPtr)((StgClosure *)p)->payload + info->layout.payload.ptrs;
	for (q = (StgPtr)((StgClosure *)p)->payload; q < end; q++) {
	    evacuate((StgClosure **)q);
	}
	break;
    }
    
    case MUT_VAR_CLEAN:
    case MUT_VAR_DIRTY: {
	StgPtr q = p;
	rtsBool saved_eager_promotion = gct->eager_promotion;

	gct->eager_promotion = rtsFalse;
	evacuate(&((StgMutVar *)p)->var);
	gct->eager_promotion = saved_eager_promotion;

	if (gct->failed_to_evac) {
	    ((StgClosure *)q)->header.info = &stg_MUT_VAR_DIRTY_info;
	} else {
	    ((StgClosure *)q)->header.info = &stg_MUT_VAR_CLEAN_info;
	}
	break;
    }

    case CAF_BLACKHOLE:
    case SE_CAF_BLACKHOLE:
    case SE_BLACKHOLE:
    case BLACKHOLE:
	break;
	
    case THUNK_SELECTOR:
    { 
	StgSelector *s = (StgSelector *)p;
	evacuate(&s->selectee);
	break;
    }
    
    case AP_STACK:
    {
	StgAP_STACK *ap = (StgAP_STACK *)p;

	evacuate(&ap->fun);
	scavenge_stack((StgPtr)ap->payload, (StgPtr)ap->payload + ap->size);
	p = (StgPtr)ap->payload + ap->size;
	break;
    }

    case PAP:
	p = scavenge_PAP((StgPAP *)p);
	break;

    case AP:
	p = scavenge_AP((StgAP *)p);
	break;

    case ARR_WORDS:
	// nothing to follow 
	break;

    case MUT_ARR_PTRS_CLEAN:
    case MUT_ARR_PTRS_DIRTY:
    {
	StgPtr next, q;
	rtsBool saved_eager;

	// We don't eagerly promote objects pointed to by a mutable
	// array, but if we find the array only points to objects in
	// the same or an older generation, we mark it "clean" and
	// avoid traversing it during minor GCs.
	saved_eager = gct->eager_promotion;
	gct->eager_promotion = rtsFalse;
	q = p;
	next = p + mut_arr_ptrs_sizeW((StgMutArrPtrs*)p);
	for (p = (P_)((StgMutArrPtrs *)p)->payload; p < next; p++) {
	    evacuate((StgClosure **)p);
	}
	gct->eager_promotion = saved_eager;

	if (gct->failed_to_evac) {
	    ((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_DIRTY_info;
	} else {
	    ((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_CLEAN_info;
	}

	gct->failed_to_evac = rtsTrue;
	break;
    }

    case MUT_ARR_PTRS_FROZEN:
    case MUT_ARR_PTRS_FROZEN0:
    {
	// follow everything 
	StgPtr next, q=p;
      
	next = p + mut_arr_ptrs_sizeW((StgMutArrPtrs*)p);
	for (p = (P_)((StgMutArrPtrs *)p)->payload; p < next; p++) {
	    evacuate((StgClosure **)p);
	}

	// If we're going to put this object on the mutable list, then
	// set its info ptr to MUT_ARR_PTRS_FROZEN0 to indicate that.
	if (gct->failed_to_evac) {
	    ((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_FROZEN0_info;
	} else {
	    ((StgClosure *)q)->header.info = &stg_MUT_ARR_PTRS_FROZEN_info;
	}
	break;
    }

    case TSO:
    {
	scavengeTSO((StgTSO*)p);
	break;
    }
  
    case TVAR_WATCH_QUEUE:
      {
	StgTVarWatchQueue *wq = ((StgTVarWatchQueue *) p);
	gct->evac_step = 0;
        evacuate((StgClosure **)&wq->closure);
        evacuate((StgClosure **)&wq->next_queue_entry);
        evacuate((StgClosure **)&wq->prev_queue_entry);
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	break;
      }

    case TVAR:
      {
	StgTVar *tvar = ((StgTVar *) p);
	gct->evac_step = 0;
	evacuate((StgClosure **)&tvar->current_value);
        evacuate((StgClosure **)&tvar->first_watch_queue_entry);
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	break;
      }

    case TREC_HEADER:
      {
        StgTRecHeader *trec = ((StgTRecHeader *) p);
        gct->evac_step = 0;
	evacuate((StgClosure **)&trec->enclosing_trec);
	evacuate((StgClosure **)&trec->current_chunk);
        evacuate((StgClosure **)&trec->invariants_to_check);
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
        break;
      }

    case TREC_CHUNK:
      {
	StgWord i;
	StgTRecChunk *tc = ((StgTRecChunk *) p);
	TRecEntry *e = &(tc -> entries[0]);
	gct->evac_step = 0;
	evacuate((StgClosure **)&tc->prev_chunk);
	for (i = 0; i < tc -> next_entry_idx; i ++, e++ ) {
	  evacuate((StgClosure **)&e->tvar);
	  evacuate((StgClosure **)&e->expected_value);
	  evacuate((StgClosure **)&e->new_value);
	}
	gct->evac_step = saved_evac_step;
	gct->failed_to_evac = rtsTrue; // mutable
	break;
      }

    case ATOMIC_INVARIANT:
    {
      StgAtomicInvariant *invariant = ((StgAtomicInvariant *) p);
      gct->evac_step = 0;
      evacuate(&invariant->code);
      evacuate((StgClosure **)&invariant->last_execution);
      gct->evac_step = saved_evac_step;
      gct->failed_to_evac = rtsTrue; // mutable
      break;
    }

    case INVARIANT_CHECK_QUEUE:
    {
      StgInvariantCheckQueue *queue = ((StgInvariantCheckQueue *) p);
      gct->evac_step = 0;
      evacuate((StgClosure **)&queue->invariant);
      evacuate((StgClosure **)&queue->my_execution);
      evacuate((StgClosure **)&queue->next_queue_entry);
      gct->evac_step = saved_evac_step;
      gct->failed_to_evac = rtsTrue; // mutable
      break;
    }

    case IND_OLDGEN:
    case IND_OLDGEN_PERM:
    case IND_STATIC:
    {
	/* Careful here: a THUNK can be on the mutable list because
	 * it contains pointers to young gen objects.  If such a thunk
	 * is updated, the IND_OLDGEN will be added to the mutable
	 * list again, and we'll scavenge it twice.  evacuate()
	 * doesn't check whether the object has already been
	 * evacuated, so we perform that check here.
	 */
	StgClosure *q = ((StgInd *)p)->indirectee;
	if (HEAP_ALLOCED_GC(q) && Bdescr((StgPtr)q)->flags & BF_EVACUATED) {
	    break;
	}
	evacuate(&((StgInd *)p)->indirectee);
    }

#if 0 && defined(DEBUG)
      if (RtsFlags.DebugFlags.gc) 
      /* Debugging code to print out the size of the thing we just
       * promoted 
       */
      { 
	StgPtr start = gen->steps[0].scan;
	bdescr *start_bd = gen->steps[0].scan_bd;
	nat size = 0;
	scavenge(&gen->steps[0]);
	if (start_bd != gen->steps[0].scan_bd) {
	  size += (P_)BLOCK_ROUND_UP(start) - start;
	  start_bd = start_bd->link;
	  while (start_bd != gen->steps[0].scan_bd) {
	    size += BLOCK_SIZE_W;
	    start_bd = start_bd->link;
	  }
	  size += gen->steps[0].scan -
	    (P_)BLOCK_ROUND_DOWN(gen->steps[0].scan);
	} else {
	  size = gen->steps[0].scan - start;
	}
	debugBelch("evac IND_OLDGEN: %ld bytes", size * sizeof(W_));
      }
#endif
      break;

    default:
	barf("scavenge_one: strange object %d", (int)(info->type));
    }    

    no_luck = gct->failed_to_evac;
    gct->failed_to_evac = rtsFalse;
    return (no_luck);
}

/* -----------------------------------------------------------------------------
   Scavenging mutable lists.

   We treat the mutable list of each generation > N (i.e. all the
   generations older than the one being collected) as roots.  We also
   remove non-mutable objects from the mutable list at this point.
   -------------------------------------------------------------------------- */

void
scavenge_mutable_list(generation *gen)
{
    bdescr *bd;
    StgPtr p, q;

    bd = gen->saved_mut_list;

    gct->evac_step = &gen->steps[0];
    for (; bd != NULL; bd = bd->link) {
	for (q = bd->start; q < bd->free; q++) {
	    p = (StgPtr)*q;
	    ASSERT(LOOKS_LIKE_CLOSURE_PTR(p));

#ifdef DEBUG	    
	    switch (get_itbl((StgClosure *)p)->type) {
	    case MUT_VAR_CLEAN:
		barf("MUT_VAR_CLEAN on mutable list");
	    case MUT_VAR_DIRTY:
		mutlist_MUTVARS++; break;
	    case MUT_ARR_PTRS_CLEAN:
	    case MUT_ARR_PTRS_DIRTY:
	    case MUT_ARR_PTRS_FROZEN:
	    case MUT_ARR_PTRS_FROZEN0:
		mutlist_MUTARRS++; break;
	    case MVAR_CLEAN:
		barf("MVAR_CLEAN on mutable list");
	    case MVAR_DIRTY:
		mutlist_MVARS++; break;
	    default:
		mutlist_OTHERS++; break;
	    }
#endif

	    // Check whether this object is "clean", that is it
	    // definitely doesn't point into a young generation.
	    // Clean objects don't need to be scavenged.  Some clean
	    // objects (MUT_VAR_CLEAN) are not kept on the mutable
	    // list at all; others, such as MUT_ARR_PTRS_CLEAN and
	    // TSO, are always on the mutable list.
	    //
	    switch (get_itbl((StgClosure *)p)->type) {
	    case MUT_ARR_PTRS_CLEAN:
		recordMutableGen_GC((StgClosure *)p,gen);
		continue;
	    case TSO: {
		StgTSO *tso = (StgTSO *)p;
		if ((tso->flags & TSO_DIRTY) == 0) {
                    // Must be on the mutable list because its link
                    // field is dirty.
                    ASSERT(tso->flags & TSO_LINK_DIRTY);

                    scavenge_TSO_link(tso);
                    if (gct->failed_to_evac) {
                        recordMutableGen_GC((StgClosure *)p,gen);
                        gct->failed_to_evac = rtsFalse;
                    } else {
                        tso->flags &= ~TSO_LINK_DIRTY;
                    }
		    continue;
		}
	    }
	    default:
		;
	    }

	    if (scavenge_one(p)) {
		// didn't manage to promote everything, so put the
		// object back on the list.
		recordMutableGen_GC((StgClosure *)p,gen);
	    }
	}
    }

    // free the old mut_list
    freeChain_sync(gen->saved_mut_list);
    gen->saved_mut_list = NULL;
}

/* -----------------------------------------------------------------------------
   Scavenging the static objects.

   We treat the mutable list of each generation > N (i.e. all the
   generations older than the one being collected) as roots.  We also
   remove non-mutable objects from the mutable list at this point.
   -------------------------------------------------------------------------- */

static void
scavenge_static(void)
{
  StgClosure* p;
  const StgInfoTable *info;

  debugTrace(DEBUG_gc, "scavenging static objects");

  /* Always evacuate straight to the oldest generation for static
   * objects */
  gct->evac_step = &oldest_gen->steps[0];

  /* keep going until we've scavenged all the objects on the linked
     list... */

  while (1) {
      
    /* get the next static object from the list.  Remember, there might
     * be more stuff on this list after each evacuation...
     * (static_objects is a global)
     */
    p = gct->static_objects;
    if (p == END_OF_STATIC_LIST) {
    	  break;
    }
    
    ASSERT(LOOKS_LIKE_CLOSURE_PTR(p));
    info = get_itbl(p);
    /*
    	if (info->type==RBH)
    	info = REVERT_INFOPTR(info); // if it's an RBH, look at the orig closure
    */
    // make sure the info pointer is into text space 
    
    /* Take this object *off* the static_objects list,
     * and put it on the scavenged_static_objects list.
     */
    gct->static_objects = *STATIC_LINK(info,p);
    *STATIC_LINK(info,p) = gct->scavenged_static_objects;
    gct->scavenged_static_objects = p;
    
    switch (info -> type) {
      
    case IND_STATIC:
      {
	StgInd *ind = (StgInd *)p;
	evacuate(&ind->indirectee);

	/* might fail to evacuate it, in which case we have to pop it
	 * back on the mutable list of the oldest generation.  We
	 * leave it *on* the scavenged_static_objects list, though,
	 * in case we visit this object again.
	 */
	if (gct->failed_to_evac) {
	  gct->failed_to_evac = rtsFalse;
	  recordMutableGen_GC((StgClosure *)p,oldest_gen);
	}
	break;
      }
      
    case THUNK_STATIC:
      scavenge_thunk_srt(info);
      break;

    case FUN_STATIC:
      scavenge_fun_srt(info);
      break;
      
    case CONSTR_STATIC:
      {	
	StgPtr q, next;
	
	next = (P_)p->payload + info->layout.payload.ptrs;
	// evacuate the pointers 
	for (q = (P_)p->payload; q < next; q++) {
	    evacuate((StgClosure **)q);
	}
	break;
      }
      
    default:
      barf("scavenge_static: strange closure %d", (int)(info->type));
    }

    ASSERT(gct->failed_to_evac == rtsFalse);
  }
}

/* -----------------------------------------------------------------------------
   scavenge a chunk of memory described by a bitmap
   -------------------------------------------------------------------------- */

static void
scavenge_large_bitmap( StgPtr p, StgLargeBitmap *large_bitmap, nat size )
{
    nat i, b;
    StgWord bitmap;
    
    b = 0;
    bitmap = large_bitmap->bitmap[b];
    for (i = 0; i < size; ) {
	if ((bitmap & 1) == 0) {
	    evacuate((StgClosure **)p);
	}
	i++;
	p++;
	if (i % BITS_IN(W_) == 0) {
	    b++;
	    bitmap = large_bitmap->bitmap[b];
	} else {
	    bitmap = bitmap >> 1;
	}
    }
}

STATIC_INLINE StgPtr
scavenge_small_bitmap (StgPtr p, nat size, StgWord bitmap)
{
    while (size > 0) {
	if ((bitmap & 1) == 0) {
	    evacuate((StgClosure **)p);
	}
	p++;
	bitmap = bitmap >> 1;
	size--;
    }
    return p;
}

/* -----------------------------------------------------------------------------
   scavenge_stack walks over a section of stack and evacuates all the
   objects pointed to by it.  We can use the same code for walking
   AP_STACK_UPDs, since these are just sections of copied stack.
   -------------------------------------------------------------------------- */

static void
scavenge_stack(StgPtr p, StgPtr stack_end)
{
  const StgRetInfoTable* info;
  StgWord bitmap;
  nat size;

  /* 
   * Each time around this loop, we are looking at a chunk of stack
   * that starts with an activation record. 
   */

  while (p < stack_end) {
    info  = get_ret_itbl((StgClosure *)p);
      
    switch (info->i.type) {
	
    case UPDATE_FRAME:
	// In SMP, we can get update frames that point to indirections
	// when two threads evaluate the same thunk.  We do attempt to
	// discover this situation in threadPaused(), but it's
	// possible that the following sequence occurs:
	//
	//        A             B
	//                  enter T
	//     enter T
	//     blackhole T
	//                  update T
	//     GC
	//
	// Now T is an indirection, and the update frame is already
	// marked on A's stack, so we won't traverse it again in
	// threadPaused().  We could traverse the whole stack again
	// before GC, but that seems like overkill.
	//
	// Scavenging this update frame as normal would be disastrous;
	// the updatee would end up pointing to the value.  So we turn
	// the indirection into an IND_PERM, so that evacuate will
	// copy the indirection into the old generation instead of
	// discarding it.
    {
        nat type;
        const StgInfoTable *i;

        i = ((StgUpdateFrame *)p)->updatee->header.info;
        if (!IS_FORWARDING_PTR(i)) {
            type = get_itbl(((StgUpdateFrame *)p)->updatee)->type;
            if (type == IND) {
                ((StgUpdateFrame *)p)->updatee->header.info = 
                    (StgInfoTable *)&stg_IND_PERM_info;
            } else if (type == IND_OLDGEN) {
                ((StgUpdateFrame *)p)->updatee->header.info = 
                    (StgInfoTable *)&stg_IND_OLDGEN_PERM_info;
            }            
            evacuate(&((StgUpdateFrame *)p)->updatee);
            p += sizeofW(StgUpdateFrame);
            continue;
        }
    }

      // small bitmap (< 32 entries, or 64 on a 64-bit machine) 
    case CATCH_STM_FRAME:
    case CATCH_RETRY_FRAME:
    case ATOMICALLY_FRAME:
    case STOP_FRAME:
    case CATCH_FRAME:
    case RET_SMALL:
	bitmap = BITMAP_BITS(info->i.layout.bitmap);
	size   = BITMAP_SIZE(info->i.layout.bitmap);
	// NOTE: the payload starts immediately after the info-ptr, we
	// don't have an StgHeader in the same sense as a heap closure.
	p++;
	p = scavenge_small_bitmap(p, size, bitmap);

    follow_srt:
	if (major_gc) 
	    scavenge_srt((StgClosure **)GET_SRT(info), info->i.srt_bitmap);
	continue;

    case RET_BCO: {
	StgBCO *bco;
	nat size;

	p++;
	evacuate((StgClosure **)p);
	bco = (StgBCO *)*p;
	p++;
	size = BCO_BITMAP_SIZE(bco);
	scavenge_large_bitmap(p, BCO_BITMAP(bco), size);
	p += size;
	continue;
    }

      // large bitmap (> 32 entries, or > 64 on a 64-bit machine) 
    case RET_BIG:
    {
	nat size;

	size = GET_LARGE_BITMAP(&info->i)->size;
	p++;
	scavenge_large_bitmap(p, GET_LARGE_BITMAP(&info->i), size);
	p += size;
	// and don't forget to follow the SRT 
	goto follow_srt;
    }

      // Dynamic bitmap: the mask is stored on the stack, and
      // there are a number of non-pointers followed by a number
      // of pointers above the bitmapped area.  (see StgMacros.h,
      // HEAP_CHK_GEN).
    case RET_DYN:
    {
	StgWord dyn;
	dyn = ((StgRetDyn *)p)->liveness;

	// traverse the bitmap first
	bitmap = RET_DYN_LIVENESS(dyn);
	p      = (P_)&((StgRetDyn *)p)->payload[0];
	size   = RET_DYN_BITMAP_SIZE;
	p = scavenge_small_bitmap(p, size, bitmap);

	// skip over the non-ptr words
	p += RET_DYN_NONPTRS(dyn) + RET_DYN_NONPTR_REGS_SIZE;
	
	// follow the ptr words
	for (size = RET_DYN_PTRS(dyn); size > 0; size--) {
	    evacuate((StgClosure **)p);
	    p++;
	}
	continue;
    }

    case RET_FUN:
    {
	StgRetFun *ret_fun = (StgRetFun *)p;
	StgFunInfoTable *fun_info;

	evacuate(&ret_fun->fun);
 	fun_info = get_fun_itbl(UNTAG_CLOSURE(ret_fun->fun));
	p = scavenge_arg_block(fun_info, ret_fun->payload);
	goto follow_srt;
    }

    default:
	barf("scavenge_stack: weird activation record found on stack: %d", (int)(info->i.type));
    }
  }		     
}

/*-----------------------------------------------------------------------------
  scavenge the large object list.

  evac_step set by caller; similar games played with evac_step as with
  scavenge() - see comment at the top of scavenge().  Most large
  objects are (repeatedly) mutable, so most of the time evac_step will
  be zero.
  --------------------------------------------------------------------------- */

static void
scavenge_large (step_workspace *ws)
{
    bdescr *bd;
    StgPtr p;

    gct->evac_step = ws->step;

    bd = ws->todo_large_objects;
    
    for (; bd != NULL; bd = ws->todo_large_objects) {
	
	// take this object *off* the large objects list and put it on
	// the scavenged large objects list.  This is so that we can
	// treat new_large_objects as a stack and push new objects on
	// the front when evacuating.
	ws->todo_large_objects = bd->link;
	
	ACQUIRE_SPIN_LOCK(&ws->step->sync_large_objects);
	dbl_link_onto(bd, &ws->step->scavenged_large_objects);
	ws->step->n_scavenged_large_blocks += bd->blocks;
	RELEASE_SPIN_LOCK(&ws->step->sync_large_objects);
	
	p = bd->start;
	if (scavenge_one(p)) {
	    if (ws->step->gen_no > 0) {
		recordMutableGen_GC((StgClosure *)p, ws->step->gen);
	    }
	}

        // stats
        gct->scanned += closure_sizeW((StgClosure*)p);
    }
}

/* ----------------------------------------------------------------------------
   Look for work to do.

   We look for the oldest step that has either a todo block that can
   be scanned, or a block of work on the global queue that we can
   scan.

   It is important to take work from the *oldest* generation that we
   has work available, because that minimizes the likelihood of
   evacuating objects into a young generation when they should have
   been eagerly promoted.  This really does make a difference (the
   cacheprof benchmark is one that is affected).

   We also want to scan the todo block if possible before grabbing
   work from the global queue, the reason being that we don't want to
   steal work from the global queue and starve other threads if there
   is other work we can usefully be doing.
   ------------------------------------------------------------------------- */

static rtsBool
scavenge_find_work (void)
{
    int s;
    step_workspace *ws;
    rtsBool did_something, did_anything;
    bdescr *bd;

    gct->scav_find_work++;

    did_anything = rtsFalse;

loop:
    did_something = rtsFalse;
    for (s = total_steps-1; s >= 0; s--) {
        if (s == 0 && RtsFlags.GcFlags.generations > 1) { 
            continue; 
        }
        ws = &gct->steps[s];
        
        gct->scan_bd = NULL;

        // If we have a scan block with some work to do,
        // scavenge everything up to the free pointer.
        if (ws->todo_bd->u.scan < ws->todo_free)
        {
            scavenge_block(ws->todo_bd);
            did_something = rtsTrue;
            break;
        }

        // If we have any large objects to scavenge, do them now.
        if (ws->todo_large_objects) {
            scavenge_large(ws);
            did_something = rtsTrue;
            break;
        }

        if ((bd = grab_todo_block(ws)) != NULL) {
            scavenge_block(bd);
            did_something = rtsTrue;
            break;
        }
    }

    if (did_something) {
        did_anything = rtsTrue;
        goto loop;
    }
    // only return when there is no more work to do

    return did_anything;
}

/* ----------------------------------------------------------------------------
   Scavenge until we can't find anything more to scavenge.
   ------------------------------------------------------------------------- */

void
scavenge_loop(void)
{
    rtsBool work_to_do;

loop:
    work_to_do = rtsFalse;

    // scavenge static objects 
    if (major_gc && gct->static_objects != END_OF_STATIC_LIST) {
	IF_DEBUG(sanity, checkStaticObjects(gct->static_objects));
	scavenge_static();
    }
    
    // scavenge objects in compacted generation
    if (mark_stack_overflowed || oldgen_scan_bd != NULL ||
	(mark_stack_bdescr != NULL && !mark_stack_empty())) {
	scavenge_mark_stack();
	work_to_do = rtsTrue;
    }
    
    // Order is important here: we want to deal in full blocks as
    // much as possible, so go for global work in preference to
    // local work.  Only if all the global work has been exhausted
    // do we start scavenging the fragments of blocks in the local
    // workspaces.
    if (scavenge_find_work()) goto loop;
    
    if (work_to_do) goto loop;
}
