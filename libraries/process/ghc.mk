libraries/process_PACKAGE = process
libraries/process_dist-install_GROUP = libraries
$(if $(filter process,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/process,dist-boot,0)))
$(eval $(call build-package,libraries/process,dist-install,$(if $(filter process,$(STAGE2_PACKAGES)),2,1)))
