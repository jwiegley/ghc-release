libraries/extensible-exceptions_PACKAGE = extensible-exceptions
libraries/extensible-exceptions_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/extensible-exceptions,dist-install,$(if $(filter extensible-exceptions,$(STAGE2_PACKAGES)),2,1)))
