libraries/directory_PACKAGE = directory
libraries/directory_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/directory,dist-install,$(if $(filter directory,$(STAGE2_PACKAGES)),2,1)))
