libraries/bin-package-db_PACKAGE = bin-package-db
libraries/bin-package-db_dist-install_GROUP = libraries
$(if $(filter bin-package-db,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/bin-package-db,dist-boot,0)))
$(eval $(call build-package,libraries/bin-package-db,dist-install,$(if $(filter bin-package-db,$(STAGE2_PACKAGES)),2,1)))
