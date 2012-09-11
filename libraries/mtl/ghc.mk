libraries/mtl_PACKAGE = mtl
libraries/mtl_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/mtl,dist-install,$(if $(filter mtl,$(STAGE2_PACKAGES)),2,1)))
