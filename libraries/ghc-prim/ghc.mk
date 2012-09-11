libraries/ghc-prim_PACKAGE = ghc-prim
libraries/ghc-prim_dist-install_GROUP = libraries
$(if $(filter ghc-prim,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/ghc-prim,dist-boot,0)))
$(eval $(call build-package,libraries/ghc-prim,dist-install,$(if $(filter ghc-prim,$(STAGE2_PACKAGES)),2,1)))
