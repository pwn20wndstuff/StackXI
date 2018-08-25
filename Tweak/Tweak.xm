#import "Tweak.h"


#define TEMPWIDTH 0
#define TEMPDURATION 0.4

extern dispatch_queue_t __BBServerQueue;

static BBServer *bbServer = nil;
static NCNotificationPriorityList *priorityList = nil;
static NCNotificationListCollectionView *listCollectionView = nil;
static NCNotificationCombinedListViewController *clvc = nil;

UIImage * imageWithView(UIView *view) {
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.opaque, 0.0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage * img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static void fakeNotification(NSString *sectionID, NSDate *date) {
    dispatch_sync(__BBServerQueue, ^{
        BBBulletin *bulletin = [[BBBulletin alloc] init];

        bulletin.title = @"StackXI";
        bulletin.message = @"Test notification!";
        bulletin.sectionID = sectionID;
        bulletin.bulletinID = [[NSProcessInfo processInfo] globallyUniqueString];
        bulletin.recordID = [[NSProcessInfo processInfo] globallyUniqueString];
        bulletin.publisherBulletinID = [[NSProcessInfo processInfo] globallyUniqueString];
        bulletin.date = date;
        bulletin.defaultAction = [BBAction actionWithLaunchBundleID:sectionID callblock:nil];

        [bbServer publishBulletin:bulletin destinations:4 alwaysToLockScreen:YES];
    });
}

static void fakeNotifications() {
    fakeNotification(@"com.apple.Music", [NSDate date]);
    fakeNotification(@"com.apple.MobileSMS", [NSDate date]);
    fakeNotification(@"com.apple.MobileSMS", [NSDate date]);
    fakeNotification(@"com.apple.MobileSMS", [NSDate date]);
    fakeNotification(@"com.apple.Music", [NSDate date]);
    fakeNotification(@"com.apple.Music", [NSDate date]);
    fakeNotification(@"com.apple.mobilephone", [NSDate date]);
    fakeNotification(@"com.apple.Music", [NSDate date]);
    fakeNotification(@"com.apple.MobileSMS", [NSDate date]);
}

%group StackXIDebug


%hook BBServer
-(id)initWithQueue:(id)arg1 {
    bbServer = %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        fakeNotifications();
    });

    return bbServer;
}

-(id)initWithQueue:(id)arg1 dataProviderManager:(id)arg2 syncService:(id)arg3 dismissalSyncCache:(id)arg4 observerListener:(id)arg5 utilitiesListener:(id)arg6 conduitListener:(id)arg7 systemStateListener:(id)arg8 settingsListener:(id)arg9 {
    bbServer = %orig;
    return bbServer;
}

- (void)dealloc {
  if (bbServer == self) {
    bbServer = nil;
  }
  
  %orig;
}
%end

%end

%group StackXI

%hook NCNotificationListSectionRevealHintView

-(void)layoutSubviews{
    self.alpha = 0;
    self.hidden = YES;
    %orig;
}

%end

%hook NCNotificationRequest

%property (assign,nonatomic) BOOL isStack;
%property (assign,nonatomic) BOOL isExpanded;
%property (assign,nonatomic) BOOL shouldShow;
%property (nonatomic,retain) NSMutableOrderedSet *stackedNotificationRequests;

-(id)init {
    id orig = %orig;
    self.stackedNotificationRequests = [[NSMutableOrderedSet alloc] init];
    self.shouldShow = false;
    self.isStack = false;
    self.isExpanded = false;
    return orig;
}

%new
-(void)insertNotificationRequest:(NCNotificationRequest *)request {
    [self.stackedNotificationRequests addObject:request];
}

%new
-(void)expandStack {
    self.isExpanded = true;

    for (NCNotificationRequest *request in self.stackedNotificationRequests) {
        request.shouldShow = true;
    }
    
    [listCollectionView reloadData];
    [listCollectionView openStack:self.bulletin.sectionID];
}


%new
-(void)shrinkStack {
    self.isExpanded = false;

    for (NCNotificationRequest *request in self.stackedNotificationRequests) {
        request.shouldShow = false;
    }
    
    [listCollectionView closeStack:self.bulletin.sectionID];
}

%end


%hook NCNotificationSectionList

-(id)removeNotificationRequest:(id)arg1 {
    [priorityList insertNotificationRequest:(NCNotificationRequest *)arg1];
    return nil;
}

-(id)insertNotificationRequest:(id)arg1 {
    [priorityList removeNotificationRequest:(NCNotificationRequest *)arg1];
    return nil;
}

-(NSUInteger)sectionCount {
    return 0;
}

-(NSUInteger)rowCountForSectionIndex:(NSUInteger)arg1 {
    return 0;
}

-(id)notificationRequestsForSectionIdentifier:(id)arg1 {
    return nil;
}

-(id)notificationRequestsAtIndexPaths:(id)arg1 {
    return nil;
}

%end

%hook NCNotificationChronologicalList

-(id)removeNotificationRequest:(id)arg1 {
    [priorityList insertNotificationRequest:(NCNotificationRequest *)arg1];
    return nil;
}

-(id)insertNotificationRequest:(id)arg1 {
    [priorityList removeNotificationRequest:(NCNotificationRequest *)arg1];
    return nil;
}

%end

%hook NCNotificationPriorityList

-(id)init {
    NSLog(@"[StackXI] Init!");
    id orig = %orig;
    priorityList = self;
    return orig;
}

%new
-(void)updateList {
    [self.requests sortUsingComparator:(NSComparator)^(id obj1, id obj2){
        // TODO: improve sorting logic!
        // i.e. sort also by last date (some magic idk w/e)

        NCNotificationRequest *a = (NCNotificationRequest *)obj1;
        NCNotificationRequest *b = (NCNotificationRequest *)obj2;

        if ([a.bulletin.sectionID isEqualToString:b.bulletin.sectionID]) {
            return [a.bulletin.date compare:b.bulletin.date];
        }

        return [a.bulletin.sectionID localizedStandardCompare:b.bulletin.sectionID];
        // TODO: sort by date of the last one in a stack
    }];

    NSString *expandedSection = nil;

    for (int i = 0; i < [self.requests count]; i++) {
        NCNotificationRequest *req = self.requests[i];
        if (req.bulletin.sectionID && req.isExpanded && req.isStack) {
            expandedSection = req.bulletin.sectionID;
            break;
        }
    }

    NSString *lastSection = nil;
    NCNotificationRequest *lastStack = nil;

    for (int i = 0; i < [self.requests count]; i++) {
        NCNotificationRequest *req = self.requests[i];
        if (req.bulletin.sectionID) {
            [req.stackedNotificationRequests removeAllObjects];
            req.isStack = false;
            req.shouldShow = false;
            req.isExpanded = false;

            if ([expandedSection isEqualToString:req.bulletin.sectionID]) {
                req.shouldShow = true;
            }

            if (!lastSection || ![lastSection isEqualToString:req.bulletin.sectionID]) {
                lastSection = req.bulletin.sectionID;
                lastStack = req;

                req.shouldShow = true;
                req.isStack = true;
                if ([expandedSection isEqualToString:req.bulletin.sectionID]) {
                    req.isExpanded = true;
                }

                continue;
            }

            if (lastStack && [lastSection isEqualToString:req.bulletin.sectionID]) {
                [lastStack insertNotificationRequest: req];
            }
        } else {
            req.shouldShow = true;
            req.isStack = true;
        }
    }
}

-(NSUInteger)insertNotificationRequest:(NCNotificationRequest *)request {
    request.shouldShow = true;
    [self.requests addObject:request];
    [self updateList];
    return 0;
}

-(NSUInteger)removeNotificationRequest:(NCNotificationRequest *)request {
    %orig;
    [self.requests removeObject:request];
    [self updateList];
    [listCollectionView reloadData];
    return 0;
}

%end

%hook NCNotificationCombinedListViewController

-(id)init {
    id orig = %orig;
    clvc = self;
    return orig;
}

-(void)viewWillAppear:(bool)animated {
    [listCollectionView closeAll];
    %orig;
}

-(void)viewWillDisappear:(bool)animated {
    [listCollectionView closeAll];
    %orig;
}

-(NSInteger)numberOfSectionsInCollectionView:(id)arg1 {
    return 1;
}

-(NSInteger)collectionView:(id)arg1 numberOfItemsInSection:(NSInteger)arg2 {
    if (arg2 != 0) {
        return 0;
    }

    return %orig;
}

-(NCNotificationListCell*)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section > 0) {
        return nil;
    }

    NCNotificationRequest* request = [self.notificationPriorityList.requests objectAtIndex:indexPath.row];
    if (!request) {
        NSLog(@"[StackXI] request is gone");
        return nil;
    }

    NCNotificationListCell* cell = %orig;
    
    if (!cell.contentViewController.notificationRequest.shouldShow) {
        cell.hidden = YES;
    } else {
        cell.hidden = NO;
    }
    
    return cell;
}

-(CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section > 0) {
        return CGSizeZero;
    }

    CGSize orig = %orig;
    if (indexPath.section == 0) {
        NCNotificationRequest *request = [self.notificationPriorityList.requests objectAtIndex:indexPath.row];
        if (!request.shouldShow) {
            return CGSizeMake(orig.width,0);
        }
    }
    return orig;
}

%end

%hook NCNotificationListCell

/*
-(void)layoutSubviews {
    %orig;
    NSLog(@"[StackXI] SUBVIEWS!!!!");
    if (self.contentViewController.notificationRequest.isStack && !self.contentViewController.notificationRequest.isExpanded) {
        NSLog(@"[StackXI] STACK CELL!!!!");
        [self.rightActionButtonsView.defaultActionButton setTitle: @"Clear All"];
        [self.rightActionButtonsView.defaultActionButton.titleLabel setText: @"Clear All"];
    } else {
        [self.rightActionButtonsView.defaultActionButton setTitle: @"Clear"];
        [self.rightActionButtonsView.defaultActionButton.titleLabel setText: @"Clear"];
    }
}*/

-(void)cellClearButtonPressed:(id)arg1 {
    if (self.contentViewController.notificationRequest.isStack && !self.contentViewController.notificationRequest.isExpanded) {
        for (NCNotificationRequest *request in self.contentViewController.notificationRequest.stackedNotificationRequests) {
            [request.clearAction.actionRunner executeAction:request.clearAction fromOrigin:self withParameters:nil completion:nil];
        }
        
        [self.contentViewController.notificationRequest.clearAction.actionRunner executeAction:self.contentViewController.notificationRequest.clearAction fromOrigin:self withParameters:nil completion:nil];
        return;
    }

    %orig;
}

%end

%hook NCNotificationShortLookViewController

%property (retain) UILabel* stackBadge;

-(id)init {
    id orig = %orig;
    NSLog(@"[StackXI] shortlook view init");
    return orig;
}

-(void)viewDidAppear:(bool)whatever {
    %orig;
    [self updateBadge];
}

-(void)viewDidLayoutSubviews {
    [self updateBadge];
    %orig;
}

%new
-(void)updateBadge {
    if (!self.stackBadge) {
        self.stackBadge = [[UILabel alloc] initWithFrame:CGRectMake(self.view.frame.origin.x + 10, self.view.frame.origin.y + self.view.frame.size.height, self.view.frame.size.width - 20, 25)];
        self.stackBadge.backgroundColor = [UIColor colorWithRed:1.0f green:1.0f blue:1.0f alpha:0.5f];
        self.stackBadge.textAlignment = NSTextAlignmentCenter;
        [self.stackBadge setFont:[UIFont systemFontOfSize:14]];
        self.stackBadge.numberOfLines = 1;
        self.stackBadge.clipsToBounds = YES;
        self.stackBadge.hidden = YES;

        [self.view addSubview:self.stackBadge];
    }

    self.stackBadge.frame = CGRectMake(self.view.frame.origin.x + 10, self.view.frame.origin.y + self.view.frame.size.height, self.view.frame.size.width - 20, 25);
    [self.view bringSubviewToFront:self.stackBadge];

    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:self.stackBadge.bounds byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight) cornerRadii:CGSizeMake(8.0, 8.0)];

    CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
    maskLayer.frame = self.stackBadge.bounds;
    maskLayer.path  = maskPath.CGPath;
    self.stackBadge.layer.mask = maskLayer;

    if (self.notificationRequest.isStack && !self.notificationRequest.isExpanded && [self.notificationRequest.stackedNotificationRequests count] > 0) {
        self.stackBadge.hidden = NO;
        int count = [self.notificationRequest.stackedNotificationRequests count];
        if (count == 1) {
            self.stackBadge.text = [NSString stringWithFormat:@"+%d notification", count];
        } else {
            self.stackBadge.text = [NSString stringWithFormat:@"+%d notifications", count];
        }
    } else {
        self.stackBadge.hidden = YES;
    }
}

- (void)_handleTapOnView:(id)arg1 {
    NSLog(@"[StackXI] tap");
    
    if (self.notificationRequest.isStack && !self.notificationRequest.isExpanded) {
        [UIView animateWithDuration:TEMPDURATION animations:^{
            self.stackBadge.alpha = 0;
        }];
        [self.notificationRequest expandStack];
        return;
    }

    return %orig;
}

%end

%hook NCNotificationListCollectionView

-(id)initWithFrame:(CGRect)arg1 collectionViewLayout:(id)arg2 {
    id orig = %orig;
    listCollectionView = self;
    return orig;
}

-(void)reloadData {
    %orig;
    [priorityList updateList];
    [self.collectionViewLayout invalidateLayout];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    for (NSInteger row = 0; row < [self numberOfItemsInSection:0]; row++) {
        id c = [self _visibleCellForIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        if (!c) continue;

        NCNotificationListCell* cell = (NCNotificationListCell*)c;
        [(NCNotificationShortLookViewController *)cell.contentViewController updateBadge];
    }
}

%new
-(void)closeAll {
    NSMutableOrderedSet *sectionIDs = [[NSMutableOrderedSet alloc] initWithCapacity:100];

    for (NCNotificationRequest *request in priorityList.requests) {
        if (!request.bulletin.sectionID) continue;

        if (![sectionIDs containsObject:request.bulletin.sectionID] && request.isStack && request.isExpanded) {
            [request shrinkStack];
            [sectionIDs addObject:request.bulletin.sectionID];
        }
    }

    [listCollectionView reloadData];
}

%new
-(void)openStack:(NSString *)sectionID {
    NSMutableOrderedSet *sectionIDs = [[NSMutableOrderedSet alloc] initWithCapacity:100];
    [sectionIDs addObject:sectionID];

    for (NCNotificationRequest *request in priorityList.requests) {
        if (!request.bulletin.sectionID) continue;

        if (![sectionIDs containsObject:request.bulletin.sectionID] && request.isStack && request.isExpanded) {
            [request shrinkStack];
            [sectionIDs addObject:request.bulletin.sectionID];
        }
    }
    
    [listCollectionView reloadData];

    CGRect frame = CGRectMake(0,0,0,0);
    bool frameFound = false;
    for (NSInteger row = 0; row < [self numberOfItemsInSection:0]; row++) {
        id c = [self _visibleCellForIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        if (!c) continue;

        NCNotificationListCell* cell = (NCNotificationListCell*)c;
        if ([sectionID isEqualToString:cell.contentViewController.notificationRequest.bulletin.sectionID]) {
            if (!frameFound) {
                frameFound = true;
                frame = cell.frame;
                continue;
            }

            [self sendSubviewToBack:cell];

            CGRect properFrame = cell.frame;
            cell.frame = frame;
            [UIView animateWithDuration:TEMPDURATION animations:^{
                cell.frame = properFrame;
            }];
        }
    }
}

%new
-(void)closeStack:(NSString *)sectionID {
    CGRect frame = CGRectMake(0,0,0,0);
    bool frameFound = false;
    for (NSInteger row = 0; row < [self numberOfItemsInSection:0]; row++) {
        id c = [self _visibleCellForIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        if (!c) continue;

        NCNotificationListCell* cell = (NCNotificationListCell*)c;
        if ([sectionID isEqualToString:cell.contentViewController.notificationRequest.bulletin.sectionID]) {
            if (!frameFound) {
                frameFound = true;
                frame = cell.frame;
                continue;
            }

            [UIView animateWithDuration:TEMPDURATION animations:^{
                cell.frame = frame;
            }];
        }
    }
}

-(void)deleteItemsAtIndexPaths:(id)arg1 { [self reloadData]; }
-(void)insertItemsAtIndexPaths:(id)arg1 { [self reloadData]; }
-(void)reloadItemsAtIndexPaths:(id)arg1 { [self reloadData]; }
-(void)reloadSections:(id)arg1 { [self reloadData]; }
-(void)deleteSections:(id)arg1 { [self reloadData]; }
-(void)insertSections:(id)arg1 { [self reloadData]; }
-(void)moveItemAtIndexPath:(id)prevPath toIndexPath:(id)newPath { [self reloadData]; }

-(void)performBatchUpdates:(id)updates completion:(void (^)(bool finished))completion {
	[self reloadData];
	if (completion) completion(true);
}

%end

%end

static void displayStatusChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (listCollectionView) {
        [listCollectionView closeAll];
    }
}

%ctor{
    HBPreferences *file = [[HBPreferences alloc] initWithIdentifier:@"io.ominousness.stackxi"];
    bool enabled = [([file objectForKey:@"Enabled"] ?: @(YES)) boolValue];
    bool debug = false;

    if (enabled) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, displayStatusChanged, CFSTR("com.apple.iokit.hid.displayStatus"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        %init(StackXI);
        if (debug) %init(StackXIDebug);
    }
}
