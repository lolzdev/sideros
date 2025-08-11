#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>

static NSWindow *window = nil;
static bool window_closed = false;

@interface WindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation WindowDelegate
- (void)windowWillClose:(NSNotification *)notification {
  window_closed = true;
}
@end

static WindowDelegate *window_delegate = nil;

@interface MetalView : NSView
@end

@implementation MetalView
+ (Class)layerClass {
  return [CAMetalLayer class];
}
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    self.layer = [CAMetalLayer layer];
  }
  return self;
}
@end

static MetalView *metal_view = nil;

static void initialize_app(void) {
  static BOOL initialized = NO;
  if (!initialized) {
    [NSApplication sharedApplication];
    initialized = YES;
  }
}

void create_window(void) {
  initialize_app();
  window_closed = false;
  if (window != nil) {
    [window makeKeyAndOrderFront:nil];
    return;
  }

  NSRect frame = NSMakeRect(100, 100, 800, 600);

  window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskResizable)
                  backing:NSBackingStoreBuffered
                    defer:NO];

  [window setTitle:@"Sideros"];

  metal_view = [[MetalView alloc] initWithFrame:frame];
  [window setContentView:metal_view];
  NSLog(@"Layer class: %@", NSStringFromClass([metal_view.layer class]));

  window_delegate = [[WindowDelegate alloc] init];
  [window setDelegate:window_delegate];

  [window makeKeyAndOrderFront:nil];
  [window orderFrontRegardless];
}

void poll_cocoa_events(void) {
  @autoreleasepool {
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:[NSDate distantPast]
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES])) {
      [NSApp sendEvent:event];
    }
  }
}

bool is_window_closed(void) { return window_closed; }
void *get_metal_layer(void) { return (__bridge void *)metal_view.layer; }
