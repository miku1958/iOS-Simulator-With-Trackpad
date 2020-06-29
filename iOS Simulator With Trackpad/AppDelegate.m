//
//  AppDelegate.m
//  iOS Simulator With Trackpad
//
//  Created by 庄黛淳华 on 2020/2/4.
//  Copyright © 2020 庄黛淳华. All rights reserved.
//

#import "AppDelegate.h"

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef eventRef, AppDelegate *appDelegate);

#ifdef DEBUG
#define NSLog(...) printf("%s", [NSString stringWithFormat:__VA_ARGS__].UTF8String);printf("\n");
#else
#define NSLog(...)
#endif


@interface AppDelegate ()
@property (nonatomic, assign) BOOL eventTapEnabled;
@property (nonatomic, strong) NSRunningApplication *targetApplication;
@property (nonatomic, assign) CFMachPortRef portRef;
@property (nonatomic, assign) CFRunLoopSourceRef runLoopSourceRef;
@property (nonatomic, assign) CGRect topSimulatorWindowBounds;
@property (nonatomic, assign) CGPoint beginScrollPosition;
@property (nonatomic, assign) CGPoint currentScrollPosition;

@property (nullable, nonatomic, strong) NSStatusItem *item;

@property (nonatomic, strong) NSArray<NSString *> *targetBundleIdentifiers;
@end

@interface AppDelegate (Active)
- (void)workspaceDidActivateApplication:(NSNotification *)notification;
@end
@interface AppDelegate (StatusBar)
@property (nonatomic, assign) BOOL replaceScrollAction;
@property (nonatomic, assign) BOOL showRealMouseCursor;
- (void)addStatusBar;
@end

@interface AppDelegate (Application)
- (void)updateTargetApplicationBounds;
@end
@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[NSWorkspace.sharedWorkspace.notificationCenter addObserver: self selector: @selector(workspaceDidActivateApplication:) name: NSWorkspaceDidActivateApplicationNotification object: nil];
//	NSWindowDidResizeNotification
	[self addStatusBar];
	_targetBundleIdentifiers = @[
		@"com.apple.iphonesimulator"
	];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSApplication.sharedApplication.keyWindow orderOut:self];
		for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
			if ([self.targetBundleIdentifiers containsObject: app.bundleIdentifier]) {
				[NSWorkspace.sharedWorkspace launchAppWithBundleIdentifier: app.bundleIdentifier options:NSWorkspaceLaunchDefault additionalEventParamDescriptor: nil launchIdentifier: nil];
			}
		}
	});
}
@end

@implementation AppDelegate (StatusBar)
- (void)addStatusBar {
	_item = [[NSStatusBar systemStatusBar] statusItemWithLength: NSSquareStatusItemLength];
	[_item.button setTitle: @"S"];
	_item.menu = [[NSMenu alloc]initWithTitle: @"menu"];
	
	
	NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle: @"quit" action:@selector(terminate:) keyEquivalent: @""];
	quit.target = self;
	[_item.menu addItem: quit];
	
	
	NSMenuItem *replaceScrollAction = [[NSMenuItem alloc] initWithTitle: self.replaceScrollAction ? @"replaceScrollAction ☑️" : @"replaceScrollAction" action:@selector(switchReplaceScrollAction:) keyEquivalent: @""];
	replaceScrollAction.target = self;
	[_item.menu addItem: replaceScrollAction];
	
	
	
	NSMenuItem *showRealMouseCursor = [[NSMenuItem alloc] initWithTitle: self.showRealMouseCursor ? @"showRealMouseCursor ☑️" : @"showRealMouseCursor" action:@selector(switchShowRealMouseCursor:) keyEquivalent: @""];
	showRealMouseCursor.target = self;
	[_item.menu addItem: showRealMouseCursor];
}
- (NSString *)KeyForSelector:(SEL)selector {
	return [NSString stringWithFormat: @"%@-%@", _targetApplication.bundleIdentifier, NSStringFromSelector(selector)];
}
- (void)terminate:(id)sender {
    [NSApp terminate:sender];
}
- (void)switchReplaceScrollAction:(NSMenuItem *)item {
	self.replaceScrollAction = !self.replaceScrollAction;
	item.title = self.replaceScrollAction ? @"replaceScrollAction ☑️" : @"replaceScrollAction";
}

- (void)switchShowRealMouseCursor:(NSMenuItem *)item {
	self.showRealMouseCursor = !self.showRealMouseCursor;
	item.title = self.showRealMouseCursor ? @"showRealMouseCursor ☑️" : @"showRealMouseCursor";
}
- (BOOL)replaceScrollAction {
	return [NSUserDefaults.standardUserDefaults boolForKey: [self KeyForSelector: @selector(replaceScrollAction)]];
}
- (void)setReplaceScrollAction:(BOOL)replaceScrollAction {
	[NSUserDefaults.standardUserDefaults setBool: replaceScrollAction forKey: [self KeyForSelector: @selector(replaceScrollAction)]];
}

- (BOOL)showRealMouseCursor {
	return [NSUserDefaults.standardUserDefaults boolForKey: [self KeyForSelector: @selector(showRealMouseCursor)]];
}
- (void)setShowRealMouseCursor:(BOOL)showRealMouseCursor {
	[NSUserDefaults.standardUserDefaults setBool: showRealMouseCursor forKey: [self KeyForSelector: @selector(showRealMouseCursor)]];
}
@end

@implementation AppDelegate (Active)

- (void)workspaceDidActivateApplication:(NSNotification *)notification {
    [self didActivateApplication:[[notification userInfo] objectForKey:NSWorkspaceApplicationKey]];
}
- (void)didActivateApplication:(NSRunningApplication *)application {
	
    _targetApplication = [_targetBundleIdentifiers containsObject: application.bundleIdentifier] ? application : nil;
	if (_targetApplication != nil) {
		[self updateTargetApplicationBounds];
	}
	self.eventTapEnabled = _targetApplication != nil;
}
@end

@implementation AppDelegate (Property)

- (void)setEventTapEnabled:(BOOL)eventTapEnabled{
//    [targetApplicationActivateMenuItem setAction:(eventTapEnabled ? nil : @selector(activateTargetApplication:))];
    
    if(eventTapEnabled != _eventTapEnabled) {
        if(eventTapEnabled) {
			CGEventMask event = NSEventMaskScrollWheel;
			
			//第四个参数, 要么CGEventMaskBit(CGEventType), 要么直接传NSEventMask
			
			_portRef = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault, event, (CGEventTapCallBack)eventTapCallback, (__bridge void * _Nullable)(self));
			if (_portRef == nil) {
				return;
			}
			_runLoopSourceRef = CFMachPortCreateRunLoopSource(NULL, _portRef, 0);
			CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSourceRef, kCFRunLoopCommonModes);
        } else if(_runLoopSourceRef != nil && CFRunLoopContainsSource(CFRunLoopGetMain(), _runLoopSourceRef, kCFRunLoopCommonModes)) {
			CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSourceRef, kCFRunLoopCommonModes);
            
			if(_portRef != nil)
            {
				CFMachPortInvalidate(_portRef);
				CFRelease(_portRef);
				_portRef = nil;
            }
            
			if(_runLoopSourceRef != nil)
            {
				CFRelease(_runLoopSourceRef);
				_runLoopSourceRef = nil;
            }
        }
        
        _eventTapEnabled = eventTapEnabled;
    }
}

@end

@implementation AppDelegate (Application)
- (void)updateTargetApplicationBounds {
	NSArray *windowInfoList = (__bridge_transfer NSArray *)CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
	CGRect rect = CGRectZero;
	for(NSDictionary *windowInfo in windowInfoList) {
		if([[windowInfo valueForKey:(NSString *)kCGWindowOwnerPID] intValue] == _targetApplication.processIdentifier) {
			CGRect current;;
			CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)[windowInfo valueForKey:(NSString *)kCGWindowBounds], &current);
			if (rect.size.height < current.size.height) {
				rect = current;
			}
		}
	}
	_topSimulatorWindowBounds = rect;
}

@end

@implementation AppDelegate (Event)

- (void)sendMouseEvent:(CGEventType)eventType atPosition:(CGPoint)position {
	CGEventRef eventRef = CGEventCreateMouseEvent(NULL, eventType, position, 0);
	CGEventPost(kCGHIDEventTap, eventRef);
	if (!self.showRealMouseCursor) {
		CGWarpMouseCursorPosition(_beginScrollPosition);
	}
}
@end

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef eventRef, AppDelegate *appDelegate) {
	__auto_type end = ^CGEventRef() {
		if (CGPointEqualToPoint(appDelegate.currentScrollPosition, CGPointZero)) {
			return eventRef;
		}

		if (appDelegate.topSimulatorWindowBounds.size.width <= 0 || appDelegate.topSimulatorWindowBounds.size.height <= 0) {
			return eventRef;
		}
		NSLog(@"end");
		[appDelegate sendMouseEvent: kCGEventLeftMouseUp atPosition: appDelegate.currentScrollPosition];
		appDelegate.currentScrollPosition = CGPointZero;
		[appDelegate sendMouseEvent: kCGEventMouseMoved atPosition: appDelegate.beginScrollPosition];
		return eventRef;
	};
	
	// 这里不能断点, 否则用NSEvent eventWithCGEvfent时内部的NSEvent会闪退
    NSEvent *event = [NSEvent eventWithCGEvent: eventRef];
//	NSLog(@"event: %@", event);
	
	CGEventType eventType;
	
	if (event.phase == NSEventPhaseBegan) {
		NSLog(@"NSEventMaskBeginGesture");
		eventType = kCGEventLeftMouseDown;
		appDelegate.beginScrollPosition =
		CGPointMake(event.locationInWindow.x, CGRectGetMaxY(NSScreen.mainScreen.frame) - event.locationInWindow.y);
		appDelegate.currentScrollPosition = appDelegate.beginScrollPosition;
	} else if (event.phase == NSEventPhaseEnded) {
		NSLog(@"NSEventMaskEndGesture");
		return end();
	} else {
		NSLog(@"NSEventMaskScrollWheel");
		eventType = kCGEventLeftMouseDragged;
	}
	if (appDelegate.topSimulatorWindowBounds.size.width <= 0 || appDelegate.topSimulatorWindowBounds.size.height <= 0) {
		return eventRef;
	}

	NSLog(@"NSEventMask \n");
	CGPoint position = appDelegate.currentScrollPosition;
	position.x += event.scrollingDeltaX;
	position.y += event.scrollingDeltaY;

	NSLog(@"position.x: %@", @(position));
	if (position.x > CGRectGetMaxX(appDelegate.topSimulatorWindowBounds)) {
		NSLog(@"position.x > CGRectGetMaxX(appDelegate.topSimulatorWindowBounds)");
		return eventRef;
	}
	if (position.y > CGRectGetMaxY(appDelegate.topSimulatorWindowBounds)) {
		NSLog(@"position.y > CGRectGetMaxY(appDelegate.topSimulatorWindowBounds)");
		return eventRef;
	}
	if (position.x < appDelegate.topSimulatorWindowBounds.origin.x) {
		NSLog(@"position.x < appDelegate.topSimulatorWindowBounds.origin.x");
		return eventRef;
	}
	if (position.y < appDelegate.topSimulatorWindowBounds.origin.y) {
		NSLog(@"position.y < appDelegate.topSimulatorWindowBounds.origin.y");
		return eventRef;
	}
	
	appDelegate.currentScrollPosition = position;
	NSLog(@"Delta event.scrollingDeltaX: %@", @(event.scrollingDeltaX));
	NSLog(@"Delta event.scrollingDeltaY: %@", @(event.scrollingDeltaY));
	NSLog(@"Delta event.deltaX: %@", @(event.deltaX));
	NSLog(@"Delta event.deltaY: %@", @(event.deltaY));
	NSLog(@"Delta \n");
	NSLog(@"Location NSScreen.mainScreen.frame: %@", @(NSScreen.mainScreen.frame));
	NSLog(@"Location event.locationInWindow: %@", @(event.locationInWindow));
	NSLog(@"Location NSEvent.mouseLocation: %@", @(NSEvent.mouseLocation));
	NSLog(@"Location appDelegate.topSimulatorWindowBounds: %@", @(appDelegate.topSimulatorWindowBounds));
	NSLog(@"Location tap position: %@", @(appDelegate.beginScrollPosition));
	NSLog(@"Location \n");
	NSLog(@"scrolling position: %@", @(position));
	[appDelegate sendMouseEvent:eventType atPosition:position];
	if (appDelegate.replaceScrollAction) {
		return nil;
	}
	return eventRef;
}
