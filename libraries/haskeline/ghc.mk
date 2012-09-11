libraries/haskeline_PACKAGE = haskeline
libraries/haskeline_dist-install_GROUP = libraries
$(if $(filter haskeline,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/haskeline,dist-boot,0)))
$(eval $(call build-package,libraries/haskeline,dist-install,$(if $(filter haskeline,$(STAGE2_PACKAGES)),2,1)))
