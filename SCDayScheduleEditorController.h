//
//  SCDayScheduleEditorController.h
//  SelfControl
//
//  Sheet controller for editing a single day's schedule for a bundle.
//  Shows a visual 24-hour timeline where users can drag to create/edit allowed windows.
//

#import <Cocoa/Cocoa.h>
#import "Block Management/SCBlockBundle.h"
#import "Block Management/SCWeeklySchedule.h"
#import "Block Management/SCTimeRange.h"

NS_ASSUME_NONNULL_BEGIN

@class SCDayScheduleEditorController;

@protocol SCDayScheduleEditorDelegate <NSObject>

/// Called when user saves changes to the schedule
- (void)dayScheduleEditor:(SCDayScheduleEditorController *)editor
         didSaveSchedule:(SCWeeklySchedule *)schedule
                  forDay:(SCDayOfWeek)day;

/// Called when user cancels editing
- (void)dayScheduleEditorDidCancel:(SCDayScheduleEditorController *)editor;

@optional

/// Called when user wants to copy this day's schedule to other days
- (void)dayScheduleEditor:(SCDayScheduleEditorController *)editor
         didRequestCopyToDay:(SCDayOfWeek)targetDay;

@end

@interface SCDayScheduleEditorController : NSWindowController

@property (nonatomic, weak, nullable) id<SCDayScheduleEditorDelegate> delegate;

/// The bundle being edited
@property (nonatomic, strong, readonly) SCBlockBundle *bundle;

/// The day being edited
@property (nonatomic, assign, readonly) SCDayOfWeek day;

/// The schedule being edited (will be copied, original not modified until save)
@property (nonatomic, strong, readonly) SCWeeklySchedule *schedule;

/// Whether schedule is committed (limits loosening)
@property (nonatomic, assign) BOOL isCommitted;

/// Initialize with bundle, schedule, and day
- (instancetype)initWithBundle:(SCBlockBundle *)bundle
                      schedule:(SCWeeklySchedule *)schedule
                           day:(SCDayOfWeek)day;

/// Show the editor as a sheet on the given window
- (void)beginSheetModalForWindow:(NSWindow *)parentWindow
               completionHandler:(nullable void (^)(NSModalResponse))handler;

@end

NS_ASSUME_NONNULL_END
