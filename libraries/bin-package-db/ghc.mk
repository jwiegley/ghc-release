libraries/bin-package-db_PACKAGE = bin-package-db
libraries/bin-package-db_dist-install_GROUP = libraries
$(if $(filter bin-package-db,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/bin-package-db,dist-boot,0)))
$(eval $(call build-package,libraries/bin-package-db,dist-install,$(if $(filter bin-package-db,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
