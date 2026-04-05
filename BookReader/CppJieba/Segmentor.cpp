//
//  Segmentor.cpp
//  C++ wrapper for CppJieba segmentation
//

#include "Segmentor.h"
#include "cppjieba/Jieba.hpp"

struct JiebaHandle {
    cppjieba::Jieba *jieba;
};

void* jiebaInit(const char *dictPath, const char *hmmPath, const char *userDictPath,
               const char *idfPath, const char *stopWordPath) {
    try {
        cppjieba::Jieba *jieba = new cppjieba::Jieba(
            dictPath,
            hmmPath,
            userDictPath,
            idfPath ? idfPath : "",
            stopWordPath ? stopWordPath : ""
        );
        JiebaHandle *handle = new JiebaHandle();
        handle->jieba = jieba;
        return handle;
    } catch (const std::exception &e) {
        return nullptr;
    }
}

void jiebaCut(void *handle, const char *text, std::vector<std::string> &words) {
    if (!handle) return;
    JiebaHandle *jh = static_cast<JiebaHandle*>(handle);
    jh->jieba->Cut(text, words);
}

void jiebaFree(void *handle) {
    if (!handle) return;
    JiebaHandle *jh = static_cast<JiebaHandle*>(handle);
    delete jh->jieba;
    delete jh;
}
