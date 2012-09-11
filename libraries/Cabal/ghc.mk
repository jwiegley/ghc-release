libraries/Cabal_PACKAGE = Cabal
libraries/Cabal_dist-install_GROUP = libraries
$(eval $(call build-package,libraries/Cabal,dist-install,1))
