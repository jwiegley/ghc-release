libraries/integer-simple_PACKAGE = integer-simple
libraries/integer-simple_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/integer-simple,dist-install,$(if $(filter integer-simple,$(STAGE2_PACKAGES)),2,1)))
