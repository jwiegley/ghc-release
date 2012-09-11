libraries/terminfo_PACKAGE = terminfo
libraries/terminfo_dist-install_GROUP = libraries
$(if $(filter terminfo,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/terminfo,dist-boot,0)))
$(eval $(call build-package,libraries/terminfo,dist-install,$(if $(filter terminfo,$(STAGE2_PACKAGES)),2,1)))
