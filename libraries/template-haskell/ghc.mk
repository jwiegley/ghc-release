libraries/template-haskell_PACKAGE = template-haskell
libraries/template-haskell_dist-install_GROUP = libraries
$(if $(filter template-haskell,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/template-haskell,dist-boot,0)))
$(eval $(call build-package,libraries/template-haskell,dist-install,$(if $(filter template-haskell,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
