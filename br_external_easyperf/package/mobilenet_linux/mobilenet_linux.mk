################################################################################
# mobilenet_linux (local-source package)
################################################################################

MOBILENET_LINUX_SITE          = $(BR2_EXTERNAL_EASYP_PATH)/package/mobilenet_linux/src
MOBILENET_LINUX_SITE_METHOD   = local
MOBILENET_LINUX_LICENSE       = Proprietary or Unknown
MOBILENET_THESHIRE_PATH       = $(BR2_EXTERNAL_EASYP_PATH)/../../../../
MOBILENET_TVM_GEN_DIR         = $(MOBILENET_THESHIRE_PATH)/sw/tinyml/out_linux_arcane_mobilenet/


# Build with the cross toolchain
define MOBILENET_LINUX_BUILD_CMDS
	# Generate TVM code if not already generated
	$(MAKE) -C $(BR2_EXTERNAL_EASYP_PATH)/../../../../ tinyml_tvm_linux_arcane_mobilenet
	# Compile
	cp $(BR2_EXTERNAL_EASYP_PATH)/../../../../hw/vendor/axi_llc/sw/arcane_rt/build/arcane_loader.h $(@D)/

    $(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -lm -lpthread \
    $(wildcard $(MOBILENET_TVM_GEN_DIR)/mlf/codegen/host/src/*.c) $(wildcard $(@D)/*.c) \
    -I $(MOBILENET_TVM_GEN_DIR)/mlf/codegen/host/include \
    -I $(MOBILENET_TVM_GEN_DIR)/mlf/runtime/include \
    -I $(MOBILENET_THESHIRE_PATH)/sw/include \
	-I $(MOBILENET_C_INC_DIR)/mlf/runtime/include -o $(@D)/mobilenet_linux
endef

# Install resulting binary into /usr/bin/ and images into /usr/share/mobilenet_images/
define MOBILENET_LINUX_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/mobilenet_linux $(TARGET_DIR)/usr/bin/mobilenet_linux
	mkdir -p $(TARGET_DIR)/usr/share/mobilenet_images
	cp -r $(BR2_EXTERNAL_EASYP_PATH)/../../../tinyml/mobilenet/*.chw $(TARGET_DIR)/usr/share/mobilenet_images/
	cp $(BR2_EXTERNAL_EASYP_PATH)/../../../tinyml/out_linux_arcane_mobilenet/mobilenetv2-12-int8_weights.bin $(TARGET_DIR)/usr/share/mobilenet_images/mobilenet_weights.bin
	cp $(BR2_EXTERNAL_EASYP_PATH)/../../../tinyml/mobilenet/labels.txt $(TARGET_DIR)/usr/share/mobilenet_images/
endef

$(eval $(generic-package))
