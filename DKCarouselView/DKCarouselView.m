//
//  DKCarouselView.m
//  DKCarouselView
//
//  Created by ZhangAo on 10/31/11.
//  Modified by Jiyee Sheng on 02/11/15
//  Copyright 2011 DKCarouselView. All rights reserved.
//

#import "DKCarouselView.h"
#import "UIImageView+WebCache.h"

typedef void(^TapBlock)();
typedef void(^PageBlock)();

@interface DKImageViewTap : UIImageView

@property (nonatomic, assign) BOOL enable;
@property (nonatomic, copy) TapBlock tapBlock;

@end

@implementation DKImageViewTap

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = YES;
        self.enable = YES;
    }
    return self;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.enable) return;
    if (self.tapBlock) {
        self.tapBlock();
    }
    [[self nextResponder] touchesEnded:touches withEvent:event];
}

@end

////////////////////////////////////////////////////////////////////////////////////////

@implementation DKCarouselItem

@end

@implementation DKCarouselURLItem

@end

@implementation DKCarouselViewItem

@end

////////////////////////////////////////////////////////////////////////

#define GetPreviousIndex()          (self.currentPage - 1 < 0 ? self.carouselItemViews.count - 1 : self.currentPage - 1)
#define GetNextIndex()              (self.currentPage + 1 >= self.carouselItemViews.count ? 0 : self.currentPage + 1)
#define kScrollViewFrameWidth       CGRectGetWidth(self.scrollView.bounds)
#define kScrollViewFrameHeight      CGRectGetHeight(self.scrollView.bounds)
#define kTouchPreviousBoundary      (self.finite && self.currentPage == 0)
#define kTouchNextBoundary          (self.finite && self.currentPage == self.carouselItemViews.count - 1)

@interface DKCarouselView () <UIScrollViewDelegate>
@property (nonatomic, assign) NSInteger currentPage;

@property (nonatomic, weak) UIScrollView *scrollView;
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, strong) NSMutableArray *carouselItemViews;
@property (nonatomic, weak) UIPageControl *pageControl;
@property (nonatomic, assign) CGRect lastRect;

@property (nonatomic, strong) NSTimer *autoPagingTimer;
@property (nonatomic, copy) ItemDidClicked itemClickedBlock;
@property (nonatomic, copy) ItemDidPaged itemPagedBlock;

@end

@implementation DKCarouselView

@dynamic numberOfItems;

// Subclasses can override this method to perform any custom initialization
// this method is not called when your view objects are subsequently loaded from the nib file
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self awakeFromNib];
    }
    
    return self;
}

// Typically, you implement awakeFromNib for objects that require additional set up that cannot be done at design time.
- (void)awakeFromNib {
    [super awakeFromNib];

    self.finite = NO;
    self.currentPage = 0;
    self.lastRect = CGRectZero;
    [self setCarouselItemViews:[[NSMutableArray alloc] initWithCapacity:5]];
    
    UIScrollView *scrollView = [UIScrollView new];
    scrollView.showsHorizontalScrollIndicator = scrollView.showsVerticalScrollIndicator = NO;
    scrollView.pagingEnabled = YES;
    scrollView.bounces = NO;
    scrollView.delegate = self;

    self.indicatorTintColor = [UIColor lightGrayColor];

    UIPageControl *pageControl = [UIPageControl new];
    pageControl.currentPageIndicatorTintColor = self.indicatorTintColor;
    pageControl.userInteractionEnabled = NO;

    [self addSubview:scrollView];
    self.scrollView = scrollView;

    [self addSubview:pageControl];
    self.pageControl = pageControl;

    self.clipsToBounds = YES;
}

// Subclasses can override this method as needed to perform more precise layout of their subviews.
// You should override this method only if the autoresizing and constraint-based behaviors of the subviews do not offer the behavior you want.
// You can use your implementation to set the frame rectangles of your subviews directly.
- (void)layoutSubviews {
    [super layoutSubviews];

    if (CGRectEqualToRect(self.lastRect, self.frame)) return;
    self.lastRect = self.frame;

    self.scrollView.frame = self.bounds;

    if (self.carouselItemViews.count == 0) {
        return;
    }

    [self setupViews];

    CGRect frame;
    frame.size = [self.pageControl sizeForNumberOfPages:self.pageControl.numberOfPages];
    frame.origin = CGPointMake(CGRectGetWidth(self.bounds) / 2 - frame.size.width / 2,
            CGRectGetHeight(self.bounds) - frame.size.height);
    self.pageControl.frame = frame;
}

// The default implementation of this method does nothing.
// Subclasses can override it to perform additional actions whenever the superview changes.
- (void)willMoveToSuperview:(UIView *)newSuperview {
    [super willMoveToSuperview:newSuperview];

    if (newSuperview == nil) {
        [self.autoPagingTimer invalidate];
        self.autoPagingTimer = nil;
    }
}

// You should typically not override this method—instead you should put “clean-up” code in prepareForDeletion or didTurnIntoFault.
- (void)dealloc {
    [self.autoPagingTimer invalidate];
}


#pragma mark - Public API

// Overload default property method.
- (void)setIndicatorTintColor:(UIColor *)indicatorTintColor {
    _indicatorTintColor = indicatorTintColor;
    
    self.pageControl.currentPageIndicatorTintColor = indicatorTintColor;
}

-(void)setItems:(NSArray *)items {
    if (items == nil) return;
    
    [self.carouselItemViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self.carouselItemViews removeAllObjects];
    self.pageControl.numberOfPages = 0;
    
    if (items.count == 0) return;

    _items = nil;
    _items = [items copy];

    self.pageControl.numberOfPages = _items.count;
    self.pageControl.currentPage = self.currentPage = 0;
    
    _scrollView.scrollEnabled = _items.count > 1;
    
    NSInteger index = 0;
    for (DKCarouselItem *item in _items) {
        DKImageViewTap *itemView = [DKImageViewTap new];

        itemView.userInteractionEnabled = YES;
        if ([item isKindOfClass:[DKCarouselURLItem class]]) {
            NSString *imageUrl = [(DKCarouselURLItem *)item imageUrl];
            [itemView sd_setImageWithURL:[NSURL URLWithString:imageUrl] placeholderImage:self.defaultImage];
        } else if ([item isKindOfClass:[DKCarouselViewItem class]]) {
            UIView *customView = [(DKCarouselViewItem *)item view];
            [itemView addSubview:customView];
            customView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        } else {
            assert(0);
        }
        
        [itemView setTapBlock:^ {
            if (self.itemClickedBlock != nil) {
                self.itemClickedBlock(item, index);
            }
        }];

        index++;
        [self.carouselItemViews addObject:itemView];
    }

    [self setupViews];
    self.lastRect = CGRectZero;
    
    [self setNeedsLayout];
}

- (void)setItemClickedBlock:(ItemDidClicked)itemClickedBlock {
    _itemClickedBlock = itemClickedBlock;
}

- (void)setItemPagedBlock:(ItemDidPaged)itemPagedBlock {
    _itemPagedBlock = itemPagedBlock;
}

- (void)setAutoPagingForInterval:(NSTimeInterval)timeInterval {
    assert(timeInterval >= 0);
    if (self.autoPagingTimer.timeInterval == timeInterval) {
        [self setPause:NO];
        return;
    }

    if (self.autoPagingTimer) {
        [self.autoPagingTimer invalidate];
        self.autoPagingTimer = nil;
        if (timeInterval == 0) return;
    }

    self.autoPagingTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval
                                                            target:self
                                                          selector:@selector(pagingNext)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)pagingNext {
    if (self.pageControl.numberOfPages > 0) {
        if (kTouchPreviousBoundary) {
            [self.scrollView setContentOffset:CGPointMake(kScrollViewFrameWidth, 0) animated:YES];
        } else if (kTouchNextBoundary) {
            return;
        } else {
            [self.scrollView setContentOffset:CGPointMake(2 * kScrollViewFrameWidth, 0) animated:YES];
        }
    }
}

- (void)setPause:(BOOL)pause {
    if (self.autoPagingTimer.timeInterval == 0) return;
    if (_pause == pause) return;
    if (!self.autoPagingTimer) return;
    _pause = pause;
    if (pause) {
        self.autoPagingTimer.fireDate = [NSDate distantFuture];
    } else {
        self.autoPagingTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:self.autoPagingTimer.timeInterval];
    }
}

- (NSUInteger)numberOfItems {
    return self.items.count ? self.items.count : 0;
}

- (void)setupViews {
    [self.carouselItemViews makeObjectsPerformSelector:@selector(removeFromSuperview)];

//    NSLog(@"currentPage at setupViews: %lu",self.currentPage);
    CGFloat originX,
            originY = 0;

    if (kTouchPreviousBoundary) {
        originX = 0;
        self.scrollView.contentSize = CGSizeMake(kScrollViewFrameWidth * 2, kScrollViewFrameHeight);
    } else if (kTouchNextBoundary) {
        originX = CGRectGetWidth(self.scrollView.bounds);
        self.scrollView.contentSize = CGSizeMake(kScrollViewFrameWidth * 2, kScrollViewFrameHeight);
    } else {
        originX = CGRectGetWidth(self.scrollView.bounds);
        self.scrollView.contentSize = CGSizeMake(kScrollViewFrameWidth * 3, kScrollViewFrameHeight);
    }

    if (!kTouchPreviousBoundary) {
        [self insertPreviousPage];
    }

    self.scrollView.contentOffset = CGPointMake(originX, originY);

    UIView *currentView = self.carouselItemViews[self.currentPage];
    currentView.frame = CGRectMake(originX, originY, kScrollViewFrameWidth, kScrollViewFrameHeight);
    [self.scrollView addSubview:currentView];

    if (!kTouchNextBoundary) {
        [self insertNextPage];
    }

    [self setNeedsLayout];
}

- (void)insertPreviousPage {
//    NSLog(@"insert previous page");
    NSInteger index = GetPreviousIndex();
    UIView *currentView = self.carouselItemViews[index];
    if (kTouchNextBoundary) {
        currentView.frame = CGRectMake(0, 0, kScrollViewFrameWidth, kScrollViewFrameHeight);
    } else {
        currentView.frame = CGRectMake(0, 0, kScrollViewFrameWidth, kScrollViewFrameHeight);
    }
    [self.scrollView addSubview:currentView];
}

- (void)insertNextPage {
//    NSLog(@"insert next page");
    NSInteger index = GetNextIndex();
    UIView *currentView = self.carouselItemViews[index];

    if (kTouchPreviousBoundary) {
        currentView.frame = CGRectMake(kScrollViewFrameWidth, 0,
                kScrollViewFrameWidth, kScrollViewFrameHeight);
    } else {
        currentView.frame = CGRectMake(kScrollViewFrameWidth * 2, 0,
                kScrollViewFrameWidth, kScrollViewFrameHeight);
    }

    [self.scrollView addSubview:currentView];
}

#pragma mark UIScrollView Delegate Methods
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.isDragging) {
        self.autoPagingTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:self.autoPagingTimer.timeInterval];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    NSInteger currentOffsetIndex = scrollView.contentOffset.x / kScrollViewFrameWidth;
    NSInteger minmiumOffsetIndex = 0;
    NSInteger maxmiumOffsetIndex = scrollView.contentSize.width / kScrollViewFrameWidth - 1;

//    NSLog(@"cur:%lu, min:%lu, max:%lu", currentOffsetIndex, minmiumOffsetIndex, maxmiumOffsetIndex);

    if (currentOffsetIndex == minmiumOffsetIndex) { //  scroll to previous page

        if (kTouchPreviousBoundary) return; // lock scroll direction from left to right at begin item.

        self.currentPage = GetPreviousIndex();

        if (self.itemPagedBlock != nil) {
            self.itemPagedBlock(self, self.currentPage);
        }
//        NSLog(@"currentPage at didEnd: %lu",self.currentPage);
        [self setupViews];
    } else if (currentOffsetIndex == maxmiumOffsetIndex) {  // scroll to next page

        if (kTouchNextBoundary) return;

        self.currentPage = GetNextIndex();

        if (self.itemPagedBlock != nil) {
            self.itemPagedBlock(self, self.currentPage);
        }
//        NSLog(@"currentPage at didEnd: %lu",self.currentPage);
        [self setupViews];
    }

//    NSLog(@"last currentPage: %lu", self.currentPage);

    self.pageControl.currentPage = self.currentPage;
}

// 针对scrollRectVisible:animated:
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    [self scrollViewDidEndDecelerating:scrollView];
}

@end