################################################################################
# dinov2_linux (local-source package)
################################################################################

DINOV2_LINUX_SITE          = $(BR2_EXTERNAL_EASYP_PATH)/package/dinov2_linux/src
DINOV2_LINUX_SITE_METHOD   = local
DINOV2_LINUX_LICENSE       = Proprietary or Unknown
DINOV2_THESHIRE_PATH       = $(BR2_EXTERNAL_EASYP_PATH)/../../../../
DINOV2_TVM_GEN_DIR         = $(DINOV2_THESHIRE_PATH)/sw/tinyml/out_linux_arcane_dinov2/


# Build with the cross toolchain
define DINOV2_LINUX_BUILD_CMDS
	# Generate TVM code if not already generated
	$(MAKE) -C $(BR2_EXTERNAL_EASYP_PATH)/../../../../ tinyml_tvm_linux_arcane_dinov2
	# Compile
	cp $(BR2_EXTERNAL_EASYP_PATH)/../../../../hw/vendor/axi_llc/sw/arcane_rt/build/arcane_loader.h $(@D)/

    $(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -lm -lpthread \
    $(wildcard $(DINOV2_TVM_GEN_DIR)/mlf/codegen/host/src/*.c) $(wildcard $(@D)/*.c) \
    -I $(DINOV2_TVM_GEN_DIR)/mlf/codegen/host/include \
    -I $(DINOV2_TVM_GEN_DIR)/mlf/runtime/include \
    -I $(DINOV2_THESHIRE_PATH)/sw/include \
	-I $(DINOV2_C_INC_DIR)/mlf/runtime/include -o $(@D)/dinov2_linux
endef

# Install resulting binary into /usr/bin/ and images into /usr/share/dinov2_images/
define DINOV2_LINUX_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/dinov2_linux $(TARGET_DIR)/usr/bin/dinov2_linux
	mkdir -p $(TARGET_DIR)/usr/share/dinov2_images
	cp -r $(BR2_EXTERNAL_EASYP_PATH)/../../../tinyml/dinov2/*.chw $(TARGET_DIR)/usr/share/dinov2_images/
	cp $(BR2_EXTERNAL_EASYP_PATH)/../../../tinyml/out_linux_arcane_dinov2/dinov2_weights.bin $(TARGET_DIR)/usr/share/dinov2_images/
endef

$(eval $(generic-package))
