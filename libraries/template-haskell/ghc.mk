libraries/template-haskell_PACKAGE = template-haskell
libraries/template-haskell_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/template-haskell,dist-install,$(if $(filter template-haskell,$(STAGE2_PACKAGES)),2,1)))
