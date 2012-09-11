
TOP=../..
ENABLE_SHELL_WRAPPERS = YES
BINDIST_EXTRAS += template-hsc.h

include $(TOP)/mk/boilerplate.mk
include $(TOP)/mk/cabal.mk

ifeq "$(ghc_ge_607)" "YES"
# XXX This is a hack to fix the build on Windows
SRC_HC_OPTS += -Wwarn
endif
