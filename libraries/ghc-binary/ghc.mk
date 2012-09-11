libraries/ghc-binary_PACKAGE = ghc-binary
libraries/ghc-binary_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/ghc-binary,dist-install,$(if $(filter ghc-binary,$(STAGE2_PACKAGES)),2,1)))
