libraries/containers_PACKAGE = containers
libraries/containers_dist-install_GROUP = libraries
$(if $(filter containers,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/containers,dist-boot,0)))
$(eval $(call build-package,libraries/containers,dist-install,$(if $(filter containers,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
