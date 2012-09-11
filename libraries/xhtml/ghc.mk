libraries/xhtml_PACKAGE = xhtml
libraries/xhtml_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/xhtml,dist-install,$(if $(filter xhtml,$(STAGE2_PACKAGES)),2,1)))
