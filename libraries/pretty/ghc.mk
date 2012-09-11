libraries/pretty_PACKAGE = pretty
libraries/pretty_dist-install_GROUP = libraries
$(if $(filter pretty,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/pretty,dist-boot,0)))
$(eval $(call build-package,libraries/pretty,dist-install,$(if $(filter pretty,$(STAGE2_PACKAGES)),2,1)))
