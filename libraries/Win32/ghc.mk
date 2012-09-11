libraries/Win32_PACKAGE = Win32
libraries/Win32_dist-install_GROUP = libraries
$(if $(filter Win32,$(PKGS_THAT_BUILD_WITH_STAGE0)),$(eval $(call build-package,libraries/Win32,dist-boot,0)))
$(eval $(call build-package,libraries/Win32,dist-install,$(if $(filter Win32,$(PKGS_THAT_BUILD_WITH_STAGE2)),2,1)))
