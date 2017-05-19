//
//  NSObject+DYLObserving.m
//  DYL Key-Value Observing
//
//  Created by Martin Kiss on 14.7.12.
//  Copyright (c) 2012 iMartin Kiss. All rights reserved.
//

#import "NSObject+DYLObserving.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "DYLObserver.h"
#import "DYLDeallocator.h"


@implementation NSObject (DYLObserving)





#pragma mark Internal

/// Getter for dictionary containing all registered observers for this object. Keys are observed key-paths.
- (NSMutableDictionary *)dyl_keyPathBlockObservers {
    // Observer is hidden object that has target (this object), key path and owner.
    // There should never exist two or more observers with the same target, key path and owner.
    // Observer has multiple observation block which are executed in order they were added.
    @synchronized(self) {
        NSMutableDictionary *keyPathObservers = objc_getAssociatedObject(self, _cmd);
        if ( ! keyPathObservers) {
            keyPathObservers = [[NSMutableDictionary alloc] init];
            objc_setAssociatedObject(self, _cmd, keyPathObservers, OBJC_ASSOCIATION_RETAIN);
        }
        __weak typeof(self)ws = self;
        [self dyl_addDeallocationCallback:^(id self) {
            __strong typeof(self)ss = ws;
            [ss internalRemoveAllObservations];
        }];
        
        return keyPathObservers;
    }
}

/// Find existing observer or create new for this key-path and owner. Multiple uses of one key-path per owner return the same observer.
- (DYLObserver *)dyl_observerForKeyPath:(NSString *)keyPath owner:(id)owner {
    DYLObserver *observer = nil;
    // Key path is used as key to retrieve observer.
    // For one key-path may be more observers with different owners.
    
    // Obtain the set
    NSMutableSet *observersForKeyPath = [[self dyl_keyPathBlockObservers] objectForKey:keyPath];
    if ( ! observersForKeyPath) {
        // Nothing found for this key-path
        observersForKeyPath = [[NSMutableSet alloc] init];
        [[self dyl_keyPathBlockObservers] setObject:observersForKeyPath forKey:keyPath];
    }
    else {
        // Find the one with this owner
        for (DYLObserver *existingObserver in observersForKeyPath) {
            if (existingObserver.owner == owner) {
                observer = existingObserver;
                break;
            }
        }
    }
    // Now the observer itself
    if ( ! observer) {
        observer = [[DYLObserver alloc] initWithTarget:self keyPath:keyPath owner:owner];
        [observersForKeyPath addObject:observer];
        [observer attach];
        
        [owner dyl_addDeallocationCallback:^(id owner) {
            [observer.target dyl_removeObservationsForOwner:owner keyPath:keyPath];
        }];
    }
    return observer;
}

/// Getter for set containing all registered notification observers for this object. See `NSNotificationCenter`.
- (NSMutableSet *)dyl_notificationBlockObservers {
    static char associationKey;
    NSMutableSet *notificationObservers = objc_getAssociatedObject(self, &associationKey);
    if ( ! notificationObservers) {
        notificationObservers = [[NSMutableSet alloc] init];
        objc_setAssociatedObject(self,
                                 &associationKey,
                                 notificationObservers,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return notificationObservers;
}

/// Called internally by the owner.
- (void)dyl_removeAllObservationsForOwner:(id)owner {
    for (NSString *keyPath in [self dyl_keyPathBlockObservers]) {
        [self dyl_removeObservationsForOwner:owner keyPath:keyPath];
    }
}

/// Called internally by the owner.
- (void)dyl_removeObservationsForOwner:(id)owner keyPath:(NSString *)keyPath {
    NSMutableSet *observersForKeyPath = [self dyl_keyPathBlockObservers][keyPath];
    
    // Avoiding obscure memory issue. First, collect all observers with given owner and then detach them.
    // This avoids using `observer.owner` after it might already got deallocated, because of detached observation.
    NSMutableSet *observersForOwnerForKeyPath = [[NSMutableSet alloc] init];
    for (DYLObserver *observer in observersForKeyPath) {
        if (observer.owner == owner) {
            [observersForOwnerForKeyPath addObject:observer];
        }
    }
    for (DYLObserver *observer in observersForOwnerForKeyPath) {
        [observer detach];
        [observersForKeyPath removeObject:observer];
    }
}





#pragma mark Observe Properties

- (void)dyl_observeProperty:(NSString *)keyPath withBlock:(DYLBlockChange)observationBlock {
    __weak typeof(self)ws = self;
    [self dyl_observeObject:self property:keyPath withBlock:^(id self, id object, id old, id new) {
        __strong typeof(self)ss = ws;
        observationBlock(ss, old, new);
    }];
}

- (void)dyl_observeProperties:(NSArray *)keyPaths withBlock:(DYLBlockChangeMany)observationBlock {
    __weak typeof(self)ws = self;
    [self dyl_observeObject:self properties:keyPaths withBlock:^(id self, id object, NSString *keyPath, id old, id new) {
        __strong typeof(self)ss = ws;
        observationBlock(ss, keyPath, old, new);
    }];
}

- (void)dyl_observeProperty:(NSString *)keyPath withSelector:(SEL)observationSelector {
    [self dyl_observeObject:self property:keyPath withSelector:observationSelector];
}

- (void)dyl_observeProperties:(NSArray *)keyPaths withSelector:(SEL)observationSelector {
    [self dyl_observeObject:self properties:keyPaths withSelector:observationSelector];
}





#pragma mark Foreign Property

/// Add observation block to appropriate observer.
- (void)dyl_observeObject:(id)object property:(NSString *)keyPath withBlock:(DYLBlockForeignChange)observationBlock {
    DYLObserver *observer = nil;
    @autoreleasepool {
        //! The autoreleasepool ensures the only reference to the DYLObserver is the associated reference.
        observer = [object dyl_observerForKeyPath:keyPath owner:self];
    }
    __weak typeof(self)ws = self;
    [observer addSettingObservationBlock:^(id object, id old, id new) {
        __strong typeof(self)ss = ws;
        observationBlock(ss, object, old, new);
    }];
}

/// Register the block for all given key-paths.
- (void)dyl_observeObject:(id)object properties:(NSArray *)keyPaths withBlock:(DYLBlockForeignChangeMany)observationBlock {
    for (NSString *keyPath in keyPaths) {
        NSString *keyPathCopy = [keyPath copy]; // If some fool uses mutable key-paths
        __weak typeof(self)ws = self;
        [self dyl_observeObject:object property:keyPath withBlock:^(id self, id object, id old , id new){
            __strong typeof(self)ss = ws;
            observationBlock(ss, object, keyPathCopy, old, new);
        }];
    }
}

/// Register block invoking given selector. Smart detecting of number of arguments.
- (void)dyl_observeObject:(id)object property:(NSString *)keyPath withSelector:(SEL)observationSelector {
    NSMethodSignature *signature = [self methodSignatureForSelector:observationSelector];
    NSInteger numberOfArguments = [signature numberOfArguments];
    __weak typeof(self)ws = self;
    [self dyl_observeObject:object property:keyPath withBlock:^(id self, id object, id old, id new) {
        __strong typeof(self)ss = ws;
        switch (numberOfArguments) {
            case 0:
            case 1:
                [NSException raise:NSInternalInconsistencyException format:@"WTF?! Method should have at least two arguments: self and _cmd!"];
                break;
                
            case 2: // +0
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                // -someObjectDidChangeSomething
                [ss performSelector:observationSelector];
                break;
                
            case 3: // +1
                if (self == object) {
                    // -didChangeSomethingTo:
                    [ss performSelector:observationSelector withObject:new]; // Observing self, we dont need self
                }
                else {
                    // -someObjectDidChangeSomething:
                    [ss performSelector:observationSelector withObject:object]; // Observing another object
                }
                break;
                
            case 4: // +2
                if (ss == object) {
                    // -didChangeSomethingFrom:to:
                    [ss performSelector:observationSelector withObject:old withObject:new];
                }
                else {
                    // -someObject: didChangeSomethingTo:
                    [ss performSelector:observationSelector withObject:object withObject:new];
                }
                break;
#pragma clang diagnostic pop
                
            default: {
                // +3
                // -someObject:didChangeSomethingFrom:to:
                void(*msgSend)(id, SEL, id, id, id) = (typeof(msgSend))objc_msgSend;
                msgSend(ss, observationSelector, object, old, new);
                break;
            }
        }
    }];
}

/// Register the selector for each key-path.
- (void)dyl_observeObject:(id)object properties:(NSArray *)keyPaths withSelector:(SEL)observationSelector {
    for (NSString *keyPath in keyPaths) {
        [self dyl_observeObject:object property:keyPath withSelector:observationSelector];
    }
}





#pragma mark Observe Relationships

/// Add observation blocks to appropriate observer. If some block was not specified, use the `changeBlock`.
- (void)dyl_observeRelationship:(NSString *)keyPath
                changeBlock:(DYLBlockChange)changeBlock
             insertionBlock:(DYLBlockInsert)insertionBlock
               removalBlock:(DYLBlockRemove)removalBlock
           replacementBlock:(DYLBlockReplace)replacementBlock
{
    DYLObserver *observer = nil;
    @autoreleasepool {
        //! The autoreleasepool ensures the only reference to the DYLObserver is the associated reference.
        observer = [self dyl_observerForKeyPath:keyPath owner:self];
    }
    __weak typeof(self)ws = self;
    [observer addSettingObservationBlock:changeBlock];
    [observer addInsertionObservationBlock: insertionBlock ?: ^(id self, id new, NSIndexSet *indexes) {
        __strong typeof(self)ss = ws;
        // If no insertion block was specified, call general change block.
        changeBlock(ss, nil, [self valueForKeyPath:keyPath]);
    }];
    [observer addRemovalObservationBlock: removalBlock ?: ^(id self, id old, NSIndexSet *indexes) {
        __strong typeof(self)ss = ws;
        // If no removal block was specified, call general change block.
        changeBlock(ss, nil, [self valueForKeyPath:keyPath]);
    }];
    [observer addReplacementObservationBlock: replacementBlock ?: ^(id self, id old, id new, NSIndexSet *indexes) {
        __strong typeof(self)ss = ws;
        // If no removal block was specified, call general change block.
        changeBlock(ss, nil, [self valueForKeyPath:keyPath]);
    }];
}

/// Call main `-observeRelationship:...` method with only first argument.
- (void)dyl_observeRelationship:(NSString *)keyPath changeBlock:(DYLBlockGeneric)changeBlock {
    [self dyl_observeRelationship:keyPath
                  changeBlock:^(id self, id old, id new) {
                      changeBlock(self, new);
                  }
               insertionBlock:nil
                 removalBlock:nil
             replacementBlock:nil];
}





#pragma mark Map Properties

/// Call `-map:to:transform:` with transform block that uses returns the same value, or null replacement.
- (void)dyl_map:(NSString *)sourceKeyPath to:(NSString *)destinationKeyPath null:(id)nullReplacement {
    [self dyl_map:sourceKeyPath to:destinationKeyPath transform:^id(id value) {
        return value ?: nullReplacement;
    }];
}

/// Observe source key-path and set its new value to destination every time it changes. Use transformation block, if specified.
- (void)dyl_map:(NSString *)sourceKeyPath to:(NSString *)destinationKeyPath transform:(id (^)(id))transformationBlock {
    __weak typeof(self)ws = self;
    [self dyl_observeProperty:sourceKeyPath withBlock:^(id self, id old, id new) {
        __strong typeof(self)ss = ws;
        id transformedValue = (transformationBlock? transformationBlock(new) : new);
        [ss setValue:transformedValue forKeyPath:destinationKeyPath];
    }];
}





#pragma mark Notifications

/// Call another one.
- (void)dyl_observeNotification:(NSString *)name withBlock:(DYLBlockNotify)block {
    [self dyl_observeNotification:name fromObject:nil withBlock:block];
}

/// Add block observer on current operation queue and the resulting internal opaque observe is stored in associated mutable set.
- (void)dyl_observeNotification:(NSString *)name fromObject:(id)object withBlock:(DYLBlockNotify)block {
    // Invoke manually for the first time.
    block(self, nil);
    __weak typeof(self) ws = self;
    id internalObserver = [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                                            object:object
                                                                             queue:[NSOperationQueue currentQueue]
                                                                        usingBlock:^(NSNotification *notification) {
                                                                            __strong typeof(self)ss = ws;
                                                                            block(ss, notification);
                                                                        }];
    [[self dyl_notificationBlockObservers] addObject:internalObserver];
}

/// Make all combination of name and object (if any are given) and call main notification observing method.
- (void)dyl_observeNotifications:(NSArray *)names fromObjects:(NSArray *)objects withBlock:(DYLBlockNotify)block {
    for (NSString *name in names) {
        if (objects) {
            for (id object in objects) {
                [self dyl_observeNotification:name fromObject:object withBlock:block];
            }
        }
        else {
            [self dyl_observeNotification:name fromObject:nil withBlock:block];
        }
    }
}





#pragma Removing

- (void)dyl_removeAllObservations {
    [self internalRemoveAllObservations];
}

/// Called usually from dealloc (may be called at any time). Detach all observers. The associated objects are released once the deallocation process finishes.
- (void)internalRemoveAllObservations {
    // Key-Path Observers
    NSMutableDictionary *keyPathBlockObservers = [self dyl_keyPathBlockObservers];
    for (NSMutableSet *observersForKeyPath in [[self dyl_keyPathBlockObservers] allValues]) {
        [observersForKeyPath makeObjectsPerformSelector:@selector(detach)];
        [observersForKeyPath removeAllObjects];
    }
    [keyPathBlockObservers removeAllObjects];
    
    // NSNotification Observers
    NSMutableSet *notificationObservers = [self dyl_notificationBlockObservers];
    for (id internalObserver in notificationObservers) {
        [[NSNotificationCenter defaultCenter] removeObserver:internalObserver];
    }
    [notificationObservers removeAllObjects];
}

/// Called at any time, tell the observed object to remove our observation blocks.
- (void)dyl_removeAllObservationsOfObject:(id)object {
    [object dyl_removeAllObservationsForOwner:self];
}

/// Called at any time, tell the observed object to remove our observation blocks for given key-path.
- (void)dyl_removeObservationsOfObject:(id)object forKeyPath:(NSString *)keyPath {
    [object dyl_removeObservationsForOwner:self keyPath:keyPath];
}



@end






DYLMappingTransformBlock const DYLMappingIsNilBlock = ^NSNumber *(id value){
    return @( value == nil );
};

DYLMappingTransformBlock const DYLMappingIsNotNilBlock = ^NSNumber *(id value){
    return @( value != nil );
};

DYLMappingTransformBlock const DYLMappingInvertBooleanBlock = ^NSNumber *(NSNumber *value){
    return @( ! value.boolValue );
};

DYLMappingTransformBlock const DYLMappingURLFromStringBlock = ^NSURL *(NSString *value){
    return [NSURL URLWithString:value];
};


