################################################################################
# arcane_tests (local-source package)
################################################################################

ARCANE_TESTS_SITE          = $(BR2_EXTERNAL_EASYP_PATH)/package/arcane_tests/src
ARCANE_TESTS_SITE_METHOD   = local
ARCANE_TESTS_LICENSE       = Proprietary or Unknown
CFLAGS 					   = $(TARGET_CFLAGS) -O2

# Build with the cross toolchain
define ARCANE_TESTS_BUILD_CMDS
	# Copy the loader header from the build tree
	cp $(BR2_EXTERNAL_EASYP_PATH)/../../../../hw/vendor/axi_llc/sw/arcane_rt/build/arcane_loader.h $(@D)/
	# Compile
	$(TARGET_CC) $(CFLAGS) $(TARGET_LDFLAGS) \
		$(@D)/arcane_user.c $(@D)/arcane_test.c -o $(@D)/arcane_test
	$(TARGET_OBJDUMP) -S -d $(@D)/arcane_test > $(@D)/arcane_test.S
endef

# Install resulting binary
define ARCANE_TESTS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/arcane_test $(TARGET_DIR)/usr/bin/arcane_test
endef

$(eval $(generic-package))
