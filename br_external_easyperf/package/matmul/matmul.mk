################################################################################
# easyperf (local-source package)
################################################################################

MATMUL_SITE          = $(BR2_EXTERNAL_EASYP_PATH)/package/matmul/src
MATMUL_SITE_METHOD   = local
MATMUL_LICENSE       = Proprietary or Unknown
# MATMUL_LICENSE_FILES = LICENSE

# Build with the cross toolchain against the upstream Makefile
define MATMUL_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" AR="$(TARGET_AR)" STRIP="$(TARGET_STRIP)" \
		CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)"
endef

# Install resulting binary; adjust name/path if your Makefile outputs something else
define MATMUL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/matmul64 $(TARGET_DIR)/usr/bin/matmul64
	$(INSTALL) -D -m 0755 $(@D)/matmul128 $(TARGET_DIR)/usr/bin/matmul128
	$(INSTALL) -D -m 0755 $(@D)/matmul256 $(TARGET_DIR)/usr/bin/matmul256
endef

$(eval $(generic-package))
