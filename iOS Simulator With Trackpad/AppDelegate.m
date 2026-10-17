//
//  AppDelegate.m
//  iOS Simulator With Trackpad
//
//  Created by 庄黛淳华 on 2020/2/4.
//  Copyright © 2020 庄黛淳华. All rights reserved.
//

#import "AppDelegate.h"
#import <os/log.h>

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef eventRef, AppDelegate *appDelegate);
static CGEventRef clickActivationCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef eventRef, void *context);

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
@property (nonatomic, assign) CFMachPortRef clickActivationPort;
@property (nonatomic, assign) CFRunLoopSourceRef clickActivationSource;
@property (nonatomic, strong) NSTimer *clickActivationRetryTimer;
@property (nonatomic, assign) CGRect topSimulatorWindowBounds;
@property (nonatomic, assign) AXUIElementRef frontWindow;
@property (nonatomic, assign) AXObserverRef topSimulatorWindowBoundsUpdateObs;
@property (nonatomic, assign) CGPoint beginScrollPosition;
@property (nonatomic, assign) CGPoint currentScrollPosition;
@property (nonatomic, assign) BOOL beginDragAction;

@property (nullable, nonatomic, strong) NSStatusItem *item;

@property (nonatomic, strong) NSArray<NSString *> *targetBundleIdentifiers;
@end

@interface AppDelegate (Active)
- (void)workspaceDidActivateApplication:(NSNotification *)notification;
- (void)installClickActivation;
- (void)activateApplicationBeforeMouseDown:(CGEventRef)eventRef;
@end
@interface AppDelegate (StatusBar)
@property (nonatomic, assign) BOOL replaceScrollAction;
@property (nonatomic, assign) BOOL restrictedToAppWindow;
@property (nonatomic, assign) BOOL showRealMouseCursor;
- (void)addStatusBar;
@end

@interface AppDelegate (Application)
- (void)updateTargetApplicationBounds;
- (void)observeTargetApplicationBounds;
@end
@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	os_log(OS_LOG_DEFAULT, "%.0f trackpad launch pid=%d trusted=%d replace=%d restricted=%d", NSDate.date.timeIntervalSince1970 * 1000, NSProcessInfo.processInfo.processIdentifier, AXIsProcessTrusted(), self.replaceScrollAction, self.restrictedToAppWindow);
	[NSWorkspace.sharedWorkspace.notificationCenter addObserver: self selector: @selector(workspaceDidActivateApplication:) name: NSWorkspaceDidActivateApplicationNotification object: nil];
//	NSWindowDidResizeNotification
	[self addStatusBar];
	_targetBundleIdentifiers = @[
		@"com.apple.iphonesimulator",
		@"com.apple.ScreenContinuity",
		@"com.hypergryph.arknights",
	];
	[self installClickActivation];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSApplication.sharedApplication.keyWindow orderOut:self];
		for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
			if ([self.targetBundleIdentifiers containsObject: app.bundleIdentifier]) {
				[NSWorkspace.sharedWorkspace launchAppWithBundleIdentifier: app.bundleIdentifier options:NSWorkspaceLaunchDefault additionalEventParamDescriptor: nil launchIdentifier: nil];
			}
		}
	});
}

- (void)applicationWillTerminate:(NSNotification *)notification {
	[_clickActivationRetryTimer invalidate];
	_clickActivationRetryTimer = nil;
	if (_clickActivationSource != NULL) {
		CFRunLoopRemoveSource(CFRunLoopGetMain(), _clickActivationSource, kCFRunLoopCommonModes);
		CFRelease(_clickActivationSource);
		_clickActivationSource = NULL;
	}
	if (_clickActivationPort != NULL) {
		CFMachPortInvalidate(_clickActivationPort);
		CFRelease(_clickActivationPort);
		_clickActivationPort = NULL;
	}
}
@end

@implementation AppDelegate (StatusBar)
- (void)addStatusBar {
	_item = [[NSStatusBar systemStatusBar] statusItemWithLength: NSSquareStatusItemLength];
	[_item.button setTitle: @"S"];
	_item.menu = [[NSMenu alloc]initWithTitle: @"menu"];

	NSMenuItem *replaceScrollAction = [[NSMenuItem alloc] initWithTitle: self.replaceScrollAction ? @"replaceScrollAction ☑️" : @"replaceScrollAction" action:@selector(switchReplaceScrollAction:) keyEquivalent: @""];
	replaceScrollAction.target = self;
	[_item.menu addItem: replaceScrollAction];
	
	NSMenuItem *restrictedToAppWindow = [[NSMenuItem alloc] initWithTitle: self.restrictedToAppWindow ? @"restrictedToAppWindow ☑️" : @"restrictedToAppWindow" action:@selector(switchRestrictedToAppWindow:) keyEquivalent: @""];
	restrictedToAppWindow.target = self;
	[_item.menu addItem: restrictedToAppWindow];
	
	NSMenuItem *showRealMouseCursor = [[NSMenuItem alloc] initWithTitle: self.showRealMouseCursor ? @"showRealMouseCursor ☑️" : @"showRealMouseCursor" action:@selector(switchShowRealMouseCursor:) keyEquivalent: @""];
	showRealMouseCursor.target = self;
	[_item.menu addItem: showRealMouseCursor];

	NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle: @"quit" action:@selector(terminate:) keyEquivalent: @""];
	quit.target = self;
	[_item.menu addItem: quit];
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

- (void)switchRestrictedToAppWindow:(NSMenuItem *)item {
	self.restrictedToAppWindow = !self.restrictedToAppWindow;
	item.title = self.restrictedToAppWindow ? @"restrictedToAppWindow ☑️" : @"restrictedToAppWindow";
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

- (BOOL)restrictedToAppWindow {
	return [NSUserDefaults.standardUserDefaults boolForKey: [self KeyForSelector: @selector(restrictedToAppWindow)]];
}
- (void)setRestrictedToAppWindow:(BOOL)restrictedToAppWindow {
	[NSUserDefaults.standardUserDefaults setBool: restrictedToAppWindow forKey: [self KeyForSelector: @selector(restrictedToAppWindow)]];
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
	if (_clickActivationPort == NULL && AXIsProcessTrusted()) {
		[self installClickActivation];
	}
    _targetApplication = [_targetBundleIdentifiers containsObject: application.bundleIdentifier] ? application : nil;
	os_log(OS_LOG_DEFAULT, "%.0f activation notification pid=%d target=%d", NSDate.date.timeIntervalSince1970 * 1000, application.processIdentifier, _targetApplication.processIdentifier);

	if (_targetApplication != nil) {
		[self updateTargetApplicationBounds];
		[self observeTargetApplicationBounds];
	}
	self.eventTapEnabled = _targetApplication != nil;
}

- (void)installClickActivation {
	if (_clickActivationPort != NULL) {
		return;
	}
	if (_clickActivationRetryTimer == nil) {
		__weak typeof(self) weakself = self;
		_clickActivationRetryTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
			__strong typeof(self) self = weakself;
			if (self == nil) {
				[timer invalidate];
				return;
			}
			if (AXIsProcessTrusted()) {
				[self installClickActivation];
			}
		}];
		[NSRunLoop.mainRunLoop addTimer:_clickActivationRetryTimer forMode:NSRunLoopCommonModes];
		os_log(OS_LOG_DEFAULT, "%.0f click listener installation started", NSDate.date.timeIntervalSince1970 * 1000);
	}
	if (!AXIsProcessTrusted()) {
		return;
	}
	CGEventMask mask = CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventRightMouseDown) | CGEventMaskBit(kCGEventOtherMouseDown);
	_clickActivationPort = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, clickActivationCallback, (__bridge void *)self);
	os_log(OS_LOG_DEFAULT, "%.0f click tap created=%d trusted=%d", NSDate.date.timeIntervalSince1970 * 1000, _clickActivationPort != NULL, AXIsProcessTrusted());
	if (_clickActivationPort == NULL) {
		NSLog(@"%.0f click activation tap creation failed; scrolling is unchanged", NSDate.date.timeIntervalSince1970 * 1000);
		return;
	}
	_clickActivationSource = CFMachPortCreateRunLoopSource(NULL, _clickActivationPort, 0);
	if (_clickActivationSource == NULL) {
		CFMachPortInvalidate(_clickActivationPort);
		CFRelease(_clickActivationPort);
		_clickActivationPort = NULL;
		NSLog(@"%.0f click activation source creation failed; scrolling is unchanged", NSDate.date.timeIntervalSince1970 * 1000);
		return;
	}
	CFRunLoopAddSource(CFRunLoopGetMain(), _clickActivationSource, kCFRunLoopCommonModes);
	[_clickActivationRetryTimer invalidate];
	_clickActivationRetryTimer = nil;
	os_log(OS_LOG_DEFAULT, "%.0f click listener installation finished", NSDate.date.timeIntervalSince1970 * 1000);
}

- (void)activateApplicationBeforeMouseDown:(CGEventRef)eventRef {
	CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
	CGPoint location = CGEventGetLocation(eventRef);
	NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
	pid_t processIdentifier = 0;
	for (NSDictionary *information in windows) {
		CGRect bounds = CGRectZero;
		if ([information[(id)kCGWindowAlpha] doubleValue] > 0 &&
			CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)information[(id)kCGWindowBounds], &bounds) && CGRectContainsPoint(bounds, location)) {
			NSRunningApplication *candidate = [NSRunningApplication runningApplicationWithProcessIdentifier:[information[(id)kCGWindowOwnerPID] intValue]];
			if (candidate.bundleIdentifier != nil && [self.targetBundleIdentifiers containsObject:candidate.bundleIdentifier]) {
				processIdentifier = candidate.processIdentifier;
				break;
			}
		}
	}
	NSRunningApplication *application = [NSRunningApplication runningApplicationWithProcessIdentifier:processIdentifier];
	if (application.bundleIdentifier == nil || ![self.targetBundleIdentifiers containsObject:application.bundleIdentifier]) {
		return;
	}
	CFAbsoluteTime deadline = started + 0.15;
	BOOL (^prepareElement)(AXUIElementRef) = ^BOOL(AXUIElementRef element) {
		CFTimeInterval remaining = deadline - CFAbsoluteTimeGetCurrent();
		if (remaining <= 0) {
			os_log_error(OS_LOG_DEFAULT, "%.0f click activation budget expired pid=%d; passing original click", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier);
			return NO;
		}
		AXError error = AXUIElementSetMessagingTimeout(element, (float)remaining);
		if (error != kAXErrorSuccess) {
			os_log_error(OS_LOG_DEFAULT, "%.0f click AX timeout setup failed pid=%d error=%d", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, error);
		}
		return error == kAXErrorSuccess;
	};
	AXUIElementRef system = AXUIElementCreateSystemWide();
	AXUIElementRef element = NULL;
	AXError error = prepareElement(system) ? AXUIElementCopyElementAtPosition(system, location.x, location.y, &element) : kAXErrorCannotComplete;
	AXError resetError = AXUIElementSetMessagingTimeout(system, 0);
	if (resetError != kAXErrorSuccess) {
		os_log_error(OS_LOG_DEFAULT, "%.0f click AX default timeout restore failed error=%d", NSDate.date.timeIntervalSince1970 * 1000, resetError);
	}
	CFRelease(system);
	if (error != kAXErrorSuccess) {
		os_log_error(OS_LOG_DEFAULT, "%.0f click hit test failed error=%d duration_ms=%.1f", NSDate.date.timeIntervalSince1970 * 1000, error, (CFAbsoluteTimeGetCurrent() - started) * 1000);
		return;
	}
	error = AXUIElementGetPid(element, &processIdentifier);
	if (error != kAXErrorSuccess) {
		os_log_error(OS_LOG_DEFAULT, "%.0f click owner lookup failed error=%d", NSDate.date.timeIntervalSince1970 * 1000, error);
		CFRelease(element);
		return;
	}
	application = [NSRunningApplication runningApplicationWithProcessIdentifier:processIdentifier];
	if (application.bundleIdentifier == nil || ![self.targetBundleIdentifiers containsObject:application.bundleIdentifier]) {
		CFRelease(element);
		return;
	}
	AXUIElementRef target = AXUIElementCreateApplication(processIdentifier);
	os_log(OS_LOG_DEFAULT, "%.0f target click pid=%d source=%lld event_target=%lld window=%lld x=%.1f y=%.1f", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, CGEventGetIntegerValueField(eventRef, kCGEventSourceUnixProcessID), CGEventGetIntegerValueField(eventRef, kCGEventTargetUnixProcessID), CGEventGetIntegerValueField(eventRef, kCGMouseEventWindowUnderMousePointer), location.x, location.y);
	CFTypeRef role = NULL;
	error = prepareElement(element) ? AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role) : kAXErrorCannotComplete;
	CFTypeRef window = NULL;
	if (error == kAXErrorSuccess && CFEqual(role, kAXWindowRole)) {
		window = CFRetain(element);
	} else {
		if (error != kAXErrorSuccess) {
			os_log_error(OS_LOG_DEFAULT, "%.0f clicked element role lookup failed pid=%d error=%d; using window attribute", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, error);
		}
		error = prepareElement(element) ? AXUIElementCopyAttributeValue(element, kAXWindowAttribute, &window) : kAXErrorCannotComplete;
	}
	if (role != NULL) {
		CFRelease(role);
	}
	CFRelease(element);
	if (error != kAXErrorSuccess) {
		os_log_error(OS_LOG_DEFAULT, "%.0f clicked window lookup failed pid=%d error=%d", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, error);
		CFRelease(target);
		return;
	}
	CFTypeRef focusedWindow = NULL;
	AXError focusError = prepareElement(target) ? AXUIElementCopyAttributeValue(target, kAXFocusedWindowAttribute, &focusedWindow) : kAXErrorCannotComplete;
	if (focusError != kAXErrorSuccess) {
		os_log_error(OS_LOG_DEFAULT, "%.0f focused window lookup failed pid=%d error=%d; raising clicked window", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, focusError);
	}
	BOOL windowIsFocused = focusError == kAXErrorSuccess && CFEqual(window, focusedWindow);
	os_log(OS_LOG_DEFAULT, "%.0f click focus pid=%d active=%d focused=%d", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, application.active, windowIsFocused);
	if (focusedWindow != NULL) {
		CFRelease(focusedWindow);
	}
	if (!application.active && prepareElement(target)) {
		error = AXUIElementSetAttributeValue(target, kAXFrontmostAttribute, kCFBooleanTrue);
		os_log(OS_LOG_DEFAULT, "%.0f click activation pid=%d error=%d", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, error);
	}
	if ((!application.active || !windowIsFocused) && prepareElement(window)) {
		error = AXUIElementPerformAction(window, kAXRaiseAction);
		os_log(OS_LOG_DEFAULT, "%.0f clicked window raise pid=%d error=%d", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, error);
	}
	os_log(OS_LOG_DEFAULT, "%.0f click finish pid=%d active=%d duration_ms=%.1f", NSDate.date.timeIntervalSince1970 * 1000, processIdentifier, application.active, (CFAbsoluteTimeGetCurrent() - started) * 1000);
	CFRelease(target);
	CFRelease(window);
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
			os_log(OS_LOG_DEFAULT, "%.0f scroll tap created=%d target=%d trusted=%d", NSDate.date.timeIntervalSince1970 * 1000, _portRef != NULL, _targetApplication.processIdentifier, AXIsProcessTrusted());
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
	if (eventType == kCGEventLeftMouseDown || eventType == kCGEventLeftMouseUp) {
		os_log(OS_LOG_DEFAULT, "%.0f scroll mouse post type=%u x=%.1f y=%.1f source=%lld cursor=%d", NSDate.date.timeIntervalSince1970 * 1000, eventType, position.x, position.y, CGEventGetIntegerValueField(eventRef, kCGEventSourceUnixProcessID), self.showRealMouseCursor);
	}
	CGEventPost(kCGHIDEventTap, eventRef);
	if (!self.showRealMouseCursor) {
		CGWarpMouseCursorPosition(_beginScrollPosition);
	}
}
@end

static CGEventRef clickActivationCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef eventRef, void *context) {
	AppDelegate *appDelegate = (__bridge AppDelegate *)context;
	if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
		os_log_error(OS_LOG_DEFAULT, "%.0f click tap disabled reason=%u; enabling", NSDate.date.timeIntervalSince1970 * 1000, type);
		CGEventTapEnable(appDelegate.clickActivationPort, true);
		return eventRef;
	}
	if ((type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown) &&
		(CGEventGetFlags(eventRef) & kCGEventFlagMaskCommand) == 0 &&
		CGEventGetIntegerValueField(eventRef, kCGEventSourceUnixProcessID) != NSProcessInfo.processInfo.processIdentifier) {
		[appDelegate activateApplicationBeforeMouseDown:eventRef];
	}
	return eventRef;
}

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef eventRef, AppDelegate *appDelegate) {
	if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
		os_log_error(OS_LOG_DEFAULT, "%.0f scroll tap disabled reason=%u", NSDate.date.timeIntervalSince1970 * 1000, type);
	}
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
	if (event.phase != NSEventPhaseChanged) {
		os_log(OS_LOG_DEFAULT, "%.0f scroll input phase=%lu target=%d x=%.1f y=%.1f bounds_x=%.1f bounds_y=%.1f bounds_w=%.1f bounds_h=%.1f dragging=%d", NSDate.date.timeIntervalSince1970 * 1000, (unsigned long)event.phase, appDelegate.targetApplication.processIdentifier, CGEventGetLocation(eventRef).x, CGEventGetLocation(eventRef).y, topSimulatorWindowBounds.origin.x, topSimulatorWindowBounds.origin.y, topSimulatorWindowBounds.size.width, topSimulatorWindowBounds.size.height, appDelegate.beginDragAction);
	}
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
		appDelegate.beginDragAction = YES;
	} else if (event.phase == NSEventPhaseEnded) {
		NSLog(@"NSEventMaskEndGesture");
		appDelegate.beginDragAction = NO;
		return end();
	} else {
		NSLog(@"NSEventMaskScrollWheel");
		eventType = kCGEventLeftMouseDragged;
	}
	if (!appDelegate.beginDragAction) {
		return eventRef;
	}
	
	if (topSimulatorWindowBounds.size.width <= 0 || topSimulatorWindowBounds.size.height <= 0) {
		return eventRef;
	}

	CGPoint position = appDelegate.currentScrollPosition;
	position.x += event.scrollingDeltaX;
	position.y += event.scrollingDeltaY;
	NSLog(@"position: %@", @(position));

	if (appDelegate.restrictedToAppWindow) {
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
	}
	NSLog(@"----------------------------------------------\n\n");

	appDelegate.currentScrollPosition = position;
	[appDelegate sendMouseEvent:eventType atPosition:position];

	return eventRef;
}
