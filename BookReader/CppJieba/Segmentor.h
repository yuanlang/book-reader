//
//  Segmentor.h
//  C++ wrapper for CppJieba segmentation
//

#ifndef Segmentor_h
#define Segmentor_h

#include <string>
#include <vector>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize Jieba segmentor with dictionary paths.
/// @param dictPath Path to jieba.dict.utf8
/// @param hmmPath Path to hmm_model.utf8
/// @param userDictPath Path to user.dict.utf8
/// @return Opaque pointer to the segmentor instance, or nullptr on failure.
void* jiebaInit(const char *dictPath, const char *hmmPath, const char *userDictPath,
               const char *idfPath, const char *stopWordPath);

/// Segment text into words using MixSegment.
/// @param handle The segmentor instance returned by jiebaInit.
/// @param text The text to segment.
/// @param words Output vector to receive the segmented words.
void jiebaCut(void *handle, const char *text, std::vector<std::string> &words);

/// Free the segmentor instance.
/// @param handle The segmentor instance to free.
void jiebaFree(void *handle);

#ifdef __cplusplus
}
#endif

#endif /* Segmentor_h */
