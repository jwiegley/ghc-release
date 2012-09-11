libraries/haskeline_PACKAGE = haskeline
libraries/haskeline_dist-install_GROUP = libraries
$(if $(filter haskeline,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/haskeline,dist-boot,0)))
$(eval $(call build-package,libraries/haskeline,dist-install,$(if $(filter haskeline,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
