#import "Tweak.h"


#define TEMPWIDTH 0
#define TEMPDURATION 0.4

extern dispatch_queue_t __BBServerQueue;

static BBServer *bbServer = nil;
static NCNotificationPriorityList *priorityList = nil;
static NCNotificationListCollectionView *listCollectionView = nil;
static NCNotificationCombinedListViewController *clvc = nil;
static bool showButtons = false;

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
    fakeNotification(@"com.apple.mobilephone", [NSDate date]);
    fakeNotification(@"com.apple.mobilephone", [NSDate date]);
    fakeNotification(@"com.apple.mobilephone", [NSDate date]);
    fakeNotification(@"com.apple.mobilephone", [NSDate date]);
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

%property (assign,nonatomic) BOOL sxiIsStack;
%property (assign,nonatomic) BOOL sxiIsExpanded;
%property (assign,nonatomic) BOOL sxiVisible;
%property (assign,nonatomic) NSUInteger sxiPositionInStack;
%property (nonatomic,retain) NSMutableOrderedSet *sxiStackedNotificationRequests;

-(id)init {
    id orig = %orig;
    self.sxiStackedNotificationRequests = [[NSMutableOrderedSet alloc] init];
    self.sxiVisible = true;
    self.sxiIsStack = false;
    self.sxiIsExpanded = false;
    self.sxiPositionInStack = 0;
    return orig;
}

%new
-(void)sxiInsertRequest:(NCNotificationRequest *)request {
    [self.sxiStackedNotificationRequests addObject:request];
}

%new
-(void)sxiExpand {
    self.sxiIsExpanded = true;

    for (NCNotificationRequest *request in self.sxiStackedNotificationRequests) {
        request.sxiVisible = true;
    }
    
    [listCollectionView sxiExpand:self.bulletin.sectionID];
}


%new
-(void)sxiCollapse {
    self.sxiIsExpanded = false;

    for (NCNotificationRequest *request in self.sxiStackedNotificationRequests) {
        request.sxiVisible = false;
    }
    
    [listCollectionView sxiCollapse:self.bulletin.sectionID];
}

%end


%hook NCNotificationSectionList

-(id)removeNotificationRequest:(id)arg1 {
    [priorityList removeNotificationRequest:(NCNotificationRequest *)arg1];
    return nil;
}

-(id)insertNotificationRequest:(id)arg1 {
    [priorityList insertNotificationRequest:(NCNotificationRequest *)arg1];
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
    [priorityList removeNotificationRequest:(NCNotificationRequest *)arg1];
    return nil;
}

-(id)insertNotificationRequest:(id)arg1 {
    [priorityList insertNotificationRequest:(NCNotificationRequest *)arg1];
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
-(void)sxiUpdateList {
    [self.requests sortUsingComparator:(NSComparator)^(id obj1, id obj2){
        // TODO: improve sorting logic!
        // i.e. sort also by last date (some magic idk w/e)

        NCNotificationRequest *a = (NCNotificationRequest *)obj1;
        NCNotificationRequest *b = (NCNotificationRequest *)obj2;

        if ([a.bulletin.sectionID isEqualToString:b.bulletin.sectionID]) {
            return [b.bulletin.date compare:a.bulletin.date];
        }

        return [a.bulletin.sectionID localizedStandardCompare:b.bulletin.sectionID];
        // TODO: sort by date of the last one in a stack
    }];

    NSString *expandedSection = nil;

    for (int i = 0; i < [self.requests count]; i++) {
        NCNotificationRequest *req = self.requests[i];
        if (req.bulletin.sectionID && req.sxiIsExpanded && req.sxiIsStack) {
            expandedSection = req.bulletin.sectionID;
            break;
        }
    }

    NSString *lastSection = nil;
    NCNotificationRequest *lastStack = nil;
    NSUInteger sxiPositionInStack = 0;

    for (int i = 0; i < [self.requests count]; i++) {
        NCNotificationRequest *req = self.requests[i];
        if (req.bulletin.sectionID) {
            [req.sxiStackedNotificationRequests removeAllObjects];
            req.sxiIsStack = false;
            req.sxiVisible = false;
            req.sxiIsExpanded = false;
            req.sxiPositionInStack = ++sxiPositionInStack;

            if ([expandedSection isEqualToString:req.bulletin.sectionID]) {
                req.sxiVisible = true;
            }

            if (!lastSection || ![lastSection isEqualToString:req.bulletin.sectionID]) {
                lastSection = req.bulletin.sectionID;
                lastStack = req;

                req.sxiVisible = true;
                req.sxiIsStack = true;
                req.sxiPositionInStack = 0;
                sxiPositionInStack = 0;
                if ([expandedSection isEqualToString:req.bulletin.sectionID]) {
                    req.sxiIsExpanded = true;
                }

                continue;
            }

            if (lastStack && [lastSection isEqualToString:req.bulletin.sectionID]) {
                [lastStack sxiInsertRequest:req];
            }
        } else {
            req.sxiVisible = true;
            req.sxiIsStack = true;
            req.sxiIsExpanded = false;
            req.sxiPositionInStack = 0;
        }
    }
}

-(NSUInteger)insertNotificationRequest:(NCNotificationRequest *)request {
    request.sxiVisible = true;
    [self.requests addObject:request];
    [listCollectionView reloadData];
    return 0;
}

-(NSUInteger)removeNotificationRequest:(NCNotificationRequest *)request {
    %orig;
    [self.requests removeObject:request];
    [listCollectionView reloadData];
    return 0;
}

-(id)clearNonPersistentRequests {
    return %orig;
}

-(id)clearRequestsPassingTest:(id)arg1 {
    //it removes notifications on unlock/lock :c
    //so i had to disable this
    return nil;
}

-(id)clearAllRequests {
    //not sure if i want this working too :D
    return nil;
}

%end

%hook NCNotificationCombinedListViewController

-(id)init {
    id orig = %orig;
    clvc = self;
    return orig;
}

-(void)viewWillAppear:(bool)animated {
    [listCollectionView sxiCollapseAll];
    %orig;
}

-(void)viewWillDisappear:(bool)animated {
    [listCollectionView sxiCollapseAll];
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
    
    if (!cell.contentViewController.notificationRequest.sxiVisible) {
        if (cell.contentViewController.notificationRequest.sxiPositionInStack > 3) {
            cell.hidden = YES; 
        } else {
            cell.hidden = NO;
            if (cell.frame.size.height != 50) {
                cell.frame = CGRectMake(cell.frame.origin.x + (10 * cell.contentViewController.notificationRequest.sxiPositionInStack), cell.frame.origin.y - 50, cell.frame.size.width - (20 * cell.contentViewController.notificationRequest.sxiPositionInStack), 50);
            }
        }
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
        if (!request.sxiVisible) {
            if (request.sxiPositionInStack > 3) {
                return CGSizeMake(orig.width,0);
            } else {
                return CGSizeMake(orig.width,1);
            }
        }

        if (request.sxiIsStack && !request.sxiIsExpanded && [request.sxiStackedNotificationRequests count] > 0) {
            return CGSizeMake(orig.width,orig.height + 15);
        }
    }
    return orig;
}

%end

%hook NCNotificationListCell


-(void)layoutSubviews {
    /*//NSLog(@"[StackXI] SUBVIEWS!!!!");
    if (self.contentViewController.notificationRequest.sxiIsStack && !self.contentViewController.notificationRequest.sxiIsExpanded) {
        //NSLog(@"[StackXI] STACK CELL!!!!");
        [self.rightActionButtonsView.defaultActionButton setTitle: @"Clear All"];
        [self.rightActionButtonsView.defaultActionButton.titleLabel setText: @"Clear All"];
    } else {
        [self.rightActionButtonsView.defaultActionButton setTitle: @"Clear"];
        [self.rightActionButtonsView.defaultActionButton.titleLabel setText: @"Clear"];
    }*/
    %orig;
    if (!self.contentViewController.notificationRequest.sxiIsStack) {
        [listCollectionView sendSubviewToBack:self];
    }
}

-(void)cellClearButtonPressed:(id)arg1 {
    if (self.contentViewController.notificationRequest.sxiIsStack && !self.contentViewController.notificationRequest.sxiIsExpanded) {
        for (NCNotificationRequest *request in self.contentViewController.notificationRequest.sxiStackedNotificationRequests) {
            [request.clearAction.actionRunner executeAction:request.clearAction fromOrigin:self withParameters:nil completion:nil];
        }
        
        [self.contentViewController.notificationRequest.clearAction.actionRunner executeAction:self.contentViewController.notificationRequest.clearAction fromOrigin:self withParameters:nil completion:nil];
        return;
    }

    %orig;
}

%end

%hook NCNotificationShortLookViewController

%property (retain) UILabel* sxiNotificationCount;
%property (retain) UIButton* sxiClearAllButton;
%property (retain) UIButton* sxiCollapseButton;

-(id)init {
    id orig = %orig;
    NSLog(@"[StackXI] shortlook view init");
    return orig;
}

-(void)viewWillAppear:(bool)whatever {
    %orig;
    [self sxiUpdateCount];
}

-(void)viewDidAppear:(bool)whatever {
    %orig;
    [self sxiUpdateCount];
}

-(void)viewDidLayoutSubviews {
    [self sxiUpdateCount];
    %orig;
}

%new
-(void)sxiCollapse:(UIButton *)button {
    [self.notificationRequest sxiCollapse];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, TEMPDURATION * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [listCollectionView reloadData];
    });
}

%new
-(void)sxiClearAll:(UIButton *)button {
    for (NCNotificationRequest *request in self.notificationRequest.sxiStackedNotificationRequests) {
        [request.clearAction.actionRunner executeAction:request.clearAction fromOrigin:self withParameters:nil completion:nil];
    }
    
    [self.notificationRequest.clearAction.actionRunner executeAction:self.notificationRequest.clearAction fromOrigin:self withParameters:nil completion:nil];
    [listCollectionView reloadData];
}

%new
-(void)sxiUpdateCount {
    if (!self.sxiNotificationCount) {
        self.sxiNotificationCount = [[UILabel alloc] initWithFrame:CGRectMake(self.view.frame.origin.x + 11, self.view.frame.origin.y + self.view.frame.size.height, self.view.frame.size.width - 21, 25)];
        [self.sxiNotificationCount setFont:[UIFont systemFontOfSize:12]];
        self.sxiNotificationCount.numberOfLines = 1;
        self.sxiNotificationCount.clipsToBounds = YES;
        self.sxiNotificationCount.hidden = YES;
        self.sxiNotificationCount.alpha = 0.0;
        self.sxiNotificationCount.textColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        [self.view addSubview:self.sxiNotificationCount];

        if (showButtons) {
            self.sxiClearAllButton = [[UIButton alloc] initWithFrame:CGRectMake(self.view.frame.origin.x + self.view.frame.size.width - 165, self.view.frame.origin.y + 5, 75, 25)];
            [self.sxiClearAllButton.titleLabel setFont:[UIFont systemFontOfSize:12]];
            self.sxiClearAllButton.hidden = YES;
            self.sxiClearAllButton.alpha = 0.0;
            [self.sxiClearAllButton setTitle:@"Clear All" forState: UIControlStateNormal];
            self.sxiClearAllButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
            [self.sxiClearAllButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            self.sxiClearAllButton.layer.masksToBounds = true;
            self.sxiClearAllButton.layer.cornerRadius = 12.5;

            self.sxiCollapseButton = [[UIButton alloc] initWithFrame:CGRectMake(self.view.frame.origin.x + self.view.frame.size.width - 80, self.view.frame.origin.y + 5, 75, 25)];
            [self.sxiCollapseButton.titleLabel setFont:[UIFont systemFontOfSize:12]];
            self.sxiCollapseButton.hidden = YES;
            self.sxiCollapseButton.alpha = 0.0;
            [self.sxiCollapseButton setTitle:@"Collapse" forState:UIControlStateNormal];
            self.sxiCollapseButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
            [self.sxiCollapseButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            self.sxiCollapseButton.layer.masksToBounds = true;
            self.sxiCollapseButton.layer.cornerRadius = 12.5;
            
            [self.sxiClearAllButton addTarget:self action:@selector(sxiClearAll:) forControlEvents:UIControlEventTouchUpInside];
            [self.sxiCollapseButton addTarget:self action:@selector(sxiCollapse:) forControlEvents:UIControlEventTouchUpInside];
            
            [self.view addSubview:self.sxiClearAllButton];
            [self.view addSubview:self.sxiCollapseButton];
        }
    }

    if (showButtons) {
        [self.view bringSubviewToFront:self.sxiClearAllButton];
        [self.view bringSubviewToFront:self.sxiCollapseButton];
    }

    NCNotificationShortLookView *lv = (NCNotificationShortLookView *)MSHookIvar<UIView *>(self, "_lookView");
    if (lv && [lv _notificationContentView] && [lv _notificationContentView].primaryLabel && [lv _notificationContentView].primaryLabel.textColor) {
        self.sxiNotificationCount.textColor = [[lv _notificationContentView].primaryLabel.textColor colorWithAlphaComponent:0.8];
    }

    if (lv) {
        lv.customContentView.hidden = !self.notificationRequest.sxiVisible;
        [lv _headerContentView].hidden = !self.notificationRequest.sxiVisible;

        if (!self.notificationRequest.sxiVisible) {
            lv.alpha = 0.7;
        } else {
            lv.alpha = 1.0;
        }
    }

    self.sxiNotificationCount.frame = CGRectMake(self.view.frame.origin.x + 11, self.view.frame.origin.y + self.view.frame.size.height - 30, self.view.frame.size.width - 21, 25);
    self.sxiNotificationCount.hidden = YES;
    self.sxiNotificationCount.alpha = 0.0;

    if (showButtons) {
        self.sxiClearAllButton.frame = CGRectMake(self.view.frame.origin.x + self.view.frame.size.width - 165, self.view.frame.origin.y + 5, 75, 25);
        self.sxiCollapseButton.frame = CGRectMake(self.view.frame.origin.x + self.view.frame.size.width - 80, self.view.frame.origin.y + 5, 75, 25);

        self.sxiClearAllButton.hidden = YES;
        self.sxiClearAllButton.alpha = 0.0;

        self.sxiCollapseButton.hidden = YES;
        self.sxiCollapseButton.alpha = 0.0;
    }

    if ([NSStringFromClass([self.view.superview class]) isEqualToString:@"UIView"] && self.notificationRequest.sxiIsStack && [self.notificationRequest.sxiStackedNotificationRequests count] > 0) {
        if (!self.notificationRequest.sxiIsExpanded) {
            self.sxiNotificationCount.hidden = NO;
            self.sxiNotificationCount.alpha = 1.0;

            int count = [self.notificationRequest.sxiStackedNotificationRequests count];
            if (count == 1) {
                self.sxiNotificationCount.text = [NSString stringWithFormat:@"%d more notification", count];
            } else {
                self.sxiNotificationCount.text = [NSString stringWithFormat:@"%d more notifications", count];
            }
        } else if (showButtons) {
            self.sxiClearAllButton.hidden = NO;
            self.sxiClearAllButton.alpha = 1.0;

            self.sxiCollapseButton.hidden = NO;
            self.sxiCollapseButton.alpha = 1.0;
        }
    }

    [self.view bringSubviewToFront:self.sxiNotificationCount];
}

- (void)_handleTapOnView:(id)arg1 {
    NSLog(@"[StackXI] tap");
    
    if (self.notificationRequest.sxiIsStack && !self.notificationRequest.sxiIsExpanded && [self.notificationRequest.sxiStackedNotificationRequests count] > 0) {
        [UIView animateWithDuration:TEMPDURATION animations:^{
            self.sxiNotificationCount.alpha = 0;
        }];
        [self.notificationRequest sxiExpand];
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
    [priorityList sxiUpdateList];
    [self.collectionViewLayout invalidateLayout];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    for (NSInteger row = 0; row < [self numberOfItemsInSection:0]; row++) {
        id c = [self _visibleCellForIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        if (!c) continue;

        NCNotificationListCell* cell = (NCNotificationListCell*)c;
        [self sendSubviewToBack:cell];
        [(NCNotificationShortLookViewController *)cell.contentViewController sxiUpdateCount];
    }
}

%new
-(void)sxiCollapseAll {
    NSMutableOrderedSet *sectionIDs = [[NSMutableOrderedSet alloc] initWithCapacity:100];

    for (NCNotificationRequest *request in priorityList.requests) {
        if (!request.bulletin.sectionID) continue;

        if (![sectionIDs containsObject:request.bulletin.sectionID] && request.sxiIsStack && request.sxiIsExpanded) {
            [request sxiCollapse];
            [sectionIDs addObject:request.bulletin.sectionID];
        }
    }

    [listCollectionView reloadData];
}

%new
-(void)sxiExpand:(NSString *)sectionID {
    NSMutableOrderedSet *sectionIDs = [[NSMutableOrderedSet alloc] initWithCapacity:100];
    [sectionIDs addObject:sectionID];

    for (NCNotificationRequest *request in priorityList.requests) {
        if (!request.bulletin.sectionID) continue;

        if (![sectionIDs containsObject:request.bulletin.sectionID] && request.sxiIsStack && request.sxiIsExpanded) {
            [request sxiCollapse];
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

            //[self sendSubviewToBack:cell];

            CGRect properFrame = cell.frame;
            cell.frame = frame;
            [UIView animateWithDuration:TEMPDURATION animations:^{
                cell.frame = properFrame;
            }];
        }
    }
}

%new
-(void)sxiCollapse:(NSString *)sectionID {
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

%hook NCNotificationListCollectionViewFlowLayout

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect {
	NSArray *attrs =  %orig;

    for (UICollectionViewLayoutAttributes *attr in attrs) {
        if (attr.size.height == 0) {
            attr.hidden = YES;
        } else {
            attr.hidden = NO;
        }
    }

    return attrs;
}

%end

%end

static void displayStatusChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (listCollectionView) {
        [listCollectionView sxiCollapseAll];
    }
}

%ctor{
    HBPreferences *file = [[HBPreferences alloc] initWithIdentifier:@"io.ominousness.stackxi"];
    bool enabled = [([file objectForKey:@"Enabled"] ?: @(YES)) boolValue];
    showButtons = [([file objectForKey:@"ShowButtons"] ?: @(NO)) boolValue];
    bool debug = false;

    if (enabled) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, displayStatusChanged, CFSTR("com.apple.iokit.hid.displayStatus"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        %init(StackXI);
        if (debug) %init(StackXIDebug);
    }
}
