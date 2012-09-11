libraries/hpc_PACKAGE = hpc
libraries/hpc_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/hpc,dist-install,$(if $(filter hpc,$(STAGE2_PACKAGES)),2,1)))
