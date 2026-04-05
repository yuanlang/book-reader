//
//  JiebaWrapper.h
//  Objective-C wrapper for CppJieba
//

#import <Foundation/Foundation.h>

@interface JiebaWrapper : NSObject

/// Initialize Jieba with dictionary paths from the app bundle.
/// @return YES if initialization succeeded.
- (BOOL)initJieba;

/// Segment the given Chinese text into words.
/// @param text The Chinese text to segment.
/// @return Array of segmented word strings.
- (NSArray<NSString *> *)cut:(NSString *)text;

@end
