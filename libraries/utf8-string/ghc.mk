libraries/utf8-string_PACKAGE = utf8-string
libraries/utf8-string_dist-install_GROUP = libraries
$(if $(filter utf8-string,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/utf8-string,dist-boot,0)))
$(eval $(call build-package,libraries/utf8-string,dist-install,$(if $(filter utf8-string,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
