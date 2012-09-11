libraries/pretty_PACKAGE = pretty
libraries/pretty_dist-install_GROUP = libraries
$(if $(filter pretty,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/pretty,dist-boot,0)))
$(eval $(call build-package,libraries/pretty,dist-install,$(if $(filter pretty,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
