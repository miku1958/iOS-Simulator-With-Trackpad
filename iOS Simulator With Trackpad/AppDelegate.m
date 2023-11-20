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

typedef NS_ENUM(NSInteger, Position) {
	PositionTopLeft = 0,
	PositionBottomLeft = 1,
};

NSScreen *defaultScreen(void) {
	for (NSScreen *screen in NSScreen.screens) {
		if ([screen.deviceDescription[@"NSScreenNumber"] intValue] == 1) {
			return screen;
		}
	}
	return NSScreen.screens.firstObject;
}

CGPoint fixedPosition(CGPoint point, Position position) {
	switch (position) {
		case PositionTopLeft:
			return point;
		case PositionBottomLeft:
			return CGPointMake(point.x, defaultScreen().frame.size.height - point.y);
	}
}

CGPoint fixedPositionTo(CGPoint fixedPosition, Position position) {
	switch (position) {
		case PositionTopLeft:
			return fixedPosition;
		case PositionBottomLeft:
			return CGPointMake(fixedPosition.x, fixedPosition.y - defaultScreen().frame.size.height);
	}
}

@interface AppDelegate ()
@property (nonatomic, assign) BOOL eventTapEnabled;
@property (nonatomic, strong) NSRunningApplication *targetApplication;
@property (nonatomic, assign) CFMachPortRef portRef;
@property (nonatomic, assign) CFRunLoopSourceRef runLoopSourceRef;
@property (nonatomic, assign) CGRect topSimulatorWindowBounds;
@property (nonatomic, assign) AXUIElementRef frontWindow;
@property (nonatomic, assign) AXObserverRef topSimulatorWindowBoundsUpdateObs;
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
- (void)observeTargetApplicationBounds;
@end
@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[NSWorkspace.sharedWorkspace.notificationCenter addObserver: self selector: @selector(workspaceDidActivateApplication:) name: NSWorkspaceDidActivateApplicationNotification object: nil];
//	NSWindowDidResizeNotification
	[self addStatusBar];
	_targetBundleIdentifiers = @[
		@"com.apple.iphonesimulator",
		@"com.hypergryph.arknights",
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
	return [NSString stringWithFormat: @"%@", NSStringFromSelector(selector)];
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
	[NSUserDefaults.standardUserDefaults synchronize];
}

- (BOOL)showRealMouseCursor {
	return [NSUserDefaults.standardUserDefaults boolForKey: [self KeyForSelector: @selector(showRealMouseCursor)]];
}
- (void)setShowRealMouseCursor:(BOOL)showRealMouseCursor {
	[NSUserDefaults.standardUserDefaults setBool: showRealMouseCursor forKey: [self KeyForSelector: @selector(showRealMouseCursor)]];
	[NSUserDefaults.standardUserDefaults synchronize];
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
		[self observeTargetApplicationBounds];
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
void _updateTargetApplicationBounds(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void * __nullable refcon) {
	AppDelegate* delegate = (__bridge AppDelegate *)refcon;
	[delegate updateTargetApplicationBounds];
}

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
	NSLog(@"topSimulatorWindowBounds: %@", @(rect))
	_topSimulatorWindowBounds = rect;
}

- (void)observeTargetApplicationBounds {
	AXUIElementRef app = AXUIElementCreateApplication(_targetApplication.processIdentifier);

	CFArrayRef names = NULL;
	AXUIElementCopyAttributeNames(app, &names);

	AXUIElementRef frontWindow = NULL;
	AXError err = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, (const void **)&frontWindow);
	if (err != kAXErrorSuccess) {
		return;
	}

	if (_frontWindow != nil && CFEqual(_frontWindow, frontWindow)) {
		return;
	}
	_frontWindow = frontWindow;

	if (_topSimulatorWindowBoundsUpdateObs != NULL) {
		AXObserverRemoveNotification(_topSimulatorWindowBoundsUpdateObs, _frontWindow, kAXMovedNotification);
		AXObserverRemoveNotification(_topSimulatorWindowBoundsUpdateObs, _frontWindow, kAXResizedNotification);
		CFRunLoopRemoveSource([[NSRunLoop currentRunLoop] getCFRunLoop], AXObserverGetRunLoopSource(_topSimulatorWindowBoundsUpdateObs), kCFRunLoopDefaultMode);
	}

	err = AXObserverCreate(_targetApplication.processIdentifier, _updateTargetApplicationBounds, &_topSimulatorWindowBoundsUpdateObs);
	if (err != kAXErrorSuccess) {
		return;
	}
	AXObserverAddNotification(_topSimulatorWindowBoundsUpdateObs, frontWindow, kAXMovedNotification, (void * _Nullable)self);
	AXObserverAddNotification(_topSimulatorWindowBoundsUpdateObs, frontWindow, kAXResizedNotification, (void * _Nullable)self);

	CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop],
					   AXObserverGetRunLoopSource(_topSimulatorWindowBoundsUpdateObs),
					   kCFRunLoopDefaultMode);
}

@end

@implementation AppDelegate (Event)

- (void)sendMouseEvent:(CGEventType)eventType atPosition:(CGPoint)position {
	CGEventRef eventRef = CGEventCreateMouseEvent(NULL, eventType, fixedPositionTo(position, PositionTopLeft), 0);
	CGEventPost(kCGHIDEventTap, eventRef);
	if (!self.showRealMouseCursor) {
		CGWarpMouseCursorPosition(_beginScrollPosition);
	}
}
@end

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef eventRef, AppDelegate *appDelegate) {
	// topSimulatorWindowBounds is related to main screen, (0, 0) is left top corner of main, to top is decreasing

	// event.locationInWindow is related to main screen, (0, 0) is left bottom corner of main, to top is increasing

	if (!appDelegate.replaceScrollAction) {
		return eventRef;
	}
	CGRect topSimulatorWindowBounds = appDelegate.topSimulatorWindowBounds;
	topSimulatorWindowBounds.origin = fixedPosition(topSimulatorWindowBounds.origin, PositionTopLeft);

	NSLog(@"topSimulatorWindowBounds: %@", @(topSimulatorWindowBounds));
	NSLog(@"CGRectGetMaxX(topSimulatorWindowBounds): %@", @(CGRectGetMaxX(topSimulatorWindowBounds)));
	NSLog(@"CGRectGetMaxY(topSimulatorWindowBounds): %@", @(CGRectGetMaxY(topSimulatorWindowBounds)));

	__auto_type end = ^CGEventRef() {
		if (appDelegate.currentScrollPosition.x == NSNotFound) {
			return eventRef;
		}

		if (topSimulatorWindowBounds.size.width <= 0 || topSimulatorWindowBounds.size.height <= 0) {
			return eventRef;
		}
		NSLog(@"end");
		[appDelegate sendMouseEvent: kCGEventLeftMouseUp atPosition: appDelegate.currentScrollPosition];
		appDelegate.currentScrollPosition = CGPointMake(NSNotFound, 0);
		[appDelegate sendMouseEvent: kCGEventMouseMoved atPosition: appDelegate.beginScrollPosition];
		return eventRef;
	};
	
	// 这里不能断点, 否则用NSEvent eventWithCGEvfent时内部的NSEvent会闪退
    NSEvent *event = [NSEvent eventWithCGEvent: eventRef];
//	NSLog(@"event: %@", event);
	
	CGEventType eventType;
	CGPoint locationInWindow = fixedPosition(event.locationInWindow, PositionBottomLeft);
	NSLog(@"event.locationInWindow: %@", @(event.locationInWindow));
	NSLog(@"locationInWindow: %@", @(locationInWindow));

	if (event.phase == NSEventPhaseBegan) {
		NSLog(@"NSEventMaskBeginGesture");
		eventType = kCGEventLeftMouseDown;
		appDelegate.beginScrollPosition = locationInWindow;
		appDelegate.currentScrollPosition = appDelegate.beginScrollPosition;
	} else if (event.phase == NSEventPhaseEnded) {
		NSLog(@"NSEventMaskEndGesture");
		return end();
	} else {
		NSLog(@"NSEventMaskScrollWheel");
		eventType = kCGEventLeftMouseDragged;
	}
	if (topSimulatorWindowBounds.size.width <= 0 || topSimulatorWindowBounds.size.height <= 0) {
		return eventRef;
	}

	CGPoint position = appDelegate.currentScrollPosition;
	position.x += event.scrollingDeltaX;
	position.y += event.scrollingDeltaY;

	NSLog(@"position: %@", @(position));
	if (position.x > CGRectGetMaxX(topSimulatorWindowBounds)) {
		NSLog(@"position.x > CGRectGetMaxX(topSimulatorWindowBounds)");
		return eventRef;
	}
	if (position.y > CGRectGetMaxY(topSimulatorWindowBounds)) {
		NSLog(@"position.y > CGRectGetMaxY(topSimulatorWindowBounds)");
		return eventRef;
	}
	if (position.x < topSimulatorWindowBounds.origin.x) {
		NSLog(@"position.x < topSimulatorWindowBounds.origin.x");
		return eventRef;
	}
	if (position.y < topSimulatorWindowBounds.origin.y) {
		NSLog(@"position.y < topSimulatorWindowBounds.origin.y");
		return eventRef;
	}
	NSLog(@"----------------------------------------------\n\n");

	appDelegate.currentScrollPosition = position;
	[appDelegate sendMouseEvent:eventType atPosition:position];

	return eventRef;
}
