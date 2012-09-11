libraries/pretty_PACKAGE = pretty
libraries/pretty_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/pretty,dist-install,$(if $(filter pretty,$(STAGE2_PACKAGES)),2,1)))
