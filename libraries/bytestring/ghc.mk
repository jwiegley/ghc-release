libraries/bytestring_PACKAGE = bytestring
libraries/bytestring_dist-install_GROUP = libraries
$(if $(filter bytestring,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/bytestring,dist-boot,0)))
$(eval $(call build-package,libraries/bytestring,dist-install,$(if $(filter bytestring,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
