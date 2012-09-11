libraries/mtl_PACKAGE = mtl
libraries/mtl_dist-install_GROUP = libraries
$(if $(filter mtl,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/mtl,dist-boot,0)))
$(eval $(call build-package,libraries/mtl,dist-install,$(if $(filter mtl,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
