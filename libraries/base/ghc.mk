libraries/base_PACKAGE = base
libraries/base_dist-install_GROUP = libraries
$(if $(filter base,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/base,dist-boot,0)))
$(eval $(call build-package,libraries/base,dist-install,$(if $(filter base,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
