libraries/Cabal/Cabal_PACKAGE = Cabal
libraries/Cabal/Cabal_dist-install_GROUP = libraries
$(if $(filter Cabal/Cabal,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/Cabal/Cabal,dist-boot,0)))
$(eval $(call build-package,libraries/Cabal/Cabal,dist-install,$(if $(filter Cabal/Cabal,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
