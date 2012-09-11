libraries/bytestring_PACKAGE = bytestring
libraries/bytestring_dist-install_GROUP = libraries
$(if $(filter bytestring,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/bytestring,dist-boot,0)))
$(eval $(call build-package,libraries/bytestring,dist-install,$(if $(filter bytestring,$(STAGE2_PACKAGES)),2,1)))
