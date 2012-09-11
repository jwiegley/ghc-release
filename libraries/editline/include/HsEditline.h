#ifndef HSEDITLINE_H
#define HSEDITLINE_H

#include "HsEditlineConfig.h"

#include <stdio.h>
#include <histedit.h>

extern EditLine *el_init_from_term(const char *prog);

/* explicit instances of el_set,el_get functions */
extern int el_set_prompt(EditLine *e,char *(*f)(EditLine *));

extern int el_set_editor(EditLine *e, const char *mode);

extern int el_get_one_arg(EditLine *e, int op, void *result);

#endif
