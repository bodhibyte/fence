//
//  SCWeekGridView.h
//  SelfControl
//
//  Custom view that displays the week grid with bundles as rows and days as columns.
//  Each cell shows a mini 24-hour timeline with allowed windows highlighted.
//

#import <Cocoa/Cocoa.h>
#import "Block Management/SCBlockBundle.h"
#import "Block Management/SCWeeklySchedule.h"

NS_ASSUME_NONNULL_BEGIN

@class SCWeekGridView;

@protocol SCWeekGridViewDelegate <NSObject>

/// Called when user clicks on a cell to edit that day's schedule
- (void)weekGridView:(SCWeekGridView *)gridView
    didSelectBundle:(SCBlockBundle *)bundle
             forDay:(SCDayOfWeek)day;

/// Called when user wants to edit a bundle's settings
- (void)weekGridView:(SCWeekGridView *)gridView
    didRequestEditBundle:(SCBlockBundle *)bundle;

/// Called when user wants to add a new bundle
- (void)weekGridViewDidRequestAddBundle:(SCWeekGridView *)gridView;

@optional

/// Called when user right-clicks a cell for copy/paste context menu
- (void)weekGridView:(SCWeekGridView *)gridView
    didRightClickBundle:(SCBlockBundle *)bundle
                 forDay:(SCDayOfWeek)day
                atPoint:(NSPoint)point;

@end

@interface SCWeekGridView : NSView

@property (nonatomic, weak, nullable) id<SCWeekGridViewDelegate> delegate;

/// Whether the view should only show remaining days (today forward)
@property (nonatomic, assign) BOOL showOnlyRemainingDays;

/// Whether week starts on Monday (YES) or Sunday (NO)
@property (nonatomic, assign) BOOL weekStartsOnMonday;

/// Whether the schedule is committed (affects editability display)
@property (nonatomic, assign) BOOL isCommitted;

/// Bundles to display as rows
@property (nonatomic, copy, nullable) NSArray<SCBlockBundle *> *bundles;

/// Schedules (one per bundle)
@property (nonatomic, copy, nullable) NSArray<SCWeeklySchedule *> *schedules;

/// Reloads the grid with current data
- (void)reloadData;

/// Returns the schedule for a specific bundle
- (nullable SCWeeklySchedule *)scheduleForBundle:(SCBlockBundle *)bundle;

/// Highlights a specific cell (for copy/paste feedback)
- (void)highlightCellForBundle:(NSString *)bundleID day:(SCDayOfWeek)day;

/// Clears any cell highlight
- (void)clearCellHighlight;

@end

NS_ASSUME_NONNULL_END
