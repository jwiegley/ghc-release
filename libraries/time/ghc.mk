libraries/time_PACKAGE = time
libraries/time_dist-install_GROUP = libraries
$(if $(filter time,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/time,dist-boot,0)))
$(eval $(call build-package,libraries/time,dist-install,$(if $(filter time,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
