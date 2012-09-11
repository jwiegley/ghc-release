libraries/old-locale_PACKAGE = old-locale
libraries/old-locale_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/old-locale,dist-install,$(if $(filter old-locale,$(STAGE2_PACKAGES)),2,1)))
