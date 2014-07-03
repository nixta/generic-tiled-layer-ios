//
//  AGSProcessedTiledMapServiceLayer.m
//  tiled-layer-generic
//
//  Created by Nicholas Furness on 8/3/13.
//  Copyright (c) 2013 Esri. All rights reserved.
//

#import "AGSCoreImageFilteredTiledMapServiceLayer.h"


@interface AGSCoreImageFilteredTiledMapServiceLayer() <AGSLayerDelegate>
@property (nonatomic, strong) AGSTiledServiceLayer * wrappedTiledLayer;
@property (nonatomic, copy) AGSCITileProcessingBlock processBlock;
@end


@implementation AGSCoreImageFilteredTiledMapServiceLayer
#pragma mark - Initializer
-(id)initWithTiledLayer:(AGSTiledServiceLayer *)wrappedTiledLayer processBlock:(AGSCITileProcessingBlock)block
{
    self = [super init];
    if (self) {
        self.wrappedTiledLayer = wrappedTiledLayer;
        self.processBlock = block;
        if (!self.processBlock) {
            self.processBlock = ^(NSData *inputImageData) {
                NSLog(@"Implement a block to process tile data on the way to the map!");
                return inputImageData;
            };
        }
    }
    return self;
}

#pragma mark - Layer Status Control
-(void)setMapView:(AGSMapView *)mapView {
    [super setMapView:mapView];
    if (self.wrappedTiledLayer.loaded) {
        [self layerDidLoad];
    } else {
        self.wrappedTiledLayer.delegate = self;
    }
}

-(void)layerDidLoad:(AGSLayer *)layer
{
    if (layer == self.wrappedTiledLayer) {
        [self layerDidLoad];
    }
}



#pragma mark - Impersonation Overrides for Contained Layer Properties
-(AGSTileInfo *)tileInfo
{
    return self.wrappedTiledLayer.tileInfo;
}

-(AGSEnvelope *)fullEnvelope
{
    return self.wrappedTiledLayer.fullEnvelope;
}

-(AGSEnvelope *)initialEnvelope
{
    return self.wrappedTiledLayer.initialEnvelope;
}

-(AGSSpatialReference *)spatialReference
{
    return self.wrappedTiledLayer.spatialReference;
}



#pragma mark - Impersonation Overrides for Tile Requests on Contained Layer
-(void)requestTileForKey:(AGSTileKey *)key
{
    NSURL *tileURL = [self.wrappedTiledLayer urlForTileKey:key];
    NSURLRequest *req = [NSURLRequest requestWithURL:tileURL];
    NSError *error = nil;
    NSData *data = [AGSRequest dataForRequest:req error:&error];
    if (!error) {
        [self setTileData:self.processBlock(data) forKey:key];
    } else {
        NSLog(@"Error getting tile %@ from %@: %@", key, tileURL, error);
    }
}



#pragma mark - Convenience Generators with Core Image Filter
+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithURL:(NSURL *)tiledLayerURL imageFilter:(CIFilter *)filter
{
    return [AGSCoreImageFilteredTiledMapServiceLayer tiledLayerWithURL:tiledLayerURL imageFilters:@[filter]];
}

+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithURL:(NSURL *)tiledLayerURL credential:(AGSCredential *)credential imageFilter:(CIFilter *)filter
{
    return [AGSCoreImageFilteredTiledMapServiceLayer tiledLayerWithURL:tiledLayerURL credential:credential imageFilters:@[filter]];
}

+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithTiledLayer:(AGSTiledServiceLayer *)tiledLayer imageFilter:(CIFilter *)filter
{
    return [AGSCoreImageFilteredTiledMapServiceLayer tiledLayerWithTiledLayer:tiledLayer imageFilters:@[filter]];
}



#pragma mark - Convenience Generators with Array of Core Image Filters
+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithURL:(NSURL *)tiledLayerURL imageFilters:(NSArray *)filters
{
    return [AGSCoreImageFilteredTiledMapServiceLayer tiledLayerWithURL:tiledLayerURL credential:nil imageFilters:filters];
}

+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithURL:(NSURL *)tiledLayerURL credential:(AGSCredential *)credential imageFilters:(NSArray *)filters
{
    AGSCITileProcessingBlock block = [AGSCoreImageFilteredTiledMapServiceLayer blockWithCIFilters:filters];
    return [AGSCoreImageFilteredTiledMapServiceLayer tiledLayerWithURL:tiledLayerURL credential:credential processBlock:block];
}

+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithTiledLayer:(AGSTiledServiceLayer *)tiledLayer imageFilters:(NSArray *)filters
{
    AGSCITileProcessingBlock block = [AGSCoreImageFilteredTiledMapServiceLayer blockWithCIFilters:filters];
    return [AGSCoreImageFilteredTiledMapServiceLayer tiledLayerWithTiledLayer:tiledLayer processBlock:block];
}



#pragma mark - Convenience Generators with Block
+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithURL:(NSURL *)tiledLayerURL processBlock:(AGSCITileProcessingBlock)block
{
    return [AGSCoreImageFilteredTiledMapServiceLayer tiledLayerWithURL:tiledLayerURL credential:nil processBlock:block];
}

+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithURL:(NSURL *)tiledLayerURL credential:(AGSCredential *)credential processBlock:(AGSCITileProcessingBlock)block
{
    AGSTiledServiceLayer *tiledLayer = [AGSTiledMapServiceLayer tiledMapServiceLayerWithURL:tiledLayerURL credential:credential];
    return [AGSCoreImageFilteredTiledMapServiceLayer tiledLayerWithTiledLayer:tiledLayer processBlock:block];
}

+(AGSCoreImageFilteredTiledMapServiceLayer *)tiledLayerWithTiledLayer:(AGSTiledServiceLayer *)tiledLayer processBlock:(AGSCITileProcessingBlock)block
{
    return [[AGSCoreImageFilteredTiledMapServiceLayer alloc] initWithTiledLayer:tiledLayer processBlock:block];
}



#pragma mark - Predefined Filter Blocks
+(AGSCITileProcessingBlock)blockWithCIFilters:(NSArray *)filters
{
    return ^(NSData *tileData){
        CIContext *context = [CIContext contextWithOptions:nil];

        CIImage *workingFilterResult = [CIImage imageWithData:tileData];
        CGRect initialExtent = workingFilterResult.extent;
        for (CIFilter *filter in filters) {
            CIFilter *workingFilter = [filter copy]; // CIFilter is not threadsafe
            [workingFilter setValue:workingFilterResult forKey:kCIInputImageKey];
            workingFilterResult = workingFilter.outputImage;
        }
        CGImageRef cgiRef = [context createCGImage:workingFilterResult fromRect:[workingFilterResult extent]];
        UIImage *outImage = [UIImage imageWithCGImage:cgiRef];
        CGImageRelease(cgiRef);
        
        if (initialExtent.size.width < outImage.size.width) {
            // Experimental - in the case where images grow, crop them
            UIImage *inImage = [UIImage imageWithData:tileData];
            CGRect newFrame = CGRectMake(2, 6, inImage.size.width, inImage.size.height);
            CGImageRef newRef = CGImageCreateWithImageInRect(outImage.CGImage, newFrame);
            outImage = [UIImage imageWithCGImage:newRef];
        }
        return UIImagePNGRepresentation(outImage);
    };
}
@end