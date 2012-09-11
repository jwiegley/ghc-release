libraries/unix_PACKAGE = unix
libraries/unix_dist-install_GROUP = libraries
$(if $(filter unix,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/unix,dist-boot,0)))
$(eval $(call build-package,libraries/unix,dist-install,$(if $(filter unix,$(STAGE2_PACKAGES)),2,1)))
