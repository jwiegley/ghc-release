# -----------------------------------------------------------------------------
# Examples of use:
#
# 	make		-- run all the tests in the current directory
# 	make verbose	-- as make test, but up the verbosity
# 	make accept	-- run the tests, accepting the current output
#
# The following variables may be set on the make command line:
#
#	TEST		-- specific test to run
#	TESTS		-- specific tests to run (same as $TEST really)
#	EXTRA_HC_OPTS	-- extra flags to send to the Haskell compiler
#	EXTRA_RUNTEST_OPTS -- extra flags to give the test driver
#	CONFIG		-- use a different configuration file
#	COMPILER	-- select a configuration file from config/
#       THREADS         -- run n tests at once
#
# -----------------------------------------------------------------------------

include $(TOP)/mk/wordsize.mk

$(TOP)/mk/wordsize.mk : $(TOP)/mk/wordsize.mk.in
	$(CPP) $(RAWCPP_FLAGS) -x c $(TOP)/mk/wordsize.mk.in > $(TOP)/mk/wordsize.mk

ifeq "$(PYTHON)" ""
$(error Python must be installed in order to use the testsuite)
endif

# export the value of $MAKE for invocation in ghc-regress/driver/
export MAKE

# ghastly hack, because the driver requires that $tool be an absolute path name.
HP2PS_ABS	= $(GHC_HP2PS_DIR_ABS)/hp2ps
GS = gs

RUNTESTS     = $(TOP)/driver/runtests.py
COMPILER     = ghc
CONFIGDIR    = $(TOP)/config
CONFIG       = $(CONFIGDIR)/$(COMPILER)

# can be overriden from the command line
ifneq "$(stage)" ""
TEST_HC = $(GHC_STAGE$(stage))
else
TEST_HC = $(GHC_STAGE2)
endif

GHC_PKG = $(GHC_PKG_INPLACE)

RUNTEST_OPTS =

ifeq "$(GhcWithNativeCodeGen)" "YES"
RUNTEST_OPTS += -e ghc_with_native_codegen=1
else
RUNTEST_OPTS += -e ghc_with_native_codegen=0
endif

ifeq "$(filter p, $(GhcLibWays))" "p"
RUNTEST_OPTS += -e ghc_with_profiling=1
else
RUNTEST_OPTS += -e ghc_with_profiling=0
endif

ifeq "$(GhcWithInterpreter)" "YES"
RUNTEST_OPTS += -e ghc_with_interpreter=1
else
RUNTEST_OPTS += -e ghc_with_interpreter=0
endif

ifeq "$(GhcUnregisterised)" "YES"
RUNTEST_OPTS += -e ghc_unregisterised=1
else
RUNTEST_OPTS += -e ghc_unregisterised=0
endif

ifeq "$(filter thr, $(GhcRTSWays))" "thr"
RUNTEST_OPTS += -e ghc_with_threaded_rts=1
else
RUNTEST_OPTS += -e ghc_with_threaded_rts=0
endif

ifeq "$(GhcWithSMP)" "YES"
RUNTEST_OPTS += -e ghc_with_smp=1
else
RUNTEST_OPTS += -e ghc_with_smp=0
endif

ifneq "$(THREADS)" ""
RUNTEST_OPTS += --threads=$(THREADS)
endif

RUNTEST_OPTS +=  \
	--rootdir=. \
	--config=$(CONFIG) \
	-e config.confdir=\"$(CONFIGDIR)\" \
	-e config.compiler=\"$(TEST_HC)\" \
	-e config.compiler_always_flags.append"(\"-D$(HostPlatform_CPP)\")" \
	-e config.compiler_always_flags.append"(\"$(EXTRA_HC_OPTS)\")" \
	-e config.ghc_pkg=\"$(GHC_PKG)\" \
	-e config.hp2ps=\"$(HP2PS_ABS)\" \
	-e config.gs=\"$(GS)\" \
	-e config.platform=\"$(TARGETPLATFORM)\" \
	-e config.os=\"$(TargetOS_CPP)\" \
	-e config.wordsize=\"$(WORDSIZE)\" \
	-e default_testopts.cleanup=\"$(CLEANUP)\" \
	-e config.timeout="int($(TIMEOUT)) or config.timeout" \
	-e config.timeout_prog=\"$(TIMEOUT_PROGRAM)\" \
	-e config.exeext=\"$(exeext)\" \
	-e config.top=\"$(FPTOOLS_TOP_ABS)/testsuite\" \
	$(EXTRA_RUNTEST_OPTS)

# HostPlatform_CPP should ideally be TargetPlatform_CPP, but that
# doesn't exist; they're always the same anyway

ifeq "$(fast)" "YES"
setfast = -e config.fast=1
else
setfast = 
endif

ifeq "$(accept)" "YES"
setaccept = -e config.accept=1
else
setaccept = 
endif

TESTS	     = 
TEST	     = 
WAY =

all :: test

TIMEOUT_PROGRAM = $(TOP)/timeout/install-inplace/bin/timeout$(exeext)

timeout : $(TIMEOUT_PROGRAM)

$(TIMEOUT_PROGRAM) :
	@echo "Looks like you don't have timeout, building it first..."
	cd $(TOP)/timeout && $(MAKE) $(MFLAGS) all

pwd : $(TOP)/utils/pwd$(exeext)

$(TOP)/utils/pwd$(exeext) :
	@echo "Looks like you don't have pwd, building utils first..."
	cd $(TOP)/utils && $(MAKE) $(MFLAGS) all

test: timeout pwd
	$(PYTHON) $(RUNTESTS) $(RUNTEST_OPTS) \
		$(patsubst %, --only=%, $(TEST)) \
		$(patsubst %, --only=%, $(TESTS)) \
		$(patsubst %, --way=%, $(WAY)) \
		$(patsubst %, --skipway=%, $(SKIPWAY)) \
		$(setfast) \
		$(setaccept)

verbose: test

accept:
	$(MAKE) accept=YES

fast:
	$(MAKE) fast=YES

