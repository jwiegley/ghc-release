libraries/xhtml_PACKAGE = xhtml
libraries/xhtml_dist-install_GROUP = libraries
$(if $(filter xhtml,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/xhtml,dist-boot,0)))
$(eval $(call build-package,libraries/xhtml,dist-install,$(if $(filter xhtml,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
