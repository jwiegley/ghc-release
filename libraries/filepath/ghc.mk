libraries/filepath_PACKAGE = filepath
libraries/filepath_dist-install_GROUP = libraries
$(if $(filter filepath,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/filepath,dist-boot,0)))
$(eval $(call build-package,libraries/filepath,dist-install,$(if $(filter filepath,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
