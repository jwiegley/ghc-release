libraries/haskell2010_PACKAGE = haskell2010
libraries/haskell2010_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/haskell2010,dist-install,$(if $(filter haskell2010,$(STAGE2_PACKAGES)),2,1)))
