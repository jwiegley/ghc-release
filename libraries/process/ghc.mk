libraries/process_PACKAGE = process
libraries/process_dist-install_GROUP = libraries
$(if $(filter process,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/process,dist-boot,0)))
$(eval $(call build-package,libraries/process,dist-install,$(if $(filter process,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
