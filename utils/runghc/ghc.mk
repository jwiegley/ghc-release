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

utils/runghc_dist_MODULES = Main
utils/runghc_dist_HC_OPTS = -cpp -DVERSION="\"$(ProjectVersion)\""
utils/runghc_dist_PROG    = runghc$(exeext)
utils/runghc_dist_SHELL_WRAPPER = YES
utils/runghc_dist_INSTALL_SHELL_WRAPPER = YES

ifneq "$(BINDIST)" "YES"
# hack: the build system has trouble with Main modules not called Main.hs
utils/runghc/dist/build/Main.hs : utils/runghc/runghc.hs $(MKDIRHIER)
	"$(MKDIRHIER)" $(dir $@)
	"$(CP)" $< $@
endif

$(eval $(call build-prog,utils/runghc,dist,1))

install: install_runhaskell

.PHONY: install_runhaskell
ifeq "$(Windows)" "YES"
install_runhaskell: install_bins
	"$(CP)" $(DESTDIR)$(bindir)/runghc$(exeext) $(DESTDIR)$(bindir)/runhaskell$(exeext)
else
install_runhaskell:
	"$(RM)" $(RM_OPTS) "$(DESTDIR)$(bindir)/runhaskell"
	$(LN_S) runghc "$(DESTDIR)$(bindir)/runhaskell"
endif

