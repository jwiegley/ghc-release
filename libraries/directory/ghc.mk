libraries/directory_PACKAGE = directory
libraries/directory_dist-install_GROUP = libraries
$(if $(filter directory,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/directory,dist-boot,0)))
$(eval $(call build-package,libraries/directory,dist-install,$(if $(filter directory,$(STAGE2_PACKAGES)),2,1)))
