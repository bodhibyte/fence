//
//  SCCalendarGridView.h
//  SelfControl
//
//  7-day calendar view showing allow blocks as events.
//  Supports Focus/All-Up states for bundle editing.
//

#import <Cocoa/Cocoa.h>
#import "Block Management/SCWeeklySchedule.h"

@class SCBlockBundle;
@class SCCalendarGridView;

NS_ASSUME_NONNULL_BEGIN

@protocol SCCalendarGridViewDelegate <NSObject>

/// Called when user creates/modifies/deletes an allow block
- (void)calendarGrid:(SCCalendarGridView *)grid
    didUpdateSchedule:(SCWeeklySchedule *)schedule
          forBundleID:(NSString *)bundleID;

/// Called when user clicks an empty area (clears bundle focus)
- (void)calendarGridDidClickEmptyArea:(SCCalendarGridView *)grid;

/// Called when user double-clicks a block (for detailed editing)
- (void)calendarGrid:(SCCalendarGridView *)grid
didRequestEditBundle:(SCBlockBundle *)bundle
              forDay:(SCDayOfWeek)day;

@optional

/// Called when user tries to interact with empty area without a bundle selected
/// Use this to show a "select a bundle first" warning
- (void)calendarGridDidAttemptInteractionWithoutFocus:(SCCalendarGridView *)grid;

@end

@interface SCCalendarGridView : NSView

/// Delegate for handling events
@property (nonatomic, weak, nullable) id<SCCalendarGridViewDelegate> delegate;

/// Array of bundles to display
@property (nonatomic, copy) NSArray<SCBlockBundle *> *bundles;

/// Dictionary mapping bundleID → SCWeeklySchedule
@property (nonatomic, copy) NSDictionary<NSString *, SCWeeklySchedule *> *schedules;

/// Currently focused bundle ID (nil = All-Up state, all bundles at 100%)
@property (nonatomic, copy, nullable) NSString *focusedBundleID;

/// Whether editing is locked (committed state)
@property (nonatomic, assign) BOOL isCommitted;

/// Week offset: 0 = current week, 1 = next week
@property (nonatomic, assign) NSInteger weekOffset;

/// Show only remaining days in current week (for weekOffset 0)
@property (nonatomic, assign) BOOL showOnlyRemainingDays;

/// Reload all data
- (void)reloadData;

/// Get schedule for a bundle
- (nullable SCWeeklySchedule *)scheduleForBundleID:(NSString *)bundleID;

/// Get the bundle object for a bundleID
- (nullable SCBlockBundle *)bundleForID:(NSString *)bundleID;

/// Undo manager for undo/redo support
@property (nonatomic, strong) NSUndoManager *undoManager;

/// Check if any block is currently selected
- (BOOL)hasSelectedBlock;

/// Clear all block selections
- (void)clearAllSelections;

@end

NS_ASSUME_NONNULL_END
