libraries/old-time_PACKAGE = old-time
libraries/old-time_dist-install_GROUP = libraries
$(if $(filter old-time,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/old-time,dist-boot,0)))
$(eval $(call build-package,libraries/old-time,dist-install,$(if $(filter old-time,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
