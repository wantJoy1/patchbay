#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <sys/stat.h>
#include "moonbit.h"

typedef moonbit_bytes_t (*patchbay_handler)(moonbit_bytes_t);

static patchbay_handler handler;
static WKWebView *web;

static moonbit_bytes_t to_bytes(NSString *s) {
  NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)d.length, 0);
  memcpy(b, d.bytes, d.length);
  return b;
}

static NSString *from_bytes(moonbit_bytes_t b) {
  return [[NSString alloc] initWithBytes:b length:Moonbit_array_length(b) encoding:NSUTF8StringEncoding];
}

@interface PatchbayHost : NSObject <NSApplicationDelegate, WKScriptMessageHandler>
@end

@implementation PatchbayHost
- (void)userContentController:(WKUserContentController *)c didReceiveScriptMessage:(WKScriptMessage *)message {
  moonbit_bytes_t frame = handler(to_bytes(message.body));
  [web evaluateJavaScript:[NSString stringWithFormat:@"patchbay.receive(%@)", from_bytes(frame)] completionHandler:nil];
  moonbit_decref(frame);
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
  return YES;
}
@end

static NSMenuItem *submenu(NSString *title, NSArray *items) {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
  for (NSArray *i in items) {
    [menu addItemWithTitle:i[0] action:NSSelectorFromString(i[1]) keyEquivalent:i[2]];
  }
  NSMenuItem *item = [NSMenuItem new];
  item.submenu = menu;
  return item;
}

// Why not drive the window through accessibility or screen capture during
// development: both need permissions the terminal may not have. Lines written
// to the FIFO `$PATCHBAY_DEV_DIR/in` are evaluated as JavaScript, or `snapshot
// PATH` saves a PNG; results are appended to `$PATCHBAY_DEV_DIR/out`.
static void dev_channel(void) {
  NSString *dir = NSProcessInfo.processInfo.environment[@"PATCHBAY_DEV_DIR"];
  if (!dir) return;
  NSString *in = [dir stringByAppendingPathComponent:@"in"];
  NSString *out = [dir stringByAppendingPathComponent:@"out"];
  unlink(in.UTF8String);
  mkfifo(in.UTF8String, 0600);
  [NSFileManager.defaultManager createFileAtPath:out contents:nil attributes:nil];
  void (^append)(NSString *) = ^(NSString *text) {
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:out];
    [h seekToEndOfFile];
    [h writeData:[[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
  };
  [NSThread detachNewThreadWithBlock:^{
    for (;;) {
      NSFileHandle *fifo = [NSFileHandle fileHandleForReadingAtPath:in];
      NSString *text = [[NSString alloc] initWithData:[fifo readDataToEndOfFile] encoding:NSUTF8StringEncoding];
      [fifo closeFile];
      for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (line.length == 0) continue;
        dispatch_async(dispatch_get_main_queue(), ^{
          if ([line hasPrefix:@"snapshot "]) {
            [web takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *e) {
              NSString *path = [line substringFromIndex:9];
              NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
              [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
              append(path);
            }];
          } else {
            [web evaluateJavaScript:line completionHandler:^(id result, NSError *e) {
              append(e ? e.localizedDescription : [NSString stringWithFormat:@"%@", result]);
            }];
          }
        });
      }
    }
  }];
}

MOONBIT_FFI_EXPORT void patchbay_set_clipboard(moonbit_bytes_t text) {
  [NSPasteboard.generalPasteboard clearContents];
  [NSPasteboard.generalPasteboard setString:from_bytes(text) forType:NSPasteboardTypeString];
}

MOONBIT_FFI_EXPORT void patchbay_open_url(moonbit_bytes_t url) {
  [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:from_bytes(url)]];
}

MOONBIT_FFI_EXPORT void patchbay_run(moonbit_bytes_t page, patchbay_handler h) {
  handler = h;
  NSApplication *app = NSApplication.sharedApplication;
  app.activationPolicy = NSApplicationActivationPolicyRegular;
  PatchbayHost *host = [PatchbayHost new];
  app.delegate = host;
  NSMenu *bar = [NSMenu new];
  [bar addItem:submenu(@"patchbay", @[@[@"patchbay を終了", @"terminate:", @"q"]])];
  [bar addItem:submenu(@"編集", @[
    @[@"取り消す", @"undo:", @"z"], @[@"やり直す", @"redo:", @"Z"], @[@"カット", @"cut:", @"x"],
    @[@"コピー", @"copy:", @"c"], @[@"ペースト", @"paste:", @"v"], @[@"すべてを選択", @"selectAll:", @"a"],
  ])];
  app.mainMenu = bar;
  WKWebViewConfiguration *config = [WKWebViewConfiguration new];
  [config.userContentController addScriptMessageHandler:host name:@"patchbay"];
  web = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 780)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
    backing:NSBackingStoreBuffered defer:NO];
  window.title = @"patchbay";
  window.contentView = web;
  [window center];
  [window makeKeyAndOrderFront:nil];
  [web loadHTMLString:from_bytes(page) baseURL:nil];
  dev_channel();
  [app activateIgnoringOtherApps:YES];
  [app run];
}
