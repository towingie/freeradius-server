#
#   Only run EAP tests if we have a "test" target
#
ifneq (,$(findstring test,$(MAKECMDGOALS)))
EAPOL_TEST = $(shell test -e "$(OUTPUT)/eapol_test.skip" || $(top_builddir)/scripts/travis/eapol_test-build.sh)
endif

ifneq "$(EAPOL_TEST)" ""

#
#	Tests for EAP support
#
TEST := test.eap
$(eval $(call TEST_BOOTSTRAP))

TEST_PATH := ${top_srcdir}/src/tests/eapol_test
CONFIG_PATH := $(TEST_PATH)/config
RADIUS_LOG := $(OUTPUT)/radiusd.log
GDB_LOG := $(OUTPUT)/gdb.log
BIN_PATH := $(BUILD_DIR)/bin/local

#
#   We use the stock raddb modules to help detect typos and other issues
#
RADDB_PATH := $(top_builddir)/raddb

#
#	Disabled modules.
#
IGNORED_EAP_TYPES := peap ttls

#
#   This ensures that FreeRADIUS uses modules from the build directory
#
EAP_TARGETS      := $(filter rlm_eap_%,$(ALL_TGTS))
EAP_TYPES_LIST   := $(patsubst rlm_eap_%.la,%,$(EAP_TARGETS))
EAP_TYPES        := $(filter-out $(IGNORED_EAP_TYPES),$(EAP_TYPES_LIST))
EAPOL_TEST_FILES := $(foreach x,$(EAP_TYPES),$(wildcard $(DIR)/$(x)*.conf))
EAPOL_OK_FILES  := $(patsubst $(DIR)/%.conf,$(OUTPUT)/%.ok,$(EAPOL_TEST_FILES))

#
#  Generic rules to start / stop the radius service.
#
include src/tests/radiusd.mk
$(eval $(call RADIUSD_SERVICE,servers,$(OUTPUT)))

#
#	Print the disabled list.
#
$(IGNORED_EAP_TYPES):
	@echo "EAPOL-TEST $@ - Disabled.  Enable by removing '$@' from 'IGNORED_EAP_TYPES' in src/tests/eapol_test/all.mk"

#
#  Separate the dependencies here just to keep a bit clear.
#
test.eap.check: $(IGNORED_EAP_TYPES) | $(OUTPUT) $(GENERATED_CERT_FILES)

#
#  Run EAP tests.
#
$(OUTPUT)/%.ok: $(DIR)/%.conf | $(GENERATED_CERT_FILES)
	@echo "EAPOL-TEST $(notdir $(patsubst %.conf,%,$<))"
	${Q}$(MAKE) --no-print-directory test.eap.radiusd_kill || true
	${Q}$(MAKE) --no-print-directory METHOD=$(basename $(notdir $@)) test.eap.radiusd_start
	${Q} [ -f $(dir $@)/radiusd.pid ] || exit 1
	$(eval OUT := $(patsubst %.conf,%.log,$@))
	$(eval KEY := $(shell grep key_mgmt=NONE $< | sed 's/key_mgmt=NONE/-n/'))
	${Q}if ! $(EAPOL_TEST) -t 2 -c $< -p $(PORT) -s $(SECRET) $(KEY) > $(OUT) 2>&1; then	\
		echo "Last entries in supplicant log ($(patsubst %.conf,%.log,$@)):";	\
		tail -n 40 "$(patsubst %.conf,%.log,$@)";				\
		echo "--------------------------------------------------";		\
		tail -n 40 "$(RADIUS_LOG)";						\
		echo "Last entries in server log ($(RADIUS_LOG)):";			\
		echo "--------------------------------------------------";		\
		echo "$(EAPOL_TEST) -c \"$<\" -p $(PORT) -s $(SECRET)";			\
		$(MAKE) test.eap.radiusd_kill;						\
		echo "RADIUSD :  TEST_PORT=$(PORT) $(RADIUSD_BIN) -Pxxx -d $(dir $<))/config -n servers -D share/dictionary/ -lstdout -f";				\
		echo "EAPOL   :  $(EAPOL_TEST) -c \"$<\" -p $(PORT) -s $(SECRET) $(KEY) "; \
		$(MAKE) --no-print-directory test.eap.radiusd_kill						\
		exit 1;\
	fi
	${Q}$(MAKE) --no-print-directory test.eap.radiusd_kill || true
	${Q}touch $@

$(TEST): $(EAPOL_OK_FILES)

else
#
#  Build rules and the make file get evaluated at different times
#  if we don't touch the test skipped file immediately, users can
#  cntrl-c out of the build process, and the skip file never gets
#  created as the test.eap target is evaluated much later in the
#  build process.2
#
ifneq (,$(findstring test,$(MAKECMDGOALS)))
$(shell touch "$(OUTPUT)/eapol_test.skip")
endif

$(TEST): $(OUTPUT)
	@echo "Retry with: $(MAKE) clean.$@ && $(MAKE) $@"
endif
