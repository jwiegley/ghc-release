libraries/binary_PACKAGE = binary
libraries/binary_dist-install_GROUP = libraries
$(if $(filter binary,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/binary,dist-boot,0)))
$(eval $(call build-package,libraries/binary,dist-install,$(if $(filter binary,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
