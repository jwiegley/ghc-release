# FP_ARG_EDITLINE
# -------------
AC_DEFUN([FP_ARG_EDITLINE],
[
AC_ARG_WITH([editline-includes],
  [AC_HELP_STRING([--with-editline-includes],
    [directory containing editline/editline.h])],
    [editline_includes=$withval],
    [editline_includes=NONE])

AC_ARG_WITH([editline-libraries],
  [AC_HELP_STRING([--with-editline-libraries],
    [directory containing editline library])],
    [editline_libraries=$withval],
    [editline_libraries=NONE])
])# FP_ARG_EDITLINE

AC_DEFUN([CHECK_HIST_ERRORS],
[
dnl Older versions of libedit (up to at least 2.6.9) don't handle errors in
dnl functions like read_history the same way that readline does; whereas
dnl readline returns a positive errno on error and zero otherwise, 
dnl editline may return -1 on error and a nonnegative value otherwise.
AC_MSG_CHECKING(for sign of read_history result on error)
AC_RUN_IFELSE(
  [AC_LANG_SOURCE([[
#include <stdio.h>
extern void rl_initialize();
extern int read_history(const char*histfile);

int main(void) {
    int ret;
    rl_initialize();
    ret = read_history("this/should/not/be/valid");
    return (ret < 0);
}
]])],
  [error_is_negative=NO],
  [error_is_negative=YES]
)

if test "x$error_is_negative" = "xYES"; then
    AC_DEFINE([NEGATIVE_HIST_ERROR],[1],
                [Define if read_history returns a positive value on error])
    AC_MSG_RESULT(negative)
else
    AC_MSG_RESULT(positive)
fi



])# CHECK_HIST_ERRORS
