libraries/ghc-prim_PACKAGE = ghc-prim
libraries/ghc-prim_dist-install_GROUP = libraries
$(if $(filter ghc-prim,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/ghc-prim,dist-boot,0)))
$(eval $(call build-package,libraries/ghc-prim,dist-install,$(if $(filter ghc-prim,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
