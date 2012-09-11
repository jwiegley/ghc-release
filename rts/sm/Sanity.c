/* -----------------------------------------------------------------------------
 *
 * (c) The GHC Team, 1998-2006
 *
 * Sanity checking code for the heap and stack.
 *
 * Used when debugging: check that everything reasonable.
 *
 *    - All things that are supposed to be pointers look like pointers.
 *
 *    - Objects in text space are marked as static closures, those
 *	in the heap are dynamic.
 *
 * ---------------------------------------------------------------------------*/

#include "PosixSource.h"
#include "Rts.h"

#ifdef DEBUG                                                   /* whole file */

#include "RtsUtils.h"
#include "sm/Storage.h"
#include "sm/BlockAlloc.h"
#include "Sanity.h"
#include "Schedule.h"
#include "Apply.h"
#include "Printer.h"
#include "Arena.h"
#include "RetainerProfile.h"

/* -----------------------------------------------------------------------------
   Forward decls.
   -------------------------------------------------------------------------- */

static void      checkSmallBitmap    ( StgPtr payload, StgWord bitmap, nat );
static void      checkLargeBitmap    ( StgPtr payload, StgLargeBitmap*, nat );
static void      checkClosureShallow ( StgClosure * );

/* -----------------------------------------------------------------------------
   Check stack sanity
   -------------------------------------------------------------------------- */

static void
checkSmallBitmap( StgPtr payload, StgWord bitmap, nat size )
{
    StgPtr p;
    nat i;

    p = payload;
    for(i = 0; i < size; i++, bitmap >>= 1 ) {
	if ((bitmap & 1) == 0) {
	    checkClosureShallow((StgClosure *)payload[i]);
	}
    }
}

static void
checkLargeBitmap( StgPtr payload, StgLargeBitmap* large_bitmap, nat size )
{
    StgWord bmp;
    nat i, j;

    i = 0;
    for (bmp=0; i < size; bmp++) {
	StgWord bitmap = large_bitmap->bitmap[bmp];
	j = 0;
	for(; i < size && j < BITS_IN(W_); j++, i++, bitmap >>= 1 ) {
	    if ((bitmap & 1) == 0) {
		checkClosureShallow((StgClosure *)payload[i]);
	    }
	}
    }
}

/*
 * check that it looks like a valid closure - without checking its payload
 * used to avoid recursion between checking PAPs and checking stack
 * chunks.
 */
 
static void 
checkClosureShallow( StgClosure* p )
{
    StgClosure *q;

    q = UNTAG_CLOSURE(p);
    ASSERT(LOOKS_LIKE_CLOSURE_PTR(q));

    /* Is it a static closure? */
    if (!HEAP_ALLOCED(q)) {
	ASSERT(closure_STATIC(q));
    } else {
	ASSERT(!closure_STATIC(q));
    }
}

// check an individual stack object
StgOffset 
checkStackFrame( StgPtr c )
{
    nat size;
    const StgRetInfoTable* info;

    info = get_ret_itbl((StgClosure *)c);

    /* All activation records have 'bitmap' style layout info. */
    switch (info->i.type) {
    case RET_DYN: /* Dynamic bitmap: the mask is stored on the stack */
    {
	StgWord dyn;
	StgPtr p;
	StgRetDyn* r;
	
	r = (StgRetDyn *)c;
	dyn = r->liveness;
	
	p = (P_)(r->payload);
	checkSmallBitmap(p,RET_DYN_LIVENESS(r->liveness),RET_DYN_BITMAP_SIZE);
	p += RET_DYN_BITMAP_SIZE + RET_DYN_NONPTR_REGS_SIZE;

	// skip over the non-pointers
	p += RET_DYN_NONPTRS(dyn);
	
	// follow the ptr words
	for (size = RET_DYN_PTRS(dyn); size > 0; size--) {
	    checkClosureShallow((StgClosure *)*p);
	    p++;
	}
	
	return sizeofW(StgRetDyn) + RET_DYN_BITMAP_SIZE +
	    RET_DYN_NONPTR_REGS_SIZE +
	    RET_DYN_NONPTRS(dyn) + RET_DYN_PTRS(dyn);
    }

    case UPDATE_FRAME:
      ASSERT(LOOKS_LIKE_CLOSURE_PTR(((StgUpdateFrame*)c)->updatee));
    case ATOMICALLY_FRAME:
    case CATCH_RETRY_FRAME:
    case CATCH_STM_FRAME:
    case CATCH_FRAME:
      // small bitmap cases (<= 32 entries)
    case STOP_FRAME:
    case RET_SMALL:
	size = BITMAP_SIZE(info->i.layout.bitmap);
	checkSmallBitmap((StgPtr)c + 1, 
			 BITMAP_BITS(info->i.layout.bitmap), size);
	return 1 + size;

    case RET_BCO: {
	StgBCO *bco;
	nat size;
	bco = (StgBCO *)*(c+1);
	size = BCO_BITMAP_SIZE(bco);
	checkLargeBitmap((StgPtr)c + 2, BCO_BITMAP(bco), size);
	return 2 + size;
    }

    case RET_BIG: // large bitmap (> 32 entries)
	size = GET_LARGE_BITMAP(&info->i)->size;
	checkLargeBitmap((StgPtr)c + 1, GET_LARGE_BITMAP(&info->i), size);
	return 1 + size;

    case RET_FUN:
    {
	StgFunInfoTable *fun_info;
	StgRetFun *ret_fun;

	ret_fun = (StgRetFun *)c;
	fun_info = get_fun_itbl(UNTAG_CLOSURE(ret_fun->fun));
	size = ret_fun->size;
	switch (fun_info->f.fun_type) {
	case ARG_GEN:
	    checkSmallBitmap((StgPtr)ret_fun->payload, 
			     BITMAP_BITS(fun_info->f.b.bitmap), size);
	    break;
	case ARG_GEN_BIG:
	    checkLargeBitmap((StgPtr)ret_fun->payload,
			     GET_FUN_LARGE_BITMAP(fun_info), size);
	    break;
	default:
	    checkSmallBitmap((StgPtr)ret_fun->payload,
			     BITMAP_BITS(stg_arg_bitmaps[fun_info->f.fun_type]),
			     size);
	    break;
	}
	return sizeofW(StgRetFun) + size;
    }

    default:
	barf("checkStackFrame: weird activation record found on stack (%p %d).",c,info->i.type);
    }
}

// check sections of stack between update frames
void 
checkStackChunk( StgPtr sp, StgPtr stack_end )
{
    StgPtr p;

    p = sp;
    while (p < stack_end) {
	p += checkStackFrame( p );
    }
    // ASSERT( p == stack_end ); -- HWL
}

static void
checkPAP (StgClosure *tagged_fun, StgClosure** payload, StgWord n_args)
{ 
    StgClosure *fun;
    StgClosure *p;
    StgFunInfoTable *fun_info;
    
    fun = UNTAG_CLOSURE(tagged_fun);
    ASSERT(LOOKS_LIKE_CLOSURE_PTR(fun));
    fun_info = get_fun_itbl(fun);
    
    p = (StgClosure *)payload;
    switch (fun_info->f.fun_type) {
    case ARG_GEN:
	checkSmallBitmap( (StgPtr)payload, 
			  BITMAP_BITS(fun_info->f.b.bitmap), n_args );
	break;
    case ARG_GEN_BIG:
	checkLargeBitmap( (StgPtr)payload, 
			  GET_FUN_LARGE_BITMAP(fun_info), 
			  n_args );
	break;
    case ARG_BCO:
	checkLargeBitmap( (StgPtr)payload, 
			  BCO_BITMAP(fun), 
			  n_args );
	break;
    default:
	checkSmallBitmap( (StgPtr)payload, 
			  BITMAP_BITS(stg_arg_bitmaps[fun_info->f.fun_type]),
			  n_args );
	break;
    }

    ASSERT(fun_info->f.arity > TAG_MASK ? GET_CLOSURE_TAG(tagged_fun) == 0
           : GET_CLOSURE_TAG(tagged_fun) == fun_info->f.arity);
}


StgOffset 
checkClosure( StgClosure* p )
{
    const StgInfoTable *info;

    ASSERT(LOOKS_LIKE_CLOSURE_PTR(p));

    p = UNTAG_CLOSURE(p);
    /* Is it a static closure (i.e. in the data segment)? */
    if (!HEAP_ALLOCED(p)) {
	ASSERT(closure_STATIC(p));
    } else {
	ASSERT(!closure_STATIC(p));
    }

    info = p->header.info;

    if (IS_FORWARDING_PTR(info)) {
        barf("checkClosure: found EVACUATED closure %d", info->type);
    }
    info = INFO_PTR_TO_STRUCT(info);

    switch (info->type) {

    case MVAR_CLEAN:
    case MVAR_DIRTY:
      { 
	StgMVar *mvar = (StgMVar *)p;
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(mvar->head));
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(mvar->tail));
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(mvar->value));
	return sizeofW(StgMVar);
      }

    case THUNK:
    case THUNK_1_0:
    case THUNK_0_1:
    case THUNK_1_1:
    case THUNK_0_2:
    case THUNK_2_0:
      {
	nat i;
	for (i = 0; i < info->layout.payload.ptrs; i++) {
	  ASSERT(LOOKS_LIKE_CLOSURE_PTR(((StgThunk *)p)->payload[i]));
	}
	return thunk_sizeW_fromITBL(info);
      }

    case FUN:
    case FUN_1_0:
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
    case IND_PERM:
    case BLACKHOLE:
    case PRIM:
    case MUT_PRIM:
    case MUT_VAR_CLEAN:
    case MUT_VAR_DIRTY:
    case CONSTR_STATIC:
    case CONSTR_NOCAF_STATIC:
    case THUNK_STATIC:
    case FUN_STATIC:
	{
	    nat i;
	    for (i = 0; i < info->layout.payload.ptrs; i++) {
		ASSERT(LOOKS_LIKE_CLOSURE_PTR(p->payload[i]));
	    }
	    return sizeW_fromITBL(info);
	}

    case BLOCKING_QUEUE:
    {
        StgBlockingQueue *bq = (StgBlockingQueue *)p;

        // NO: the BH might have been updated now
        // ASSERT(get_itbl(bq->bh)->type == BLACKHOLE);
        ASSERT(LOOKS_LIKE_CLOSURE_PTR(bq->bh));

        ASSERT(get_itbl(bq->owner)->type == TSO);
        ASSERT(bq->queue == (MessageBlackHole*)END_TSO_QUEUE 
               || get_itbl(bq->queue)->type == TSO);
        ASSERT(bq->link == (StgBlockingQueue*)END_TSO_QUEUE || 
               get_itbl(bq->link)->type == IND ||
               get_itbl(bq->link)->type == BLOCKING_QUEUE);

        return sizeofW(StgBlockingQueue);
    }

    case BCO: {
	StgBCO *bco = (StgBCO *)p;
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(bco->instrs));
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(bco->literals));
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(bco->ptrs));
	return bco_sizeW(bco);
    }

    case IND_STATIC: /* (1, 0) closure */
      ASSERT(LOOKS_LIKE_CLOSURE_PTR(((StgIndStatic*)p)->indirectee));
      return sizeW_fromITBL(info);

    case WEAK:
      /* deal with these specially - the info table isn't
       * representative of the actual layout.
       */
      { StgWeak *w = (StgWeak *)p;
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(w->key));
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(w->value));
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(w->finalizer));
	if (w->link) {
	  ASSERT(LOOKS_LIKE_CLOSURE_PTR(w->link));
	}
	return sizeW_fromITBL(info);
      }

    case THUNK_SELECTOR:
	    ASSERT(LOOKS_LIKE_CLOSURE_PTR(((StgSelector *)p)->selectee));
	    return THUNK_SELECTOR_sizeW();

    case IND:
	{ 
  	    /* we don't expect to see any of these after GC
	     * but they might appear during execution
	     */
	    StgInd *ind = (StgInd *)p;
	    ASSERT(LOOKS_LIKE_CLOSURE_PTR(ind->indirectee));
	    return sizeofW(StgInd);
	}

    case RET_BCO:
    case RET_SMALL:
    case RET_BIG:
    case RET_DYN:
    case UPDATE_FRAME:
    case STOP_FRAME:
    case CATCH_FRAME:
    case ATOMICALLY_FRAME:
    case CATCH_RETRY_FRAME:
    case CATCH_STM_FRAME:
	    barf("checkClosure: stack frame");

    case AP:
    {
	StgAP* ap = (StgAP *)p;
	checkPAP (ap->fun, ap->payload, ap->n_args);
	return ap_sizeW(ap);
    }

    case PAP:
    {
	StgPAP* pap = (StgPAP *)p;
	checkPAP (pap->fun, pap->payload, pap->n_args);
	return pap_sizeW(pap);
    }

    case AP_STACK:
    { 
	StgAP_STACK *ap = (StgAP_STACK *)p;
	ASSERT(LOOKS_LIKE_CLOSURE_PTR(ap->fun));
	checkStackChunk((StgPtr)ap->payload, (StgPtr)ap->payload + ap->size);
	return ap_stack_sizeW(ap);
    }

    case ARR_WORDS:
	    return arr_words_sizeW((StgArrWords *)p);

    case MUT_ARR_PTRS_CLEAN:
    case MUT_ARR_PTRS_DIRTY:
    case MUT_ARR_PTRS_FROZEN:
    case MUT_ARR_PTRS_FROZEN0:
	{
	    StgMutArrPtrs* a = (StgMutArrPtrs *)p;
	    nat i;
	    for (i = 0; i < a->ptrs; i++) {
		ASSERT(LOOKS_LIKE_CLOSURE_PTR(a->payload[i]));
	    }
	    return mut_arr_ptrs_sizeW(a);
	}

    case TSO:
        checkTSO((StgTSO *)p);
        return tso_sizeW((StgTSO *)p);

    case TREC_CHUNK:
      {
        nat i;
        StgTRecChunk *tc = (StgTRecChunk *)p;
        ASSERT(LOOKS_LIKE_CLOSURE_PTR(tc->prev_chunk));
        for (i = 0; i < tc -> next_entry_idx; i ++) {
          ASSERT(LOOKS_LIKE_CLOSURE_PTR(tc->entries[i].tvar));
          ASSERT(LOOKS_LIKE_CLOSURE_PTR(tc->entries[i].expected_value));
          ASSERT(LOOKS_LIKE_CLOSURE_PTR(tc->entries[i].new_value));
        }
        return sizeofW(StgTRecChunk);
      }
      
    default:
	    barf("checkClosure (closure type %d)", info->type);
    }
}


/* -----------------------------------------------------------------------------
   Check Heap Sanity

   After garbage collection, the live heap is in a state where we can
   run through and check that all the pointers point to the right
   place.  This function starts at a given position and sanity-checks
   all the objects in the remainder of the chain.
   -------------------------------------------------------------------------- */

void 
checkHeap(bdescr *bd)
{
    StgPtr p;

#if defined(THREADED_RTS)
    // heap sanity checking doesn't work with SMP, because we can't
    // zero the slop (see Updates.h).
    return;
#endif

    for (; bd != NULL; bd = bd->link) {
        if(!(bd->flags & BF_SWEPT)) {
            p = bd->start;
            while (p < bd->free) {
                nat size = checkClosure((StgClosure *)p);
                /* This is the smallest size of closure that can live in the heap */
                ASSERT( size >= MIN_PAYLOAD_SIZE + sizeofW(StgHeader) );
                p += size;
	    
                /* skip over slop */
                while (p < bd->free &&
                       (*p < 0x1000 || !LOOKS_LIKE_INFO_PTR(*p))) { p++; }
            }
	}
    }
}

void 
checkHeapChunk(StgPtr start, StgPtr end)
{
  StgPtr p;
  nat size;

  for (p=start; p<end; p+=size) {
    ASSERT(LOOKS_LIKE_INFO_PTR(*p));
    size = checkClosure((StgClosure *)p);
    /* This is the smallest size of closure that can live in the heap. */
    ASSERT( size >= MIN_PAYLOAD_SIZE + sizeofW(StgHeader) );
  }
}

void
checkLargeObjects(bdescr *bd)
{
  while (bd != NULL) {
    if (!(bd->flags & BF_PINNED)) {
      checkClosure((StgClosure *)bd->start);
    }
    bd = bd->link;
  }
}

void
checkTSO(StgTSO *tso)
{
    StgPtr sp = tso->sp;
    StgPtr stack = tso->stack;
    StgOffset stack_size = tso->stack_size;
    StgPtr stack_end = stack + stack_size;

    if (tso->what_next == ThreadRelocated) {
      checkTSO(tso->_link);
      return;
    }

    if (tso->what_next == ThreadKilled) {
      /* The garbage collector doesn't bother following any pointers
       * from dead threads, so don't check sanity here.  
       */
      return;
    }

    ASSERT(tso->_link == END_TSO_QUEUE || 
           tso->_link->header.info == &stg_MVAR_TSO_QUEUE_info ||
           tso->_link->header.info == &stg_TSO_info);
    ASSERT(LOOKS_LIKE_CLOSURE_PTR(tso->block_info.closure));
    ASSERT(LOOKS_LIKE_CLOSURE_PTR(tso->bq));
    ASSERT(LOOKS_LIKE_CLOSURE_PTR(tso->blocked_exceptions));

    ASSERT(stack <= sp && sp < stack_end);

    checkStackChunk(sp, stack_end);
}

/* 
   Check that all TSOs have been evacuated.
   Optionally also check the sanity of the TSOs.
*/
void
checkGlobalTSOList (rtsBool checkTSOs)
{
  StgTSO *tso;
  nat g;

  for (g = 0; g < RtsFlags.GcFlags.generations; g++) {
      for (tso=generations[g].threads; tso != END_TSO_QUEUE; 
           tso = tso->global_link) {
          ASSERT(LOOKS_LIKE_CLOSURE_PTR(tso));
          ASSERT(get_itbl(tso)->type == TSO);
          if (checkTSOs)
              checkTSO(tso);

          tso = deRefTSO(tso);

          // If this TSO is dirty and in an old generation, it better
          // be on the mutable list.
          if (tso->dirty || (tso->flags & TSO_LINK_DIRTY)) {
              ASSERT(Bdescr((P_)tso)->gen_no == 0 || (tso->flags & TSO_MARKED));
              tso->flags &= ~TSO_MARKED;
          }
      }
  }
}

/* -----------------------------------------------------------------------------
   Check mutable list sanity.
   -------------------------------------------------------------------------- */

void
checkMutableList( bdescr *mut_bd, nat gen )
{
    bdescr *bd;
    StgPtr q;
    StgClosure *p;

    for (bd = mut_bd; bd != NULL; bd = bd->link) {
	for (q = bd->start; q < bd->free; q++) {
	    p = (StgClosure *)*q;
	    ASSERT(!HEAP_ALLOCED(p) || Bdescr((P_)p)->gen_no == gen);
            if (get_itbl(p)->type == TSO) {
                ((StgTSO *)p)->flags |= TSO_MARKED;
            }
	}
    }
}

void
checkMutableLists (rtsBool checkTSOs)
{
    nat g, i;

    for (g = 0; g < RtsFlags.GcFlags.generations; g++) {
        checkMutableList(generations[g].mut_list, g);
        for (i = 0; i < n_capabilities; i++) {
            checkMutableList(capabilities[i].mut_lists[g], g);
        }
    }
    checkGlobalTSOList(checkTSOs);
}

/*
  Check the static objects list.
*/
void
checkStaticObjects ( StgClosure* static_objects )
{
  StgClosure *p = static_objects;
  StgInfoTable *info;

  while (p != END_OF_STATIC_LIST) {
    checkClosure(p);
    info = get_itbl(p);
    switch (info->type) {
    case IND_STATIC:
      { 
        StgClosure *indirectee = UNTAG_CLOSURE(((StgIndStatic *)p)->indirectee);

	ASSERT(LOOKS_LIKE_CLOSURE_PTR(indirectee));
	ASSERT(LOOKS_LIKE_INFO_PTR((StgWord)indirectee->header.info));
	p = *IND_STATIC_LINK((StgClosure *)p);
	break;
      }

    case THUNK_STATIC:
      p = *THUNK_STATIC_LINK((StgClosure *)p);
      break;

    case FUN_STATIC:
      p = *FUN_STATIC_LINK((StgClosure *)p);
      break;

    case CONSTR_STATIC:
      p = *STATIC_LINK(info,(StgClosure *)p);
      break;

    default:
      barf("checkStaticObjetcs: strange closure %p (%s)", 
	   p, info_type(p));
    }
  }
}

/* Nursery sanity check */
void
checkNurserySanity (nursery *nursery)
{
    bdescr *bd, *prev;
    nat blocks = 0;

    prev = NULL;
    for (bd = nursery->blocks; bd != NULL; bd = bd->link) {
	ASSERT(bd->u.back == prev);
	prev = bd;
	blocks += bd->blocks;
    }

    ASSERT(blocks == nursery->n_blocks);
}


/* Full heap sanity check. */
void
checkSanity( rtsBool check_heap )
{
    nat g, n;

    for (g = 0; g < RtsFlags.GcFlags.generations; g++) {
        ASSERT(countBlocks(generations[g].blocks)
               == generations[g].n_blocks);
        ASSERT(countBlocks(generations[g].large_objects)
                   == generations[g].n_large_blocks);
        if (check_heap) {
            checkHeap(generations[g].blocks);
        }
        checkLargeObjects(generations[g].large_objects);
    }
    
    for (n = 0; n < n_capabilities; n++) {
        checkNurserySanity(&nurseries[n]);
    }
    
    checkFreeListSanity();

#if defined(THREADED_RTS)
    // always check the stacks in threaded mode, because checkHeap()
    // does nothing in this case.
    checkMutableLists(rtsTrue);
#else
    if (check_heap) {
        checkMutableLists(rtsFalse);
    } else {
        checkMutableLists(rtsTrue);
    }
#endif
}

// If memInventory() calculates that we have a memory leak, this
// function will try to find the block(s) that are leaking by marking
// all the ones that we know about, and search through memory to find
// blocks that are not marked.  In the debugger this can help to give
// us a clue about what kind of block leaked.  In the future we might
// annotate blocks with their allocation site to give more helpful
// info.
static void
findMemoryLeak (void)
{
  nat g, i;
  for (g = 0; g < RtsFlags.GcFlags.generations; g++) {
      for (i = 0; i < n_capabilities; i++) {
	  markBlocks(capabilities[i].mut_lists[g]);
      }
      markBlocks(generations[g].mut_list);
      markBlocks(generations[g].blocks);
      markBlocks(generations[g].large_objects);
  }

  for (i = 0; i < n_capabilities; i++) {
      markBlocks(nurseries[i].blocks);
  }

#ifdef PROFILING
  // TODO:
  // if (RtsFlags.ProfFlags.doHeapProfile == HEAP_BY_RETAINER) {
  //    markRetainerBlocks();
  // }
#endif

  // count the blocks allocated by the arena allocator
  // TODO:
  // markArenaBlocks();

  // count the blocks containing executable memory
  markBlocks(exec_block);

  reportUnmarkedBlocks();
}

void
checkRunQueue(Capability *cap)
{
    StgTSO *prev, *tso;
    prev = END_TSO_QUEUE;
    for (tso = cap->run_queue_hd; tso != END_TSO_QUEUE; 
         prev = tso, tso = tso->_link) {
        ASSERT(prev == END_TSO_QUEUE || prev->_link == tso);
        ASSERT(tso->block_info.prev == prev);
    }
    ASSERT(cap->run_queue_tl == prev);
}

/* -----------------------------------------------------------------------------
   Memory leak detection

   memInventory() checks for memory leaks by counting up all the
   blocks we know about and comparing that to the number of blocks
   allegedly floating around in the system.
   -------------------------------------------------------------------------- */

// Useful for finding partially full blocks in gdb
void findSlop(bdescr *bd);
void findSlop(bdescr *bd)
{
    lnat slop;

    for (; bd != NULL; bd = bd->link) {
        slop = (bd->blocks * BLOCK_SIZE_W) - (bd->free - bd->start);
        if (slop > (1024/sizeof(W_))) {
            debugBelch("block at %p (bdescr %p) has %ldKB slop\n",
                       bd->start, bd, slop / (1024/sizeof(W_)));
        }
    }
}

static lnat
genBlocks (generation *gen)
{
    ASSERT(countBlocks(gen->blocks) == gen->n_blocks);
    ASSERT(countBlocks(gen->large_objects) == gen->n_large_blocks);
    return gen->n_blocks + gen->n_old_blocks + 
	    countAllocdBlocks(gen->large_objects);
}

void
memInventory (rtsBool show)
{
  nat g, i;
  lnat gen_blocks[RtsFlags.GcFlags.generations];
  lnat nursery_blocks, retainer_blocks,
       arena_blocks, exec_blocks;
  lnat live_blocks = 0, free_blocks = 0;
  rtsBool leak;

  // count the blocks we current have

  for (g = 0; g < RtsFlags.GcFlags.generations; g++) {
      gen_blocks[g] = 0;
      for (i = 0; i < n_capabilities; i++) {
	  gen_blocks[g] += countBlocks(capabilities[i].mut_lists[g]);
      }	  
      gen_blocks[g] += countAllocdBlocks(generations[g].mut_list);
      gen_blocks[g] += genBlocks(&generations[g]);
  }

  nursery_blocks = 0;
  for (i = 0; i < n_capabilities; i++) {
      ASSERT(countBlocks(nurseries[i].blocks) == nurseries[i].n_blocks);
      nursery_blocks += nurseries[i].n_blocks;
  }

  retainer_blocks = 0;
#ifdef PROFILING
  if (RtsFlags.ProfFlags.doHeapProfile == HEAP_BY_RETAINER) {
      retainer_blocks = retainerStackBlocks();
  }
#endif

  // count the blocks allocated by the arena allocator
  arena_blocks = arenaBlocks();

  // count the blocks containing executable memory
  exec_blocks = countAllocdBlocks(exec_block);

  /* count the blocks on the free list */
  free_blocks = countFreeList();

  live_blocks = 0;
  for (g = 0; g < RtsFlags.GcFlags.generations; g++) {
      live_blocks += gen_blocks[g];
  }
  live_blocks += nursery_blocks + 
               + retainer_blocks + arena_blocks + exec_blocks;

#define MB(n) (((n) * BLOCK_SIZE_W) / ((1024*1024)/sizeof(W_)))

  leak = live_blocks + free_blocks != mblocks_allocated * BLOCKS_PER_MBLOCK;

  if (show || leak)
  {
      if (leak) { 
          debugBelch("Memory leak detected:\n");
      } else {
          debugBelch("Memory inventory:\n");
      }
      for (g = 0; g < RtsFlags.GcFlags.generations; g++) {
	  debugBelch("  gen %d blocks : %5lu blocks (%lu MB)\n", g, 
                     gen_blocks[g], MB(gen_blocks[g]));
      }
      debugBelch("  nursery      : %5lu blocks (%lu MB)\n", 
                 nursery_blocks, MB(nursery_blocks));
      debugBelch("  retainer     : %5lu blocks (%lu MB)\n", 
                 retainer_blocks, MB(retainer_blocks));
      debugBelch("  arena blocks : %5lu blocks (%lu MB)\n", 
                 arena_blocks, MB(arena_blocks));
      debugBelch("  exec         : %5lu blocks (%lu MB)\n", 
                 exec_blocks, MB(exec_blocks));
      debugBelch("  free         : %5lu blocks (%lu MB)\n", 
                 free_blocks, MB(free_blocks));
      debugBelch("  total        : %5lu blocks (%lu MB)\n",
                 live_blocks + free_blocks, MB(live_blocks+free_blocks));
      if (leak) {
          debugBelch("\n  in system    : %5lu blocks (%lu MB)\n", 
                     mblocks_allocated * BLOCKS_PER_MBLOCK, mblocks_allocated);
      }
  }

  if (leak) {
      debugBelch("\n");
      findMemoryLeak();
  }
  ASSERT(n_alloc_blocks == live_blocks);
  ASSERT(!leak);
}


#endif /* DEBUG */
