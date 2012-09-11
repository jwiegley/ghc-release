libraries/mtl_PACKAGE = mtl
libraries/mtl_dist-install_GROUP = libraries
$(if $(filter mtl,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/mtl,dist-boot,0)))
$(eval $(call build-package,libraries/mtl,dist-install,$(if $(filter mtl,$(STAGE2_PACKAGES)),2,1)))
