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

utils/genapply_dist_MODULES = GenApply
utils/genapply_dist_PROG    = $(GHC_GENAPPLY_PGM)

utils/genapply_HC_OPTS += -package pretty

ifeq "$(GhcUnregisterised)" "YES"
utils/genapply_HC_OPTS += -DNO_REGS
endif

utils/genapply/GenApply.hs : $(GHC_INCLUDE_DIR)/ghcconfig.h
utils/genapply/GenApply.hs : $(GHC_INCLUDE_DIR)/MachRegs.h
utils/genapply/GenApply.hs : $(GHC_INCLUDE_DIR)/Constants.h

$(eval $(call build-prog,utils/genapply,dist,0))
