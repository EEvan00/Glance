#ifndef GLANCE_SMC_DEFINITIONS_H
#define GLANCE_SMC_DEFINITIONS_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} GlanceSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} GlanceSMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} GlanceSMCKeyInfoData;

typedef struct {
    uint32_t key;
    GlanceSMCVersion vers;
    GlanceSMCPLimitData pLimitData;
    GlanceSMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} GlanceSMCParamStruct;

_Static_assert(sizeof(GlanceSMCParamStruct) == 80, "Unexpected AppleSMC parameter size");
_Static_assert(offsetof(GlanceSMCParamStruct, keyInfo) == 28, "Unexpected AppleSMC keyInfo offset");
_Static_assert(offsetof(GlanceSMCParamStruct, data8) == 42, "Unexpected AppleSMC command offset");
_Static_assert(offsetof(GlanceSMCParamStruct, bytes) == 48, "Unexpected AppleSMC data offset");

#endif
