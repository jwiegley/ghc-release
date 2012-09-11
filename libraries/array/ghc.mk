libraries/array_PACKAGE = array
libraries/array_dist-install_GROUP = libraries
$(if $(filter array,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/array,dist-boot,0)))
$(eval $(call build-package,libraries/array,dist-install,$(if $(filter array,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
