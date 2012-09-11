libraries/containers_PACKAGE = containers
libraries/containers_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/containers,dist-install,$(if $(filter containers,$(STAGE2_PACKAGES)),2,1)))
