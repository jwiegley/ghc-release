libraries/Win32_PACKAGE = Win32
libraries/Win32_dist-install_GROUP = libraries
$(if $(filter Win32,$(PACKAGES_STAGE0)),$(eval $(call build-package,libraries/Win32,dist-boot,0)))
$(eval $(call build-package,libraries/Win32,dist-install,$(if $(filter Win32,$(STAGE2_PACKAGES)),2,1)))
