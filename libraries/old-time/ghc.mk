libraries/old-time_PACKAGE = old-time
libraries/old-time_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/old-time,dist-install,$(if $(filter old-time,$(STAGE2_PACKAGES)),2,1)))
