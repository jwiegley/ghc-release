libraries/hoopl_PACKAGE = hoopl
libraries/hoopl_dist-install_GROUP = libraries
$(if $(filter hoopl,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/hoopl,dist-boot,0)))
$(eval $(call build-package,libraries/hoopl,dist-install,$(if $(filter hoopl,$(STAGE2_PACKAGES)),2,1)))
