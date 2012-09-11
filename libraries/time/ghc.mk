libraries/time_PACKAGE = time
libraries/time_dist-install_GROUP = libraries
$(if $(filter time,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/time,dist-boot,0)))
$(eval $(call build-package,libraries/time,dist-install,$(if $(filter time,$(STAGE2_PACKAGES)),2,1)))
