libraries/Cabal/cabal_PACKAGE = Cabal
libraries/Cabal/cabal_dist-install_GROUP = libraries
$(if $(filter Cabal/cabal,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/Cabal/cabal,dist-boot,0)))
$(eval $(call build-package,libraries/Cabal/cabal,dist-install,$(if $(filter Cabal/cabal,$(STAGE2_PACKAGES)),2,1)))
