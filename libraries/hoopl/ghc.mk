libraries/hoopl_PACKAGE = hoopl
libraries/hoopl_dist-install_GROUP = libraries
$(if $(filter hoopl,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/hoopl,dist-boot,0)))
$(eval $(call build-package,libraries/hoopl,dist-install,$(if $(filter hoopl,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
