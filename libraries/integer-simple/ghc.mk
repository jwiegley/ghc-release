libraries/integer-simple_PACKAGE = integer-simple
libraries/integer-simple_dist-install_GROUP = libraries
$(if $(filter integer-simple,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/integer-simple,dist-boot,0)))
$(eval $(call build-package,libraries/integer-simple,dist-install,$(if $(filter integer-simple,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
