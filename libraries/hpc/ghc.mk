libraries/hpc_PACKAGE = hpc
libraries/hpc_dist-install_GROUP = libraries
$(if $(filter hpc,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/hpc,dist-boot,0)))
$(eval $(call build-package,libraries/hpc,dist-install,$(if $(filter hpc,$(STAGE2_PACKAGES)),2,1)))
