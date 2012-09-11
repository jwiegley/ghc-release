libraries/array_PACKAGE = array
libraries/array_dist-install_GROUP = libraries
$(if $(filter array,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/array,dist-boot,0)))
$(eval $(call build-package,libraries/array,dist-install,$(if $(filter array,$(STAGE2_PACKAGES)),2,1)))
