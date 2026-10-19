#import "KWClassicAppearance.h"
#import <UIKit/UIKit.h>

static UIImage *KWGradientImage(CGSize size, const CGFloat *colors, size_t stops, BOOL rounded)
{
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, stops);
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    if (rounded) {
        UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:5.0];
        [clip addClip];
    }
    CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(0, size.height), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:0.18 alpha:0.75].CGColor);
    CGContextSetLineWidth(context, 1.0);
    CGRect border = CGRectInset(bounds, 0.5, 0.5);
    if (rounded) {
        [[UIBezierPath bezierPathWithRoundedRect:border cornerRadius:5.0] stroke];
    } else {
        CGContextMoveToPoint(context, 0, size.height - 0.5);
        CGContextAddLineToPoint(context, size.width, size.height - 0.5);
        CGContextStrokePath(context);
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIImage *KWButtonImage(BOOL highlighted)
{
    static const CGFloat normal[] = {
        0.64, 0.75, 0.90, 1.0,
        0.37, 0.53, 0.72, 1.0
    };
    static const CGFloat pressed[] = {
        0.30, 0.46, 0.67, 1.0,
        0.22, 0.36, 0.55, 1.0
    };
    UIImage *image = KWGradientImage(CGSizeMake(64, 32), highlighted ? pressed : normal, 2, YES);
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 8, 0, 8)];
}

static UIImage *KWSearchFieldImage(void)
{
    static const CGFloat colors[] = {
        1.0, 1.0, 1.0, 1.0,
        0.91, 0.92, 0.94, 1.0
    };
    UIImage *image = KWGradientImage(CGSizeMake(48, 28), colors, 2, YES);
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 8, 0, 8)];
}

@implementation KWClassicAppearance

+ (void)apply
{
    NSString *version = [UIDevice currentDevice].systemVersion;
    if ([version compare:@"7.0" options:NSNumericSearch] == NSOrderedAscending) return;

    static const CGFloat blueBar[] = {
        0.57, 0.67, 0.82, 1.0,
        0.39, 0.53, 0.72, 1.0,
        0.27, 0.41, 0.60, 1.0
    };
    static const CGFloat searchBar[] = {
        0.96, 0.96, 0.96, 1.0,
        0.83, 0.84, 0.86, 1.0
    };

    UIImage *barImage = [KWGradientImage(CGSizeMake(1, 44), blueBar, 3, NO)
                         resizableImageWithCapInsets:UIEdgeInsetsMake(1, 0, 1, 0)];
    UIImage *toolbarImage = [KWGradientImage(CGSizeMake(1, 44), blueBar, 3, NO)
                             resizableImageWithCapInsets:UIEdgeInsetsMake(1, 0, 1, 0)];
    UIImage *searchImage = [KWGradientImage(CGSizeMake(1, 44), searchBar, 2, NO)
                            resizableImageWithCapInsets:UIEdgeInsetsMake(1, 0, 1, 0)];

    NSShadow *titleShadow = [[NSShadow alloc] init];
    titleShadow.shadowColor = [UIColor colorWithWhite:0.12 alpha:0.8];
    titleShadow.shadowOffset = CGSizeMake(0, -1);
    NSDictionary *titleAttributes = @{
        NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Bold" size:20],
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSShadowAttributeName: titleShadow
    };

    [[UINavigationBar appearance] setBackgroundImage:barImage forBarMetrics:UIBarMetricsDefault];
    [[UINavigationBar appearance] setBackgroundImage:barImage forBarMetrics:UIBarMetricsLandscapePhone];
    [[UINavigationBar appearance] setShadowImage:nil];
    [[UINavigationBar appearance] setTitleTextAttributes:titleAttributes];

    [[UIToolbar appearance] setBackgroundImage:toolbarImage
                             forToolbarPosition:UIToolbarPositionAny
                                     barMetrics:UIBarMetricsDefault];
    [[UIToolbar appearance] setTintColor:[UIColor whiteColor]];

    NSShadow *buttonShadow = [[NSShadow alloc] init];
    buttonShadow.shadowColor = [UIColor colorWithWhite:0.12 alpha:0.8];
    buttonShadow.shadowOffset = CGSizeMake(0, -1);
    NSDictionary *buttonTitle = @{
        NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Bold" size:13],
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSShadowAttributeName: buttonShadow
    };
    [[UIBarButtonItem appearance] setTitleTextAttributes:buttonTitle forState:UIControlStateNormal];
    [[UIBarButtonItem appearance] setTitleTextAttributes:buttonTitle forState:UIControlStateHighlighted];
    [[UIBarButtonItem appearance] setBackgroundImage:KWButtonImage(NO)
                                            forState:UIControlStateNormal
                                          barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setBackgroundImage:KWButtonImage(YES)
                                            forState:UIControlStateHighlighted
                                          barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setBackButtonBackgroundImage:KWButtonImage(NO)
                                                      forState:UIControlStateNormal
                                                    barMetrics:UIBarMetricsDefault];

    [[UISearchBar appearance] setBackgroundImage:searchImage];
    [[UISearchBar appearance] setSearchFieldBackgroundImage:KWSearchFieldImage() forState:UIControlStateNormal];
    [[UISearchBar appearance] setTranslucent:NO];
    [[UITableView appearance] setSeparatorColor:[UIColor colorWithRed:0.78 green:0.78 blue:0.80 alpha:1.0]];
}

@end
