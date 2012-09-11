libraries/bytestring_PACKAGE = bytestring
libraries/bytestring_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/bytestring,dist-install,$(if $(filter bytestring,$(STAGE2_PACKAGES)),2,1)))
