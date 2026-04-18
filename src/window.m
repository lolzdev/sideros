#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import "sideros_api.h"

static NSWindow *window = nil;
static bool window_closed = false;

static unsigned int map_modifier_key(unsigned short key_code) {
  switch (key_code) {
  case 56:
    return 340;
  case 59:
    return 341;
  case 58:
    return 342;
  case 55:
    return 343;
  case 60:
    return 344;
  case 62:
    return 345;
  case 61:
    return 346;
  case 54:
    return 347;
  case 57:
    return 280;
  default:
    return 0;
  }
}

static unsigned int map_special_key(unsigned short key_code) {
  switch (key_code) {
  case 36:
    return 257;
  case 48:
    return 258;
  case 51:
    return 259;
  case 53:
    return 256;
  case 115:
    return 268;
  case 116:
    return 266;
  case 117:
    return 261;
  case 119:
    return 269;
  case 121:
    return 267;
  case 123:
    return 263;
  case 124:
    return 262;
  case 125:
    return 264;
  case 126:
    return 265;
  default:
    return map_modifier_key(key_code);
  }
}

static unsigned int map_character_key(NSString *characters) {
  if (characters.length == 0) {
    return 0;
  }

  unichar ch = [characters characterAtIndex:0];
  switch (ch) {
  case NSCarriageReturnCharacter:
  case NSEnterCharacter:
    return 257;
  case NSBackspaceCharacter:
  case NSDeleteCharacter:
    return 259;
  case NSTabCharacter:
  case NSBackTabCharacter:
    return 258;
  case 0x1B:
    return 256;
  case NSUpArrowFunctionKey:
    return 265;
  case NSDownArrowFunctionKey:
    return 264;
  case NSLeftArrowFunctionKey:
    return 263;
  case NSRightArrowFunctionKey:
    return 262;
  case NSF1FunctionKey:
    return 290;
  case NSF2FunctionKey:
    return 291;
  case NSF3FunctionKey:
    return 292;
  case NSF4FunctionKey:
    return 293;
  case NSF5FunctionKey:
    return 294;
  case NSF6FunctionKey:
    return 295;
  case NSF7FunctionKey:
    return 296;
  case NSF8FunctionKey:
    return 297;
  case NSF9FunctionKey:
    return 298;
  case NSF10FunctionKey:
    return 299;
  case NSF11FunctionKey:
    return 300;
  case NSF12FunctionKey:
    return 301;
  default:
    if (ch < 128) {
      if (ch >= 'A' && ch <= 'Z') {
        ch = (unichar)(ch - 'A' + 'a');
      }
      return (unsigned int)ch;
    }
    return 0;
  }
}

static unsigned int map_key_event(NSEvent *event) {
  unsigned int key = map_special_key(event.keyCode);
  if (key != 0) {
    return key;
  }

  NSString *characters = event.charactersIgnoringModifiers;
  return map_character_key(characters);
}

static void dispatch_key_event(NSEvent *event, bool release) {
  unsigned int key = map_key_event(event);
  if (key != 0) {
    sideros_key_callback(key, release);
  }
}

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

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window != nil) {
    [self.window makeFirstResponder:self];
  }
}

- (void)keyDown:(NSEvent *)event {
  dispatch_key_event(event, false);
}

- (void)keyUp:(NSEvent *)event {
  dispatch_key_event(event, true);
}

- (void)flagsChanged:(NSEvent *)event {
  unsigned int key = map_modifier_key(event.keyCode);
  if (key == 0) {
    return;
  }

  NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  bool pressed = false;

  switch (event.keyCode) {
  case 55:
  case 54:
    pressed = (flags & NSEventModifierFlagCommand) != 0;
    break;
  case 56:
  case 60:
    pressed = (flags & NSEventModifierFlagShift) != 0;
    break;
  case 59:
  case 62:
    pressed = (flags & NSEventModifierFlagControl) != 0;
    break;
  case 58:
  case 61:
    pressed = (flags & NSEventModifierFlagOption) != 0;
    break;
  case 57:
    pressed = (flags & NSEventModifierFlagCapsLock) != 0;
    break;
  default:
    break;
  }

  sideros_key_callback(key, !pressed);
}

- (void)scrollWheel:(NSEvent *)event {
  if (event.scrollingDeltaY > 0) {
    sideros_scroll_callback(true);
  } else if (event.scrollingDeltaY < 0) {
    sideros_scroll_callback(false);
  }
}
@end

static MetalView *metal_view = nil;

static void initialize_app(void) {
  static BOOL initialized = NO;
  if (!initialized) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];
    initialized = YES;
  }
}

void create_window(void) {
  initialize_app();
  window_closed = false;
  if (window != nil) {
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    [window makeMainWindow];
    [window makeFirstResponder:metal_view];
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

  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:nil];
  [window makeMainWindow];
  [window orderFrontRegardless];
  [window makeFirstResponder:metal_view];
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
