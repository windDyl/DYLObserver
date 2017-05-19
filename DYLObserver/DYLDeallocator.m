//
//  DYLDeallocator.m
//  Block Key-Value Observing
//
//  Created by Martin Kiss on 21.11.15.
//  Copyright © 2015 iMartin Kiss. All rights reserved.
//

#import "DYLDeallocator.h"
#import <objc/runtime.h>



@interface DYLDeallocator : NSObject

@property (readonly, unsafe_unretained) NSObject *owner;
@property (readonly) NSMutableArray<DYLDeallocatorCallback> *callbacks;

@end



@implementation DYLDeallocator


- (instancetype)initWithOwner:(NSObject*)owner {
    self = [super init];
    if (self) {
        self->_owner = owner;
        self->_callbacks = [NSMutableArray new];
    }
    return self;
}


- (void)addCallback:(DYLDeallocatorCallback)block {
    if (block)
        [self->_callbacks addObject:block];
}


- (void)invokeCallbacks {
    NSArray<DYLDeallocatorCallback> *blocks = self->_callbacks;
    self->_callbacks = nil;
    
    __unsafe_unretained NSObject *owner = self->_owner;
    for (DYLDeallocatorCallback block in blocks) {
        block(owner);
    }
}


- (void)dealloc {
    [self invokeCallbacks];
}


@end



@implementation NSObject (DYLDeallocator)


static const void * DYLDeallocatorAssociationKey = &DYLDeallocatorAssociationKey;


- (void)dyl_addDeallocationCallback:(DYLDeallocatorCallback)block {
    @synchronized(self) {
        @autoreleasepool {
            DYLDeallocator *deallocator = objc_getAssociatedObject(self, DYLDeallocatorAssociationKey);
            if ( ! deallocator) {
                deallocator = [[DYLDeallocator alloc] initWithOwner:self];
                objc_setAssociatedObject(self, DYLDeallocatorAssociationKey, deallocator, OBJC_ASSOCIATION_RETAIN);
            }
            [self.class swizzleDeallocIfNeeded];
            [deallocator addCallback:block];
        }
    }
}


+ (BOOL)swizzleDeallocIfNeeded {
    static NSMutableSet *swizzledClasses = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzledClasses = [[NSMutableSet alloc] init];
    });
    
    @synchronized(self) {
        if ([swizzledClasses containsObject:self]) return NO;
        
        SEL deallocSelector = NSSelectorFromString(@"dealloc");
        Method dealloc = class_getInstanceMethod(self, deallocSelector);
        
        void (*oldImplementation)(id, SEL) = (typeof(oldImplementation))method_getImplementation(dealloc);
        void(^newDeallocBlock)(id) = ^(__unsafe_unretained NSObject *self_deallocating) {
            
            // New dealloc implementation:
            DYLDeallocator *decomposer = objc_getAssociatedObject(self_deallocating, DYLDeallocatorAssociationKey);
            [decomposer invokeCallbacks];
            
            // Calling existing implementation.
            oldImplementation(self_deallocating, deallocSelector);
        };
        IMP newImplementation = imp_implementationWithBlock(newDeallocBlock);
        
        class_replaceMethod(self, deallocSelector, newImplementation, method_getTypeEncoding(dealloc));
        
        [swizzledClasses addObject:self];
        
        return YES;
    }
}



@end


