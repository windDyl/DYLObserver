//
//  DYLDeallocator.h
//  Block Key-Value Observing
//
//  Created by Martin Kiss on 21.11.15.
//  Copyright © 2015 iMartin Kiss. All rights reserved.
//

#import <Foundation/Foundation.h>



typedef void(^DYLDeallocatorCallback)(id receiver);



@interface NSObject (DYLDeallocator)

- (void)dyl_addDeallocationCallback:(DYLDeallocatorCallback)block;

@end


