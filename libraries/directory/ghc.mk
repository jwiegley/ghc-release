libraries/directory_PACKAGE = directory
libraries/directory_dist-install_GROUP = libraries
$(if $(filter directory,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/directory,dist-boot,0)))
$(eval $(call build-package,libraries/directory,dist-install,$(if $(filter directory,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
