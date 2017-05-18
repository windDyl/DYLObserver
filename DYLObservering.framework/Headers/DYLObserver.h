//
//  DYLObserver.h
//  Block Key-Value Observing
//
//  Created by Martin Kiss on 28.9.12.
//  Copyright (c) 2012 iMartin Kiss. All rights reserved.
//

#import <Foundation/Foundation.h>



#pragma mark Block Typedefs

typedef void(^DYLBlockGeneric)          (id self, id newValue);
typedef void(^DYLBlockChange)           (id self, id oldValue, id newValue);
typedef void(^DYLBlockChangeMany)       (id self, NSString *keyPath, id oldValue, id newValue);
typedef void(^DYLBlockInsert)           (id self, id newValue, NSIndexSet *indexes);
typedef void(^DYLBlockRemove)           (id self, id oldValue,  NSIndexSet *indexes);
typedef void(^DYLBlockReplace)          (id self, id oldValue, id newValue, NSIndexSet *indexes);

typedef void(^DYLBlockForeignChange)    (id self, id object, id oldValue, id newValue);
typedef void(^DYLBlockForeignChangeMany)(id self, id object, NSString *keyPath, id oldValue, id newValue);

typedef void(^DYLBlockNotify)           (id self, NSNotification *notification);





/**
 This is private class. This is the object that holds observation blocks and observes given property using standatd KVO.
 For multiple observations of the same key-path (and object) only one observer is used.
 */
@interface DYLObserver : NSObject


#pragma mark Initialization
/// Do not use. Observation target will be nil, so any calls to it will have no effect.
- (id)init;
/// Designated initializer.
- (id)initWithTarget:(NSObject *)target keyPath:(NSString *)keyPath owner:(id)owner;


#pragma mark Observation
/// Object that is observed when the receiver is attached.
@property (nonatomic, readonly, assign) id target;
/// Key-path that is observed on the target.
@property (nonatomic, readonly, copy) NSString *keyPath;
/// Object that 'owns' all blocks in this observer. This object was the caller of observation method.
@property (nonatomic, readonly, assign) id owner;


#pragma mark Attaching
/// Attached means, that this object really observes the key-path it was initialized with. Set it to add/remove this observer.
@property (nonatomic, readwrite, assign) BOOL attached;
/// Convenience method to set `attached` to YES.
- (void)attach;
/// Convenience method to set `attached` to NO.
- (void)detach;


#pragma mark Blocks
/// Add block to be executed on key-path setting of simple property or relationship.
- (void)addSettingObservationBlock:(DYLBlockChange)block;
/// Add block to be executed on key-path relationship insertion.
- (void)addInsertionObservationBlock:(DYLBlockInsert)block;
/// Append block to be executed on key-path relationship removal.
- (void)addRemovalObservationBlock:(DYLBlockRemove)block;
/// Add block to be executed on key-path relationship replacement.
- (void)addReplacementObservationBlock:(DYLBlockReplace)block;


@end
