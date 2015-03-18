//
//  KZAlertController.m
//
//  Created by Mike Kasianowicz on 3/17/15.
//  Copyright (c) 2015 Mike Kasianowicz. All rights reserved.
//

#import "KZAlertController.h"

static void *kObserveContext = &kObserveContext;

@protocol KZUIInternalAlertViewDelegate;

@protocol KZUIInternalAlertView <NSObject>
@property (nonatomic) NSString *title;
@property (nonatomic) NSString *message;
@property (nonatomic) NSInteger cancelButtonIndex;
@property (nonatomic, weak) id <KZUIInternalAlertViewDelegate> delegate;

-(NSInteger)addButtonWithTitle:(NSString*)title;
-(void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated;
-(void)showFromViewController:(UIViewController*)viewController;

// action-sheet specific
@property (nonatomic) NSInteger destructiveButtonIndex;

// alert-view specific
@property(nonatomic,assign) UIAlertViewStyle alertViewStyle;
- (UITextField *)textFieldAtIndex:(NSInteger)textFieldIndex;


// update the tint/enabled of the action
-(void)updateAction:(KZUIAlertAction*)action tintColor:(UIColor*)tintColor;

// search for the views and set them on action.view
-(void)populateViewsForActions:(NSArray*)actions fromWindow:(UIWindow*)window;
@end


@protocol KZUIInternalAlertViewDelegate <NSObject>
-(void)alertViewWillAppear:(id<KZUIInternalAlertView>)alertView;
-(void)alertView:(id<KZUIInternalAlertView>)alertView didDismissWithButtonAtIndex:(NSInteger)index;
@end



@interface _KZUIAlertViewController : NSObject <KZUIInternalAlertView, UIAlertViewDelegate>
@end

@interface _KZUIActionSheetController : NSObject <KZUIInternalAlertView, UIActionSheetDelegate>
@end


//MARK: Internals

@interface _KZUIAlertControllerNonTransition : NSObject <UIViewControllerAnimatedTransitioning>
@end

static NSArray *subviewsInView(UIView *view, Class cls);
static void subviewsInViewR(NSMutableArray *subviews, UIView *view, Class cls);
static NSArray *sortedViewArray(NSArray *array);

//MARK: Protected interfaces
@interface KZUIAlertController() <UIViewControllerTransitioningDelegate, KZUIInternalAlertViewDelegate>
@end

@interface KZUIAlertAction ()
@property (nonatomic, copy) void (^handler)(UIAlertAction *);
@property (nonatomic, weak) UIView *view;
@end


//MARK: public class implementations
@implementation KZUIAlertAction
-(instancetype)initWithTitle:(NSString*)title
                       style:(UIAlertActionStyle)style
                     handler:(void (^)(UIAlertAction *action))handler {
    self = [super init];
    if(self) {
        _title = title;
        _style = style;
        self.handler = handler;
        self.enabled = YES;
    }
    return self;
}

+ (instancetype)actionWithTitle:(NSString *)title
                          style:(UIAlertActionStyle)style
                        handler:(void (^)(UIAlertAction *action))handler {
    if([UIDevice currentDevice].systemVersion.intValue > 7) {
        // duck typing is awesome
        return (id)[UIAlertAction actionWithTitle:title style:style handler:handler];
    }
    return [[self alloc] initWithTitle:title
                                 style:style
                               handler:handler];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self.class alloc] initWithTitle:self.title
                                       style:self.style
                                     handler:self.handler];
}

@end






@implementation KZUIAlertController {
    id<KZUIInternalAlertView> _view;

    NSMutableArray *_actions;
    NSMutableArray *_defaultActions;
    NSMutableArray *_cancelActions;

    NSMutableArray *_textFields;
    NSMutableArray *_textFieldConfigurators;

    // save off window tint color before presenting
    UIColor *_tintColor;
}

//MARK: public convenience method
+ (instancetype)alertControllerWithTitle:(NSString *)title
                                 message:(NSString *)message
                          preferredStyle:(UIAlertControllerStyle)preferredStyle {
    if([UIDevice currentDevice].systemVersion.intValue > 7) {
        // duck typing is awesome
        return (id)[UIAlertController alertControllerWithTitle:title message:message preferredStyle:preferredStyle];
    }

    return [[self alloc] initWithTitle:title
                               message:message
                        preferredStyle:preferredStyle];
}

//MARK: protected init
-(instancetype)initWithTitle:(NSString *)title
                     message:(NSString *)message
              preferredStyle:(UIAlertControllerStyle)preferredStyle {
    self = [super init];
    if(self) {

        NSAssert([UIDevice currentDevice].systemVersion.intValue < 8, @"This class does not work on iOS 8 or greater");

        switch(preferredStyle) {
            case UIAlertControllerStyleActionSheet:
                _view = [_KZUIActionSheetController new];
                break;

            case UIAlertControllerStyleAlert:
                _view = [_KZUIAlertViewController new];
                break;

            default:
                [NSException raise:@"KZUIAlertController" format:@"Only action sheet and alert view supported"];
        }

        _view.delegate = self;

        self.title = title;
        self.message = message;
        _preferredStyle = preferredStyle;


        _actions = [NSMutableArray new];

        _defaultActions = [NSMutableArray new];
        _cancelActions = [NSMutableArray new];

        _textFields = [NSMutableArray new];
        _textFieldConfigurators = [NSMutableArray new];

        self.modalPresentationStyle = UIModalPresentationCustom;
        self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        self.transitioningDelegate = self;
    }
    return self;
}

//MARK: view lifecycle
-(void)loadView {
    UIView *view = [UIView new];
    view.backgroundColor = [UIColor clearColor];
    self.view = view;
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // show the alert immediately after this VC is presented
    [self _showAlertView];
}

-(void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // ensure the alert is dismissed immediately when this is dismissed
    [self _forceDismissAlertView:animated];
}

//MARK: public interface
-(void)setTitle:(NSString *)title {
    _view.title = title;
}

-(NSString*)title {
    return _view.title;
}

-(void)setMessage:(NSString *)message {
    _view.message = message;
}

-(NSString*)message {
    return _view.message;
}

-(void)addAction:(UIAlertAction *)action {
    [_actions addObject:action];

    [action addObserver:self
             forKeyPath:@"enabled"
                options:0
                context:kObserveContext];

    NSMutableArray *category;
    switch(action.style) {
        case UIAlertActionStyleDestructive:
        case UIAlertActionStyleDefault:
            category = _defaultActions;
            break;

        case UIAlertActionStyleCancel:
            NSAssert(_cancelActions.count == 0, @"Can only have one cancel action");
            category = _cancelActions;
            break;
    }

    [category addObject:action];
}

-(NSArray*)actions {
    return [_actions copy];
}

-(void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *))configurationHandler {
    [_textFieldConfigurators addObject:configurationHandler ? [configurationHandler copy] : (id)^(UITextField* tf) {}];

    switch(_textFields.count) {
        case 0:
            _view.alertViewStyle = UIAlertViewStylePlainTextInput;
            break;

        case 1:
            _view.alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
            break;

        case 2:
            [NSException raise:@"KZUIAlertController" format:@"More than 2 text fields not supported"];
            break;

    }

    [_textFields removeAllObjects];

    for(int i = 0; i < _textFieldConfigurators.count; i++) {
        UITextField *field = [_view textFieldAtIndex:i];
        field.placeholder = nil;
        field.secureTextEntry = NO;

        configurationHandler = _textFieldConfigurators[i];
        configurationHandler(field);
        [_textFields addObject:field];
    }
}

-(NSArray*)textFields {
    return [_textFields copy];
}


//MARK: helpers
-(void)_showAlertView {
    _tintColor = [UIApplication sharedApplication].keyWindow.tintColor;
    [self _reconstructActions];
    [_view showFromViewController:self.presentingViewController];
}

-(void)_forceDismissAlertView:(BOOL)animated {
    [_view dismissWithClickedButtonIndex:_view.cancelButtonIndex animated:animated];
    _view = nil;
}

-(void)_reconstructActions {
    NSMutableArray *actions = [NSMutableArray new];

    for(UIAlertAction *action in _defaultActions) {
        [actions addObject:action];
        NSInteger index = [_view addButtonWithTitle:action.title];
        if(action.style == UIAlertActionStyleDestructive) {
            _view.destructiveButtonIndex = index;
        }
    }

    for(UIAlertAction *action in _cancelActions) {
        [actions addObject:action];
        _view.cancelButtonIndex = [_view addButtonWithTitle:action.title];
    }

    _actions = actions;
}


//MARK: alert delegate methods
-(void)alertViewWillAppear:(id<KZUIInternalAlertView>)alertView {
    dispatch_queue_t mq = dispatch_get_main_queue();
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;

    dispatch_async(mq, ^{
        [_view populateViewsForActions:_actions
                            fromWindow:keyWindow];

        for(KZUIAlertAction *action in _actions) {
            [_view updateAction:action tintColor:_tintColor];
        }

        dispatch_async(mq, ^{
            keyWindow.tintColor = _tintColor;
        });
    });
}

-(void)alertView:(id<KZUIInternalAlertView>)alertView didDismissWithButtonAtIndex:(NSInteger)index {
    KZUIAlertAction *action = self.actions[index];
    if(action.handler) {
        action.handler((id)action);
    }

    [self.presentingViewController dismissViewControllerAnimated:YES
                                                      completion:nil];
}

//MARK: KVO cleanup
-(void)observeValueForKeyPath:(NSString *)keyPath
                     ofObject:(id)object
                       change:(NSDictionary *)change
                      context:(void *)context {
    if(context != kObserveContext) {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
        return;
    }

    [_view updateAction:object tintColor:_tintColor];
}
-(void)dealloc {
    for(id action in _actions) {
        [action removeObserver:self forKeyPath:@"enabled" context:kObserveContext];
    }
}

//MARK: transitioning hooks
- (id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                   presentingController:(UIViewController *)presenting
                                                                       sourceController:(UIViewController *)source {
    return [_KZUIAlertControllerNonTransition new];
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return [_KZUIAlertControllerNonTransition new];
}

@end





//MARK: Internal stuff
@implementation _KZUIAlertControllerNonTransition
- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext {
    return 0;
}

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext {
    //UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];

    UIView *cv = [transitionContext containerView];

    //[cv addSubview:fromViewController.view];
    [cv addSubview:toViewController.view];

    toViewController.view.frame = cv.bounds;
    [transitionContext completeTransition:YES];
}

@end


static NSArray *subviewsInView(UIView *view, Class cls) {
    NSMutableArray *array = [NSMutableArray new];
    subviewsInViewR(array, view, cls);
    return [array copy];
}

static void subviewsInViewR(NSMutableArray *subviews, UIView *view, Class cls){
    for(UIView *subview in view.subviews) {
        if([subview isKindOfClass:cls]) {
            [subviews addObject:subview];
        } else {
            subviewsInViewR(subviews, subview, cls);
        }
    }
}

static NSArray *sortedViewArray(NSArray *array) {
    return [array sortedArrayUsingComparator:^NSComparisonResult(UIView * obj1, UIView * obj2) {
        UIWindow *window = obj1.window;

        CGPoint point1 = [window convertPoint:obj1.bounds.origin fromView:obj1];
        CGPoint point2 = [window convertPoint:obj2.bounds.origin fromView:obj2];

        NSNumber *val1, *val2;
        if(point1.y == point2.y) {
            val1 = @(point1.x);
            val2 = @(point2.x);
        } else {
            val1 = @(point1.y);
            val2 = @(point2.y);
        }
        return [val1 compare:val2];
    }];
}





@implementation _KZUIAlertViewController {
    UIAlertView *_view;
}
@synthesize delegate=_delegate;

-(instancetype)init {
    self = [super init];
    if(self) {
        _view = [UIAlertView new];
        _view.delegate = self;
    }
    return self;
}

-(void)setTitle:(NSString *)title {
    _view.title = title;
}

-(NSString*)title {
    return _view.title;
}

-(void)setMessage:(NSString *)message {
    _view.message = message;
}

-(NSString*)message {
    return _view.message;
}

-(void)setAlertViewStyle:(UIAlertViewStyle)alertViewStyle {
    _view.alertViewStyle = alertViewStyle;
}

-(UIAlertViewStyle)alertViewStyle {
    return _view.alertViewStyle;
}

-(void)setCancelButtonIndex:(NSInteger)cancelButtonIndex {
    _view.cancelButtonIndex = cancelButtonIndex;
}

-(NSInteger)cancelButtonIndex {
    return _view.cancelButtonIndex;
}

-(void)setDestructiveButtonIndex:(NSInteger)destructiveButtonIndex {
    [NSException raise:@"KZUIAlertController" format:@"Alert view does not support destructive buttons"];
}

-(NSInteger)destructiveButtonIndex {
    return -1;
}

-(NSInteger)addButtonWithTitle:(NSString *)title {
    return [_view addButtonWithTitle:title];
}

-(void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated {
    [_view dismissWithClickedButtonIndex:index
                                     animated:animated];
}

-(void)showFromViewController:(UIViewController *)viewController {
    [_view show];
}

-(UITextField*)textFieldAtIndex:(NSInteger)textFieldIndex {
    return [_view textFieldAtIndex:textFieldIndex];
}

//MARK: delegate methods
-(void)willPresentAlertView:(UIAlertView *)alertView {
    [_delegate alertViewWillAppear:self];
}

-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    [_delegate alertView:self didDismissWithButtonAtIndex:buttonIndex];
}

-(void)updateAction:(KZUIAlertAction*)action tintColor:(UIColor*)tintColor {
    UILabel* label = (id)action.view;
    label.textColor = tintColor;
    label.highlightedTextColor = tintColor;
    label.enabled = action.enabled;
}

-(void)populateViewsForActions:(NSArray*)actions fromWindow:(UIWindow*)window {
    NSArray *tvcs = subviewsInView(window, [UITableViewCell class]);
    tvcs = sortedViewArray(tvcs);

    for(int i = 0; i < tvcs.count; i++) {
        UITableViewCell *cell = tvcs[i];
        KZUIAlertAction *action = actions[i];
        action.view = cell.textLabel;
    }
}
@end









@implementation _KZUIActionSheetController {
    UIActionSheet *_view;
    NSString *_title;
    NSString *_message;
}

@synthesize delegate=_delegate;

-(instancetype)init {
    self = [super init];
    if(self) {
        _view = [UIActionSheet new];
        _view.delegate = self;
    }
    return self;
}

-(void)setTitle:(NSString *)title {
    _view.title = title;
}

-(NSString*)title {
    return _view.title;
}

-(void)setMessage:(NSString *)message {
    _message = message;
    [self _updateTitle];
}

-(NSString*)message {
    return _message;
}

-(void)setAlertViewStyle:(UIAlertViewStyle)alertViewStyle {
    [NSException raise:@"KZUIAlertController" format:@"Action sheet does not support text fields"];
}

-(UIAlertViewStyle)alertViewStyle {
    return UIAlertViewStyleDefault;
}

-(void)setCancelButtonIndex:(NSInteger)cancelButtonIndex {
    _view.cancelButtonIndex = cancelButtonIndex;
}

-(NSInteger)cancelButtonIndex {
    return _view.cancelButtonIndex;
}

-(void)setDestructiveButtonIndex:(NSInteger)destructiveButtonIndex {
    _view.destructiveButtonIndex = destructiveButtonIndex;
}

-(NSInteger)destructiveButtonIndex {
    return _view.destructiveButtonIndex;
}


-(NSInteger)addButtonWithTitle:(NSString *)title {
    return [_view addButtonWithTitle:title];
}

-(void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated {
    [_view dismissWithClickedButtonIndex:index
                                animated:animated];
}

-(void)showFromViewController:(UIViewController *)viewController {
    if([viewController isKindOfClass:[UITabBarController class]]) {
        [_view showFromTabBar:((UITabBarController*)viewController).tabBar];
    } else if([viewController isKindOfClass:[UINavigationController class]]) {
        [_view showFromToolbar:((UINavigationController*)viewController).toolbar];
    } else {
        // TODO: handle popovers on iPad
        [_view showInView:viewController.view];
    }
}

-(UITextField*)textFieldAtIndex:(NSInteger)textFieldIndex {
    return nil;
}


-(void)_updateTitle {
    _view.title = [NSString stringWithFormat:@"%@\n\n%@", _title, _message];
}

//MARK: delegate methods
-(void)willPresentActionSheet:(UIActionSheet *)actionSheet {
    [_delegate alertViewWillAppear:self];
}

-(void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    [_delegate alertView:self didDismissWithButtonAtIndex:buttonIndex];
}

-(void)updateAction:(KZUIAlertAction*)action tintColor:(UIColor*)tintColor {
    UIButton *button = (id)action.view;
    button.enabled = action.enabled;
    UIColor *textColor = UIAlertActionStyleDestructive ? [UIColor redColor] : tintColor;

    [button setTitleColor:textColor
                 forState:UIControlStateNormal];
    [button setTitleColor:textColor
                 forState:UIControlStateHighlighted];
    [button setTitleColor:[UIColor grayColor]
                 forState:UIControlStateDisabled];
}

-(void)populateViewsForActions:(NSArray*)actions fromWindow:(UIWindow*)window {
    NSArray *buttons = subviewsInView(window, [UIButton class]);
    buttons = sortedViewArray(buttons);

    for(int i = 0; i < buttons.count; i++) {
        UIButton *button = buttons[i];
        KZUIAlertAction *action = actions[i];
        action.view = button;
    }
}

@end
