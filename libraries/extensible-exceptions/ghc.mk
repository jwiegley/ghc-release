libraries/extensible-exceptions_PACKAGE = extensible-exceptions
libraries/extensible-exceptions_dist-install_GROUP = libraries
$(if $(filter extensible-exceptions,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/extensible-exceptions,dist-boot,0)))
$(eval $(call build-package,libraries/extensible-exceptions,dist-install,$(if $(filter extensible-exceptions,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
