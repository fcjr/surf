// Touch data layout adapted from OpenMultitouchSupport's OpenMTInternal.h.
// Copyright (c) 2019 TakutoNakamura. MIT licensed; see
// ../Resources/Licenses/OpenMultitouchSupport.txt.
// Surf uses shorter field names and resolves the functions at runtime.
#import <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>

typedef void *MTDeviceRef;
typedef struct {
    float x;
    float y;
} MTPoint;
typedef struct {
    MTPoint pos;
    MTPoint vel;
} MTReadout;
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerId;
    int handId;
    MTReadout normalized;
    float size;
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTReadout mm;
    int field14;
    int field15;
    float density;
} MTFinger;

_Static_assert(sizeof(MTFinger) == 96, "Unexpected multitouch contact layout");

typedef void (*MTContactCallback)(MTDeviceRef device, MTFinger *data, int nFingers, double timestamp, int frame);
typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallback);
typedef void (*MTUnregisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallback);
typedef int32_t (*MTDeviceStartFn)(MTDeviceRef, int);
typedef int32_t (*MTDeviceStopFn)(MTDeviceRef);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef);
typedef int32_t (*MTDeviceGetFamilyIDFn)(MTDeviceRef, int *);
typedef int32_t (*MTDeviceGetDeviceIDFn)(MTDeviceRef, uint64_t *);
