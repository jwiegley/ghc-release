#include "HsEditline.h"

EditLine *el_init_from_term(const char *prog) {
    return el_init(prog, stdin, stdout, stderr);
}

int el_set_prompt(EditLine *e,char *(*f)(EditLine *)) {
    return el_set(e, EL_PROMPT, f);
}

int el_set_editor(EditLine *e, const char *mode) {
    return el_set(e, EL_EDITOR, mode);
}

int el_get_one_arg(EditLine *e, int op, void *result) {
    return el_get(e, op, result);
}
