//
//  JiebaWrapper.mm
//  Objective-C++ bridge for CppJieba
//

#import "JiebaWrapper.h"
#include "Segmentor.h"

@implementation JiebaWrapper {
    void *_segmentor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _segmentor = nullptr;
    }
    return self;
}

- (BOOL)initJieba {
    if (_segmentor != nullptr) {
        return YES;
    }

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *dictPath = [bundle pathForResource:@"jieba" ofType:@"dict.utf8"];
    NSString *hmmPath = [bundle pathForResource:@"hmm_model" ofType:@"utf8"];
    NSString *userDictPath = [bundle pathForResource:@"user" ofType:@"dict.utf8"];
    NSString *idfPath = [bundle pathForResource:@"idf" ofType:@"dict.utf8"];
    NSString *stopWordPath = [bundle pathForResource:@"stop_word" ofType:@"utf8"];

    if (!dictPath || !hmmPath || !userDictPath) {
        NSLog(@"Jieba dictionary files not found in bundle");
        return NO;
    }

    _segmentor = jiebaInit(
        [dictPath UTF8String],
        [hmmPath UTF8String],
        [userDictPath UTF8String],
        idfPath ? [idfPath UTF8String] : nullptr,
        stopWordPath ? [stopWordPath UTF8String] : nullptr
    );

    return _segmentor != nullptr;
}

- (NSArray<NSString *> *)cut:(NSString *)text {
    if (_segmentor == nullptr) {
        NSLog(@"Jieba not initialized. Call initJieba first.");
        return @[];
    }

    if (text.length == 0) {
        return @[];
    }

    std::vector<std::string> words;
    jiebaCut(_segmentor, [text UTF8String], words);

    NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:words.size()];
    for (const auto &word : words) {
        [result addObject:[NSString stringWithUTF8String:word.c_str()]];
    }
    return result;
}

- (void)dealloc {
    if (_segmentor != nullptr) {
        jiebaFree(_segmentor);
        _segmentor = nullptr;
    }
}

@end
