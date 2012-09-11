libraries/base_PACKAGE = base
libraries/base_dist-install_GROUP = libraries
$(if $(filter base,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/base,dist-boot,0)))
$(eval $(call build-package,libraries/base,dist-install,$(if $(filter base,$(STAGE2_PACKAGES)),2,1)))
