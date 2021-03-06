//
//  TapImageView.m
//  Tabula
//
//  Created by Alexander Tewpin on 10/06/14.
//  Copyright (c) 2014 Alexander Tewpin. All rights reserved.
//

#import "TapImageView.h"

@implementation TapImageView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.contentMode = UIViewContentModeScaleAspectFill;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = YES;
    }
    return self;
}

- (void)resetSize {
    //поджатие картинок для борд с увеличенным превью типа mlp
    CGFloat tnHeight = self.tnHeight;
    CGFloat tnWidth = self.tnWidth;
    CGFloat i = 1;
    
    if (tnHeight > CELL_IMAGE_BOX_SIZE_PX || tnWidth > CELL_IMAGE_BOX_SIZE_PX) {
        if (tnHeight > tnWidth) {
            i = CELL_IMAGE_BOX_SIZE_PX/tnHeight;
        } else {
            i = CELL_IMAGE_BOX_SIZE_PX/tnWidth;
        }
        tnHeight = tnHeight*i;
        tnWidth = tnWidth*i;
    }
    
    self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, tnWidth/2, tnHeight/2);
}

- (void)resetToMediaSize {
    //используется, если в посте несколько картинок
    CGFloat tnHeight = self.tnHeight;
    CGFloat tnWidth = self.tnWidth;
    CGFloat i = 1;
    
    if (tnHeight > CELL_MEDIA_BOX_SIZE_PX || tnWidth > CELL_MEDIA_BOX_SIZE_PX) {
        if (tnHeight > tnWidth) {
            i = CELL_MEDIA_BOX_SIZE_PX/tnHeight;
        } else {
            i = CELL_MEDIA_BOX_SIZE_PX/tnWidth;
        }
        tnHeight = tnHeight*i;
        tnWidth = tnWidth*i;
    }
    
    self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, tnWidth/2, tnHeight/2);
}

- (void)shiftOnTextInset {
    self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y+CELL_TEXT_VIEW_V_INSET, self.frame.size.width, self.frame.size.height);
}

@end
