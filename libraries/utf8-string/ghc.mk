libraries/utf8-string_PACKAGE = utf8-string
libraries/utf8-string_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/utf8-string,dist-install,$(if $(filter utf8-string,$(STAGE2_PACKAGES)),2,1)))
