libraries/Win32_PACKAGE = Win32
libraries/Win32_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/Win32,dist-install,$(if $(filter Win32,$(STAGE2_PACKAGES)),2,1)))
