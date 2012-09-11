libraries/xhtml_PACKAGE = xhtml
libraries/xhtml_dist-install_GROUP = libraries
$(if $(filter xhtml,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/xhtml,dist-boot,0)))
$(eval $(call build-package,libraries/xhtml,dist-install,$(if $(filter xhtml,$(STAGE2_PACKAGES)),2,1)))
