//
//  KaldiFbankBridge.h
//  fastv
//
//  Created by rocky on 2025/11/19.
//

#ifndef KaldiFbankBridge_h
#define KaldiFbankBridge_h

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *KaldiFbankHandle;

KaldiFbankHandle KaldiFbankCreate(int sampleRate,
                                  int numMelBins,
                                  float frameLengthMs,
                                  float frameShiftMs,
                                  const char *windowType,
                                  float dither,
                                  bool snipEdges);

void KaldiFbankDestroy(KaldiFbankHandle handle);

int KaldiFbankCompute(KaldiFbankHandle handle,
                      const float *samples,
                      int sampleCount,
                      float **outBuffer,
                      int *outNumFrames,
                      int *outFeatureDim);

void KaldiFbankFreeBuffer(float *buffer);

#ifdef __cplusplus
}
#endif

#endif /* KaldiFbankBridge_h */

