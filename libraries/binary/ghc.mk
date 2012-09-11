libraries/binary_PACKAGE = binary
libraries/binary_dist-install_GROUP = libraries
$(if $(filter binary,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/binary,dist-boot,0)))
$(eval $(call build-package,libraries/binary,dist-install,$(if $(filter binary,$(STAGE2_PACKAGES)),2,1)))
