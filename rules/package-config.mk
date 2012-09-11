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


define package-config # args: $1 = dir, $2 = distdir, $3 = GHC stage

$1_$2_HC = $$(GHC_STAGE$3)

# configuration stuff that depends on which GHC we're building with
ifeq "$3" "0"
$1_$2_ghc_ge_609 = $$(ghc_ge_609)
$1_$2_HC_CONFIG = $$(GHC_STAGE0)
$1_$2_HC_CONFIG_DEP =
$1_$2_GHC_PKG = $$(GHC_PKG)
$1_$2_GHC_PKG_DEP = 
$1_$2_HC_MK_DEPEND = $$($1_$2_HC)
# We can't make rules depend on the bootstrapping compiler, as then
# on cygwin we get a dep on c:/ghc/..., and make gets confused by the :
$1_$2_HC_MK_DEPEND_DEP =
$1_$2_HC_DEP =
$1_$2_HC_PKGCONF = -package-conf $$(BOOTSTRAPPING_CONF)
$1_$2_GHC_PKG_OPTS = --package-conf=$$(BOOTSTRAPPING_CONF)
$1_$2_CONFIGURE_OPTS += --package-db=$$(TOP)/$$(BOOTSTRAPPING_CONF)
else
$1_$2_ghc_ge_609 = YES
$1_$2_HC_PKGCONF = 
$1_$2_HC_CONFIG = $$(TOP)/$$(DUMMY_GHC_INPLACE)
$1_$2_HC_CONFIG_DEP = $$(DUMMY_GHC_INPLACE)
$1_$2_GHC_PKG = $$(TOP)/$$(GHC_PKG_INPLACE)
$1_$2_GHC_PKG_DEP = $$(GHC_PKG_INPLACE)
$1_$2_GHC_PKG_OPTS =
# If stage is not 0 then we always use stage1 for making .depend, as later
# stages aren't available early enough
$1_$2_HC_MK_DEPEND = $$(GHC_STAGE1)
$1_$2_HC_MK_DEPEND_DEP = $$($1_$2_HC_MK_DEPEND)
$1_$2_HC_DEP = $$($1_$2_HC)
$1_$2_HC_OPTS += -no-user-package-conf
endif

# Useful later
$1_$2_SLASH_MODS = $$(subst .,/,$$($1_$2_MODULES))

endef
