################################################################################
# easyperf (local-source package)
################################################################################

EASYPERF_SITE          = $(BR2_EXTERNAL_EASYP_PATH)/package/easyperf/src
EASYPERF_SITE_METHOD   = local
EASYPERF_LICENSE       = Proprietary or Unknown
# EASYPERF_LICENSE_FILES = LICENSE

# Build with the cross toolchain against the upstream Makefile
define EASYPERF_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" AR="$(TARGET_AR)" STRIP="$(TARGET_STRIP)" \
		CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)"
endef

# Install resulting binary; adjust name/path if your Makefile outputs something else
define EASYPERF_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/easyperf $(TARGET_DIR)/usr/bin/easyperf
endef

$(eval $(generic-package))
