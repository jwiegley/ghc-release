AC_INIT([Haskell editline package], [1.0], [libraries@haskell.org], [editline])

AC_CONFIG_HEADERS([include/HsEditlineConfig.h])

FP_ARG_EDITLINE

EDITLINE_INCLUDE_DIRS=
EDITLINE_LIB_DIRS=
if test "x$editline_libraries" != "xNONE"; then
  LDFLAGS="-L$editline_libraries $LDFLAGS"
  EDITLINE_LDFLAGS="-L$editline_libraries $EDITLINE_LDFLAGS"
  EDITLINE_LIB_DIRS=$editline_libraries
fi
if test "x$editline_includes" != "xNONE"; then
  CPPFLAGS="-I$editline_includes $CPPFLAGS"
  EDITLINE_CFLAGS="-I$editline_includes $EDITLINE_CFLAGS"
  EDITLINE_INCLUDE_DIRS=$editline_includes
fi
AC_SUBST(EDITLINE_INCLUDE_DIRS)
AC_SUBST(EDITLINE_LIB_DIRS)

AC_ARG_WITH([cc],
            [C compiler],
            [CC=$withval])
AC_PROG_CC()

dnl ncurses supersedes termcap and curses, but for compatibility,
dnl we have to check for all...
AC_CHECK_LIB(ncurses, tputs, HaveLibTermcap=YES; LibTermcap=ncurses,
  AC_CHECK_LIB(termcap, tputs, HaveLibTermcap=YES; LibTermcap=termcap,
    AC_CHECK_LIB(curses, tputs, HaveLibTermcap=YES; LibTermcap=curses,
      HaveLibTermcap=NO; LibTermcap=not-installed)))

if test "x$HaveLibTermcap" = xYES ; then
  HaveLibEdit=YES
  LIBS="$LIBS -l$LibTermcap -ledit"
  AC_CHECK_FUNC(el_init, , HaveLibEdit=NO)
  AC_CHECK_FUNC(readline, , HaveLibEdit=NO)
  EDITLINE_LIBS="edit $LibTermcap"
else
  HaveLibEdit=NO
fi

dnl Look for the equivalent of <readline/readline.h>
dnl Make sure to check <readline/readline.h> last, so that if both readline and
dnl editline are installed, we'll pick the right one.
AC_CHECK_HEADERS([editline/readline.h editline/editline.h readline/readline.h], [break])

CHECK_HIST_ERRORS

AC_CHECK_FUNCS([rl_completion_matches completion_matches], HaveCompletionMatches=YES)
if test "x$HaveCompletionMatches" != xYES ; then
  HaveLibEdit=NO
fi

if test "x$HaveLibEdit" = xYES ; then
  BUILD_PACKAGE_BOOL=True
else
  BUILD_PACKAGE_BOOL=False
  AC_MSG_FAILURE([editline not found, so this package cannot be built])
fi

AC_SUBST([BUILD_PACKAGE_BOOL])
AC_SUBST([EDITLINE_CFLAGS])
AC_SUBST([EDITLINE_LDFLAGS])
AC_SUBST([EDITLINE_LIBS])

AC_CONFIG_FILES([editline.buildinfo])
AC_OUTPUT
