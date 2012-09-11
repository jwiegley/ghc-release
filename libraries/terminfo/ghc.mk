libraries/terminfo_PACKAGE = terminfo
libraries/terminfo_dist-install_GROUP = libraries
$(if $(filter terminfo,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/terminfo,dist-boot,0)))
$(eval $(call build-package,libraries/terminfo,dist-install,$(if $(filter terminfo,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
