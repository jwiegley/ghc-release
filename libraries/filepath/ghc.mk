libraries/filepath_PACKAGE = filepath
libraries/filepath_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/filepath,dist-install,$(if $(filter filepath,$(STAGE2_PACKAGES)),2,1)))
