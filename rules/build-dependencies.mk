# -----------------------------------------------------------------------------
#
# (c) 2009 The University of Glasgow
#
# This file is part of the GHC build system.
#
# To understand how the build system works and how to modify it, see
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Architecture
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Modifying
#
# -----------------------------------------------------------------------------


define build-dependencies # args: $1 = dir, $2 = distdir

ifeq "$$($1_$2_ghc_ge_609)" "YES"
$1_$2_MKDEPENDHS_FLAGS = -include-pkg-deps -dep-makefile $$($1_$2_depfile) $$(foreach way,$$(filter-out v,$$($1_$2_WAYS)),-dep-suffix $$(way))
else
$1_$2_MKDEPENDHS_FLAGS = -optdep--include-pkg-deps -optdep-f -optdep$$($1_$2_depfile) $$(foreach way,$$(filter-out v,$$($1_$2_WAYS)),-optdep-s -optdep$$(way))
endif

ifneq "$$($1_$2_NO_BUILD_DEPS)" "YES"

$$($1_$2_depfile) : $$(MKDIRHIER) $$(MKDEPENDC) $$($1_$2_HS_SRCS) $$($1_$2_HS_BOOT_SRCS) $$($1_$2_HC_MK_DEPEND_DEP) $$($1_$2_C_FILES) $$($1_$2_S_FILES)
	"$$(MKDIRHIER)" $1/$2/build
	"$$(RM)" $$(RM_OPTS) $$@.tmp
	touch $$@.tmp
ifneq "$$($1_$2_C_SRCS)$$($1_$2_S_SRCS)" ""
	"$$(MKDEPENDC)" -f $$($1_$2_depfile).tmp $$($1_MKDEPENDC_OPTS) $$(foreach way,$$($1_WAYS),-s $$(way)) -- $$($1_$2_v_ALL_CC_OPTS) -- $$($1_$2_C_FILES) $$($1_$2_S_FILES)
	sed -e "s|$1/\([^ :]*o[ :]\)|$1/$2/build/\1|g" -e "s|$$(TOP)/||g$(CASE_INSENSITIVE_SED)" -e "s|$2/build/$2/build|$2/build|g" <$$($1_$2_depfile).tmp >$$($1_$2_depfile)
endif
ifneq "$$($1_$2_HS_SRCS)" ""
	"$$($1_$2_HC_MK_DEPEND)" -M $$($1_$2_MKDEPENDHS_FLAGS) \
	    $$(filter-out -split-objs, $$($1_$2_v_ALL_HC_OPTS)) \
	    $$($1_$2_HS_SRCS)
endif
	echo "$1_$2_depfile_EXISTS = YES" >> $$@
ifneq "$$($1_$2_SLASH_MODS)" ""
	for dir in $$(sort $$(foreach mod,$$($1_$2_SLASH_MODS),$1/$2/build/$$(dir $$(mod)))); do \
		if test ! -d $$$$dir; then mkdir -p $$$$dir; fi \
	done
endif

endif # $1_$2_NO_BUILD_DEPS

# Note sed magic above: mkdependC can't do -odir stuff, so we have to
# munge the dependencies it generates to refer to the correct targets.

# Seems as good a place as any to attach the unlit dependency
$$($1_$2_depfile) : $$(UNLIT)

ifneq "$$(NO_INCLUDE_DEPS)" "YES"
include $$($1_$2_depfile)
else
ifeq "$$(DEBUG)" "YES"
$$(warning not building dependencies in $1)
endif
endif

endef

# Case insensitivity is only needed on Windows, and s///i isn't
# portable, so we only define it on Windows (where it is available,
# as we use the GNU tools):
ifeq "$(Windows)" "YES"
CASE_INSENSITIVE_SED = i
else
CASE_INSENSITIVE_SED =
endif

