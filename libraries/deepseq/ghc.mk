libraries/deepseq_PACKAGE = deepseq
libraries/deepseq_dist-install_GROUP = libraries
$(if $(filter deepseq,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/deepseq,dist-boot,0)))
$(eval $(call build-package,libraries/deepseq,dist-install,$(if $(filter deepseq,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
