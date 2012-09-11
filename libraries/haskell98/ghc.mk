libraries/haskell98_PACKAGE = haskell98
libraries/haskell98_dist-install_GROUP = libraries
$(if $(filter haskell98,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/haskell98,dist-boot,0)))
$(eval $(call build-package,libraries/haskell98,dist-install,$(if $(filter haskell98,$(STAGE2_PACKAGES)),2,1)))
