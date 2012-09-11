libraries/array_PACKAGE = array
libraries/array_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/array,dist-install,$(if $(filter array,$(STAGE2_PACKAGES)),2,1)))
