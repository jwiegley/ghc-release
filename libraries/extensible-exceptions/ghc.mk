libraries/extensible-exceptions_PACKAGE = extensible-exceptions
libraries/extensible-exceptions_dist-install_GROUP = libraries
$(if $(filter extensible-exceptions,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/extensible-exceptions,dist-boot,0)))
$(eval $(call build-package,libraries/extensible-exceptions,dist-install,$(if $(filter extensible-exceptions,$(STAGE2_PACKAGES)),2,1)))
