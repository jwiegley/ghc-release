libraries/terminfo_PACKAGE = terminfo
libraries/terminfo_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/terminfo,dist-install,$(if $(filter terminfo,$(STAGE2_PACKAGES)),2,1)))
