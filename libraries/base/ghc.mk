libraries/base_PACKAGE = base
libraries/base_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/base,dist-install,$(if $(filter base,$(STAGE2_PACKAGES)),2,1)))
