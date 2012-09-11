libraries/transformers_PACKAGE = transformers
libraries/transformers_dist-install_GROUP = libraries
$(if $(filter transformers,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/transformers,dist-boot,0)))
$(eval $(call build-package,libraries/transformers,dist-install,$(if $(filter transformers,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
