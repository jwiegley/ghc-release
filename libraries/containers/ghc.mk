libraries/containers_PACKAGE = containers
libraries/containers_dist-install_GROUP = libraries
$(if $(filter containers,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/containers,dist-boot,0)))
$(eval $(call build-package,libraries/containers,dist-install,$(if $(filter containers,$(STAGE2_PACKAGES)),2,1)))
