# KZAlertController-iOS7
This class allows you to code against UIAlertController APIs, but still support iOS 7.  The only difference between the SDK8 API and this is that you must allocate with 'KZUI' classes.

Not a whole lot of testing has been done yet, so I'm sure there are scenarios that aren't supported well.

Example code:
```
UIAlertController *ac = [KZUIAlertController alertControllerWithTitle:@"Title"
                                                              message:@"Message"
                                                       preferredStyle:UIAlertControllerStyleAlert];
                                                       
UIAlertAction *action = [KZUIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
                                                          NSLog(@"God bless Objective-C");
                                                 }];
                                                       
 ```
