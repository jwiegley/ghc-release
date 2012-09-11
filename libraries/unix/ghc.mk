libraries/unix_PACKAGE = unix
libraries/unix_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/unix,dist-install,$(if $(filter unix,$(STAGE2_PACKAGES)),2,1)))
