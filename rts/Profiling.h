/* -----------------------------------------------------------------------------
 *
 * (c) The GHC Team, 1998-2005
 *
 * Support for profiling
 *
 * ---------------------------------------------------------------------------*/

#ifndef PROFILING_H
#define PROFILING_H

#include <stdio.h>

#include "BeginPrivate.h"

void initProfiling1 (void);
void freeProfiling1 (void);
void initProfiling2 (void);
void endProfiling   (void);

extern FILE *prof_file;
extern FILE *hp_file;

#ifdef PROFILING

void gen_XML_logfile    ( void );
void reportCCSProfiling ( void );

void PrintNewStackDecls ( void );

void fprintCCS( FILE *f, CostCentreStack *ccs );
void fprintCCS_stderr( CostCentreStack *ccs );

#ifdef DEBUG
void debugCCS( CostCentreStack *ccs );
#endif

#endif

#include "EndPrivate.h"

#endif /* PROFILING_H */
