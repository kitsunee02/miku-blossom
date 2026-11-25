# HsinOS Android 15 product for Xiaomi Redmi 9A (blossom).
# Adapted from the public lineage_blossom.mk product in the lineage-22.2 tree.

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/non_ab_device.mk)

# Device configuration.
$(call inherit-product, device/xiaomi/blossom/device.mk)

# HsinOS common product configuration replaces the LineageOS common product.
$(call inherit-product, vendor/hsin/build/product/hsin_product.mk)

scr_resolution := 720
TARGET_SUPPORTS_BLUR := true
TARGET_ENABLE_BLUR := true
TARGET_BOOT_ANIMATION_RES := 720

PRODUCT_NAME := hsin_blossom
PRODUCT_DEVICE := blossom
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_BRAND := Redmi

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi
