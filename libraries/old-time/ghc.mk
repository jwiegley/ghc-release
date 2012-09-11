libraries/old-time_PACKAGE = old-time
libraries/old-time_dist-install_GROUP = libraries
$(if $(filter old-time,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/old-time,dist-boot,0)))
$(eval $(call build-package,libraries/old-time,dist-install,$(if $(filter old-time,$(STAGE2_PACKAGES)),2,1)))
