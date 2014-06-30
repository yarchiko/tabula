//
//  ThreadViewController.m
//  m2ch
//
//  Created by Александр Тюпин on 08/05/14.
//  Copyright (c) 2014 Alexander Tewpin. All rights reserved.
//

#import "ThreadViewController.h"
#import "BoardViewController.h"
#import "GetRequestViewController.h"
#import "UrlNinja.h"
#import "JTSImageViewController.h"
#import "JTSImageInfo.h"
#import "ThreadData.h"

@interface ThreadViewController ()

@end

@implementation ThreadViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerClass:[PostTableViewCell class] forCellReuseIdentifier:@"reuseIndenifier"];
    self.tableView.estimatedRowHeight = UITableViewAutomaticDimension;
    self.navigationItem.title = [NSString stringWithFormat:@"Тред в /%@/", self.boardId];
    self.isLoaded = NO;
    
    [[NSNotificationCenter defaultCenter]
     addObserverForName:UIContentSizeCategoryDidChangeNotification
     object:nil
     queue:[NSOperationQueue mainQueue]
     usingBlock:^(NSNotification *note) {
         [self.tableView reloadData];
     }];
    
    self.refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.refreshButton.frame = CGRectMake(0, 0, 320, 44);
    [self.refreshButton setTitle:@"Обновить тред" forState:UIControlStateNormal];
    [self.refreshButton setTitle:@"Загрузка..." forState:UIControlStateDisabled];
    [self.refreshButton addTarget:self action:@selector(loadUpdatedData) forControlEvents:UIControlEventTouchUpInside];
    self.refreshButton.hidden = YES;
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.color = [UIColor grayColor];
    self.spinner.center = CGPointMake(self.view.frame.size.width/2, self.view.frame.size.height/2-64);
    self.spinner.hidesWhenStopped = YES;
    [self.spinner startAnimating];
    
    [self.view addSubview:self.spinner];
    self.tableView.tableFooterView = self.refreshButton;
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    
    [self loadData];
}

#pragma mark - Data loading and creating

- (void)loadData {
    [self updateStarted];
    NSString *threadStringUrl = [NSString stringWithFormat:@"http://2ch.hk/makaba/mobile.fcgi?task=get_thread&board=%@&thread=%@&post=1", self.boardId, self.threadId];
    NSURL *threadUrl = [NSURL URLWithString:threadStringUrl];
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:threadUrl completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        [self masterThreadWithLocation:location];
    }];
    [task resume];
}

- (void)loadUpdatedData {
    [self updateStarted];
    NSString *lastNum = self.thread.linksReference[self.thread.linksReference.count-1];
    NSString *threadStringUrl = [NSString stringWithFormat:@"http://2ch.hk/makaba/mobile.fcgi?task=get_thread&board=%@&thread=%@&num=%@", self.boardId, self.threadId, lastNum];
    
    NSURL *threadUrl = [NSURL URLWithString:threadStringUrl];
    
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:threadUrl completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        [self childThreadWithLocation:location];
    }];
    [task resume];
}

- (void)masterThreadWithLocation:(NSURL *)location {
    NSData *data = [NSData dataWithContentsOfURL:location];
    //асинхронное задание по созданию массива
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        
        self.thread = [self createThreadWithData:data];
        NSString *comboId = [NSString stringWithFormat:@"%@%@", self.boardId, self.threadId];
        
        NSArray *positionArray = [ThreadData MR_findByAttribute:@"name" withValue:comboId];
        if (positionArray.count != 0) {
            ThreadData *position = positionArray[positionArray.count - 1];
            self.thread.startingPost = position.position;
        }
        
        //начинаем тред с последненнего прочитанного поста
        if (self.thread.startingPost) {
            NSUInteger postNum = [self.thread.linksReference indexOfObject:self.thread.startingPost];
            if (postNum == NSNotFound) {
                postNum = 0;
            } else {
                postNum += 1;
            }
            
            NSUInteger indexArray[] = {0, postNum};
            self.thread.startingRow = [NSIndexPath indexPathWithIndexes:indexArray length:2];
        }
        
        self.currentThread = [Thread currentThreadWithThread:self.thread andPosition:self.thread.startingRow];
        
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self performSelectorOnMainThread:@selector(creationEnded) withObject:nil waitUntilDone:YES];
            if ([self.currentThread.startingRow indexAtPosition:1] != 0) {
                [self.tableView scrollToRowAtIndexPath:self.currentThread.startingRow atScrollPosition:UITableViewScrollPositionTop animated:NO];
            }
        });
    });
}

- (void)childThreadWithLocation:(NSURL *)location {
    NSData *data = [NSData dataWithContentsOfURL:location];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        
        Thread *childThread = [self createThreadWithData:data];
        
        if (childThread.posts.count != 0) {
            [childThread.posts removeObjectAtIndex:0];
            [childThread.linksReference removeObjectAtIndex:0];
            
            [self.thread.posts addObjectsFromArray:childThread.posts];
            [self.thread.linksReference addObjectsFromArray:childThread.linksReference];
            
            self.currentThread.postsBottomLeft += childThread.posts.count;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self performSelectorOnMainThread:@selector(updateEnded) withObject:nil waitUntilDone:YES];
        });
    });

}

- (Thread *)createThreadWithData:(NSData *)data {
    
    NSError *dataError = nil;
    NSArray *dataArray = [NSArray array];
    
    //может прийти nil, если двач тупит, потом нужно написать обработку
    if (data) {
        dataArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&dataError];
        if (dataError) {
            NSLog(@"JSON Error: %@", dataError);
            return nil;
        }
    }
    
    Thread *thread = [[Thread alloc]init];
    thread.posts = [NSMutableArray array];
    thread.linksReference = [NSMutableArray array];
    
    for (NSDictionary *dic in dataArray) {
        Post *post = [Post postWithDictionary:dic andBoardId:self.boardId];
        [thread.posts addObject:post];
        [thread.linksReference addObject:[NSString stringWithFormat:@"%ld", (long)post.num]];
    }
    return thread;
}

#pragma mark - Data updating

- (void)updateStarted {
    self.refreshButton.enabled = NO;
    self.isLoaded = NO;
}

- (void)creationEnded {
    //обновление таблицы бросает исключения автолейаута, если нажать на назад пока оно выполняется, но программу это не крашит
    [self.tableView reloadData];
    self.refreshButton.enabled = YES;
    self.refreshButton.hidden = NO;
    self.isLoaded = YES;
    [self.spinner stopAnimating];
    [self updateLastPost];
}

- (void)updateEnded {
    [self loadMorePostsBottom];
    self.refreshButton.enabled = YES;
    self.isLoaded = YES;
    [self updateLastPost];
}

- (void)updateLastPost {
    //запись последнего поста в БД
    NSString *position = self.thread.linksReference[self.thread.linksReference.count-1];
    NSString *comboId = [NSString stringWithFormat:@"%@%@", self.boardId, self.threadId];
    NSNumber *count = [NSNumber numberWithInteger:self.thread.posts.count];
    
    //надо бы вписать этот объект как проперти, но сейчас нет времени на тестинг
    NSArray *positionArray = [ThreadData MR_findByAttribute:@"name" withValue:comboId];
    for (ThreadData *threadData in positionArray) {
        [threadData MR_deleteEntity];
    }
    
    [MagicalRecord saveWithBlock:^(NSManagedObjectContext *localContext) {
        ThreadData *localThreadData = [ThreadData MR_createInContext:localContext];
        localThreadData.name = comboId;
        localThreadData.position = position;
        localThreadData.count = count;
    }];
}

#pragma mark - Session stuff
//чтобы компилятор не ругался

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location{
    
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes {
    
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.currentThread.posts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PostTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reuseIndenifier"];
    
    [cell updateFonts];
    
    Post *post = self.currentThread.posts[indexPath.row];
    
    [cell setPost:post];
    
    [cell setNeedsUpdateConstraints];
    [cell updateConstraintsIfNeeded];
    
    cell.comment.delegate = self;
    
    UITapGestureRecognizer *tgr = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(imageTapped:)];
    UILongPressGestureRecognizer *lpgr = [[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(postLongPress:)];
    
    lpgr.minimumPressDuration = 0.5;
    [cell.comment setTag:cell.num];
    
    tgr.delegate = self;
    lpgr.delegate = self;
    
    [cell addGestureRecognizer:lpgr];
    [cell.postImage addGestureRecognizer:tgr];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (self == self.navigationController.topViewController) {
        
        Post *post = self.currentThread.posts[indexPath.row];
        
        if (post.postHeight) {
            return post.postHeight;
        } else {
        
            PostTableViewCell *cell = [[PostTableViewCell alloc]init];
            
            [cell setTextPost:post];
            
            [cell setNeedsUpdateConstraints];
            [cell updateConstraintsIfNeeded];
            
            cell.bounds = CGRectMake(0.0f, 0.0f, CGRectGetWidth(tableView.bounds), CGRectGetHeight(cell.bounds));
            
            [cell setNeedsLayout];
            [cell layoutIfNeeded];
            
            CGFloat height = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
            
            height += 1;
            post.postHeight = height;
            [self.currentThread.posts removeObjectAtIndex:indexPath.row];
            [self.currentThread.posts insertObject:post atIndex:indexPath.row];
            
            return height;
        }
    }
    
    return 0;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionCurveEaseInOut animations:^
     {
         [[self.tableView cellForRowAtIndexPath:indexPath] setSelected:NO animated:YES];
     } completion: NULL];
}

#pragma mark - Posting and draft handling

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"newPost"]) {
        UINavigationController *navigationController = segue.destinationViewController;
        GetRequestViewController *destinationController = (GetRequestViewController *)navigationController.topViewController;
        [destinationController setBoardId:self.boardId];
        [destinationController setThreadId:self.threadId];
        [destinationController setDraft:self.thread.postDraft];
        destinationController.postView.text = self.thread.postDraft;
        destinationController.delegate = self;
    }
}

- (void)postCanceled:(NSString *)draft{
    self.thread.postDraft = draft;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)postPosted {
    [self loadUpdatedData];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - TTTAttributedLabelDelegate

- (void)attributedLabel:(__unused TTTAttributedLabel *)label didSelectLinkWithURL:(NSURL *)url {

    UrlNinja *urlNinja = [UrlNinja unWithUrl:url];
    
    switch (urlNinja.type) {
        case boardLink: {
            //открыть борду
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:nil];
            BoardViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"BoardTag"];
            controller.boardId = urlNinja.boardId;
            [self.navigationController pushViewController:controller animated:YES];
            break;
        }
        case boardThreadLink: {
            //открыть тред
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:nil];
            ThreadViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"ThreadTag"];
            controller.boardId = urlNinja.boardId;
            controller.threadId = urlNinja.threadId;
            
            //без этого фачится размер заголовка
            controller.navigationItem.title = [NSString stringWithFormat:@"Тред в /%@/", urlNinja.boardId];

            [self.navigationController pushViewController:controller animated:YES];
            break;
        }
        case boardThreadPostLink:
            //проскроллить страницу
            if ([urlNinja.boardId isEqualToString:self.boardId] && [urlNinja.threadId isEqualToString:self.threadId]) {
                NSIndexPath *index = [NSIndexPath indexPathForRow:[self.thread.linksReference indexOfObject:urlNinja.postId] inSection:0];
                [self.tableView scrollToRowAtIndexPath:index atScrollPosition:UITableViewScrollPositionTop animated:YES];
                }
                //открыть тред и проскроллить страницу
                else {
                    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:nil];
                    ThreadViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"ThreadTag"];
                    controller.boardId = urlNinja.boardId;
                    controller.threadId = urlNinja.threadId;
                    controller.postId = urlNinja.postId;
                    [self.navigationController pushViewController:controller animated:YES];
                    break;
                }
            break;
        default: {
            //внешня ссылка - предложение открыть в сафари
            UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:[url absoluteString] delegate:self cancelButtonTitle:NSLocalizedString(@"Отмена", nil) destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Открыть ссылку в Safari", nil), nil];
            actionSheet.tag = 2;
            [actionSheet showInView:self.view];
            break;
        }
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if(actionSheet.tag == 1) // лонгпресс по посту
    {
        if (buttonIndex == actionSheet.cancelButtonIndex) {
            return;
        } else if (buttonIndex == 0) { // ответить
            if (![self.thread.postDraft isEqualToString:@""] && self.thread.postDraft) {
                self.thread.postDraft = [NSString stringWithFormat:@"%@%@\n", self.thread.postDraft, self.reply];
            } else {
                self.thread.postDraft = [NSString stringWithFormat:@"%@\n", self.reply];
            }
        } else if (buttonIndex == 1) { //ответ с цитатой
            if (![self.thread.postDraft isEqualToString:@""] && self.thread.postDraft) {
                self.thread.postDraft = [NSString stringWithFormat:@"%@\n%@\n%@\n", self.thread.postDraft, self.reply, self.quote];
            } else {
                self.thread.postDraft = [NSString stringWithFormat:@"%@\n%@\n", self.reply, self.quote];
            }
        }
        
        [self performSegueWithIdentifier:@"newPost" sender:self];
        
    } else if (actionSheet.tag == 2) { //клик по ссылке
        if (buttonIndex == actionSheet.cancelButtonIndex) {
            return;
        }
        //кстати, на конфе видел, что это хуевое решение, потому что юиаппликейнеш не должен за это отвечать и это как-то решается через делегирование
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:actionSheet.title]];
    }
}

- (void)imageTapped:(UITapGestureRecognizer *)sender {

    TapImageView *image = (TapImageView *)sender.view;
    // Create image info
    JTSImageInfo *imageInfo = [[JTSImageInfo alloc] init];
    
    NSLog(@"%@", image.bigImageUrl);
    imageInfo.imageURL = image.bigImageUrl;
    imageInfo.referenceRect = image.frame;
    imageInfo.referenceView = image.superview;
    
    // Setup view controller
    JTSImageViewController *imageViewer = [[JTSImageViewController alloc]
                                           initWithImageInfo:imageInfo
                                           mode:JTSImageViewControllerMode_Image
                                           backgroundStyle:JTSImageViewControllerBackgroundStyle_ScaledDimmed];
    
    // Present the view controller.
    [imageViewer showFromViewController:self transition:JTSImageViewControllerTransition_FromOffscreen];
}

- (void)postLongPress:(UIGestureRecognizer *)sender {
    
    if (sender.state == UIGestureRecognizerStateBegan){
        PostTableViewCell *cell = (PostTableViewCell *)sender.view;
        TTTAttributedLabel *post = cell.comment;
//        TTTAttributedLabel *post = (TTTAttributedLabel *)sender.view;
        self.reply = [@">>" stringByAppendingString:[NSString stringWithFormat:@"%ld", (long)cell.num]];
        self.quote = [self makeQuote:post.text];
    
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:
          NSLocalizedString(@"Отмена", nil) destructiveButtonTitle:nil otherButtonTitles:
          NSLocalizedString(@"Ответить", nil),
          NSLocalizedString(@"Ответить с цитатой", nil), nil];
        actionSheet.tag = 1;
        [actionSheet showInView:self.view];
    }
}

- (NSString *)makeQuote:(NSString *)sourceString {
    NSMutableString *mString = [sourceString mutableCopy];
    NSMutableArray *resultArray = [NSMutableArray array];
    NSRegularExpression *quoteReg = [NSRegularExpression regularExpressionWithPattern:@"^.+$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    [quoteReg enumerateMatchesInString:sourceString options:0 range:NSMakeRange(0, sourceString.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        [resultArray addObject:result];
    }];
    NSInteger shift = 0;
    for (NSTextCheckingResult *result in resultArray) {
        [mString insertString:@">" atIndex:result.range.location + shift];
        shift ++;
    }
    return mString;
}

#pragma mark - Loading and refreshing

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if ((self.tableView.contentSize.height - self.tableView.contentOffset.y) < 5000 && self.isLoaded == YES && self.currentThread.postsBottomLeft !=0 && self.isUpdating == NO) {
        [self loadMorePostsBottom];
    }
    if (self.tableView.contentOffset.y < 5000 && self.isLoaded == YES && self.currentThread.postsTopLeft !=0 && self.isUpdating == NO) {
        [self loadMorePostsTop];
    }
}

- (void)loadMorePostsTop {
    self.isUpdating = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        
        NSInteger i = 0;
        CGPoint newContentOffset = CGPointMake(0, 0);
        
        if (self.currentThread.postsTopLeft > 50) {
            i = 50;
        }
        else {
            i = self.currentThread.postsTopLeft;
        }
        
        for (int k = 0; k < i; k++) {
            newContentOffset.y += [self heightForPost:[self.thread.posts objectAtIndex:self.currentThread.postsTopLeft+k-i]];
        }
        
        [self.currentThread insertMoreTopPostsFrom:self.thread];
        newContentOffset.y += self.tableView.contentOffset.y;
        
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self.tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
            [self.tableView setContentOffset:newContentOffset];
            self.isUpdating = NO;
        });
    });
}

- (void)loadMorePostsBottom {
    self.isUpdating = YES;
    self.refreshButton.enabled = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        [self.currentThread insertMoreBottomPostsFrom:self.thread];
        [self cacheHeightsForUpdatedIndexes];
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self.tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
            [self updateLastPost];
            self.refreshButton.enabled = YES;
            self.isUpdating = NO;
        });
    });
}

- (CGFloat)cacheHeightsForUpdatedIndexes {
    CGFloat height = 0;
    for (NSIndexPath *indexPath in self.currentThread.updatedIndexes)
        height += [self.tableView.delegate tableView:self.tableView heightForRowAtIndexPath:indexPath];
    return height;
}

- (CGFloat)heightForPost:(Post *)post {
    
    if (self == self.navigationController.topViewController) {
        
        if (post.postHeight) {
            return post.postHeight;
        } else {
            
            PostTableViewCell *cell = [[PostTableViewCell alloc]init];
            
            [cell setTextPost:post];
            
            [cell setNeedsUpdateConstraints];
            [cell updateConstraintsIfNeeded];
            
            cell.bounds = CGRectMake(0.0f, 0.0f, CGRectGetWidth(self.tableView.bounds), CGRectGetHeight(cell.bounds));
            
            [cell setNeedsLayout];
            [cell layoutIfNeeded];
            
            CGFloat height = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
            
            height += 1;
            post.postHeight = height;
            
            return height;
        }
    }
    
    return 0;
}

@end
