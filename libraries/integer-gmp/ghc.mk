libraries/integer-gmp_PACKAGE = integer-gmp
libraries/integer-gmp_dist-install_GROUP = libraries
$(if $(filter integer-gmp,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/integer-gmp,dist-boot,0)))
$(eval $(call build-package,libraries/integer-gmp,dist-install,$(if $(filter integer-gmp,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
