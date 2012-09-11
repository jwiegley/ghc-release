# DO NOT EDIT!  Instead, create a file mk/validate.mk, whose settings will
# override these.  See also mk/custom-settings.mk.

WERROR          = -Werror

HADDOCK_DOCS    = YES
SRC_CC_OPTS     += -Wall $(WERROR)
SRC_HC_OPTS     += -Wall $(WERROR) -H64m -O0

GhcStage1HcOpts += -O

GhcStage2HcOpts += -O
# Using -O (rather than -O0) here bringes my validate down from 22mins to 16 mins.
# Compiling stage2 takes longer, but we gain a faster haddock, faster
# running of the tests, and faster building of the utils to be installed

GhcLibHcOpts    += -O -dcore-lint
GhcLibWays     := $(filter v dyn,$(GhcLibWays))
SplitObjs       = NO
NoFibWays       =
STRIP           = :

CHECK_PACKAGES = YES

# dblatex with miktex under msys/mingw can't build the PS and PDF docs,
# and just building the HTML docs is sufficient to check that the
# markup is correct, so we turn off PS and PDF doc building when
# validating.
BUILD_DOCBOOK_PS  = NO
BUILD_DOCBOOK_PDF = NO

ifeq "$(ValidateHpc)" "YES"
GhcStage2HcOpts += -fhpc -hpcdir $(TOP)/testsuite/hpc_output/
endif
ifeq "$(ValidateSlow)" "YES"
GhcStage2HcOpts += -XGenerics -DDEBUG
GhcLibHcOpts    += -XGenerics
endif

# Temporarily turn off unused-do-bind warnings for the time package
libraries/time_dist-install_EXTRA_HC_OPTS += -fno-warn-unused-do-bind
# On Windows, there are also some unused import warnings
libraries/time_dist-install_EXTRA_HC_OPTS += -fno-warn-unused-imports

libraries/haskeline_dist-install_EXTRA_HC_OPTS += -fno-warn-unused-imports

# Temporarily turn off unused-import warnings for the ghc-binary package
libraries/ghc-binary_dist-boot_EXTRA_HC_OPTS += -fno-warn-unused-imports
libraries/ghc-binary_dist-install_EXTRA_HC_OPTS += -fno-warn-unused-imports
