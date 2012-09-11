libraries/unix_PACKAGE = unix
libraries/unix_dist-install_GROUP = libraries
$(if $(filter unix,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/unix,dist-boot,0)))
$(eval $(call build-package,libraries/unix,dist-install,$(if $(filter unix,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
