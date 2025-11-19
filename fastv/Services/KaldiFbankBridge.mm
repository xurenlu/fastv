//
//  KaldiFbankBridge.mm
//  fastv
//
//  Created by rocky on 2025/11/19.
//

#import <Foundation/Foundation.h>
#import "KaldiFbankBridge.h"

#include <algorithm>
#include <vector>
#include <string>
#include <memory>
#include <cstdlib>

#include "../../ThirdParty/kaldi-native-fbank/csrc/online-feature.h"

// 引入 kaldi-native-fbank 源文件以便在同一翻译单元内编译
#include "../../ThirdParty/kaldi-native-fbank/csrc/log.cc"
#include "../../ThirdParty/kaldi-native-fbank/csrc/feature-window.cc"
#include "../../ThirdParty/kaldi-native-fbank/csrc/feature-functions.cc"
#include "../../ThirdParty/kaldi-native-fbank/csrc/mel-computations.cc"
#include "../../ThirdParty/kaldi-native-fbank/csrc/feature-fbank.cc"
#include "../../ThirdParty/kaldi-native-fbank/csrc/rfft.cc"
#include "../../ThirdParty/kaldi-native-fbank/csrc/online-feature.cc"
extern "C" {
#include "../../ThirdParty/kaldi-native-fbank/csrc/fftsg.c"
}

struct KaldiFbankHandleWrapper {
    knf::FbankOptions opts;
};

KaldiFbankHandle KaldiFbankCreate(int sampleRate,
                                  int numMelBins,
                                  float frameLengthMs,
                                  float frameShiftMs,
                                  const char *windowType,
                                  float dither,
                                  bool snipEdges) {
    auto wrapper = new (std::nothrow) KaldiFbankHandleWrapper();
    if (!wrapper) {
        return nullptr;
    }
    
    wrapper->opts.frame_opts.samp_freq = static_cast<float>(sampleRate);
    wrapper->opts.frame_opts.frame_length_ms = frameLengthMs;
    wrapper->opts.frame_opts.frame_shift_ms = frameShiftMs;
    wrapper->opts.frame_opts.window_type = windowType ? windowType : "hamming";
    wrapper->opts.frame_opts.dither = dither;
    wrapper->opts.frame_opts.snip_edges = snipEdges;
    wrapper->opts.mel_opts.num_bins = numMelBins;
    wrapper->opts.energy_floor = 0.0f;
    
    return static_cast<KaldiFbankHandle>(wrapper);
}

void KaldiFbankDestroy(KaldiFbankHandle handle) {
    if (!handle) {
        return;
    }
    auto wrapper = static_cast<KaldiFbankHandleWrapper *>(handle);
    delete wrapper;
}

int KaldiFbankCompute(KaldiFbankHandle handle,
                      const float *samples,
                      int sampleCount,
                      float **outBuffer,
                      int *outNumFrames,
                      int *outFeatureDim) {
    if (!handle || !samples || sampleCount <= 0 || !outBuffer ||
        !outNumFrames || !outFeatureDim) {
        return -1;
    }
    
    auto wrapper = static_cast<KaldiFbankHandleWrapper *>(handle);
    
    knf::OnlineFbank fbank(wrapper->opts);
    
    std::vector<float> scaled(samples, samples + sampleCount);
    constexpr float scale = 32768.0f;
    std::for_each(scaled.begin(), scaled.end(), [](float &value) {
        value *= scale;
    });
    
    fbank.AcceptWaveform(wrapper->opts.frame_opts.samp_freq, scaled.data(), sampleCount);
    fbank.InputFinished();
    
    int32_t frames = fbank.NumFramesReady();
    int32_t dim = fbank.Dim();
    
    if (frames <= 0 || dim <= 0) {
        *outBuffer = nullptr;
        *outNumFrames = 0;
        *outFeatureDim = 0;
        return 0;
    }
    
    size_t totalCount = static_cast<size_t>(frames) * static_cast<size_t>(dim);
    float *buffer = static_cast<float *>(malloc(totalCount * sizeof(float)));
    if (!buffer) {
        return -2;
    }
    
    for (int32_t i = 0; i < frames; ++i) {
        const float *frame = fbank.GetFrame(i);
        memcpy(buffer + static_cast<size_t>(i) * dim, frame, dim * sizeof(float));
    }
    
    *outBuffer = buffer;
    *outNumFrames = frames;
    *outFeatureDim = dim;
    
    return 0;
}

void KaldiFbankFreeBuffer(float *buffer) {
    if (buffer) {
        free(buffer);
    }
}

