libraries/hpc_PACKAGE = hpc
libraries/hpc_dist-install_GROUP = libraries
$(if $(filter hpc,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/hpc,dist-boot,0)))
$(eval $(call build-package,libraries/hpc,dist-install,$(if $(filter hpc,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
