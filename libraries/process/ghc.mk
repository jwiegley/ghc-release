libraries/process_PACKAGE = process
libraries/process_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/process,dist-install,$(if $(filter process,$(STAGE2_PACKAGES)),2,1)))
