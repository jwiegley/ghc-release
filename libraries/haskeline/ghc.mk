libraries/haskeline_PACKAGE = haskeline
libraries/haskeline_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/haskeline,dist-install,$(if $(filter haskeline,$(STAGE2_PACKAGES)),2,1)))
