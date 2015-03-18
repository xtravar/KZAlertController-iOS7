//
//  KZAlertController.h
//
//  Created by Mike Kasianowicz on 3/17/15.
//  Copyright (c) 2015 Mike Kasianowicz. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface KZUIAlertAction : NSObject <NSCopying>

+ (id)actionWithTitle:(NSString *)title
                style:(UIAlertActionStyle)style
              handler:(void (^)(UIAlertAction *action))handler;

@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) UIAlertActionStyle style;
@property (nonatomic, getter=isEnabled) BOOL enabled;

@end



@interface KZUIAlertController : UIViewController
+ (id)alertControllerWithTitle:(NSString *)title
                       message:(NSString *)message
                preferredStyle:(UIAlertControllerStyle)preferredStyle;

- (void)addAction:(KZUIAlertAction *)action;
@property (nonatomic, readonly) NSArray *actions;
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *textField))configurationHandler;
@property (nonatomic, readonly) NSArray *textFields;

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;

@property (nonatomic, readonly) UIAlertControllerStyle preferredStyle;

@end


