//
//  JBAppDelegate.m
//  JSONBenchmarks
//
//  Created by Sam Soffes on 11/4/09.
//  Copyright 2009 Sam Soffes. All rights reserved.
//

#import "JBAppDelegate.h"
#import "JBResultsViewController.h"
#import "JBConstants.h"
#import "JSONParser.h"
#import "JSONWriter.h"
#import "SBJsonParser.h"
#import "SBJsonWriter.h"
#import "JSONKit.h"
#import "CJSONDeserializer.h"
#import "CJSONSerializer.h"
#import "NSObject+YAJL.h"
#import "SBStatistics.h"

// Number of iterations to run
#define kIterations 100

// Run five times so block overhead is less of a factor
#define x(x) do { x; x; x; x; x; } while (0)

// Comparer function for sorting
static int _compareResults(NSDictionary *result1, NSDictionary *result2, void *context) {
	return [[result1 objectForKey:JBAverageTimeKey] compare:[result2 objectForKey:JBAverageTimeKey]];
}

// Benchmark function
static inline void bench(NSString *what, NSString *direction, void (^block)(void), NSMutableArray *results) {
	
	SBStatistics *stats = [[SBStatistics new] autorelease];

	for (NSInteger i = 0; i < kIterations; i++) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSDate *before = [NSDate date];
		block();
		[stats addDouble:-[before timeIntervalSinceNow] * 1000];
		[pool release];
	}
	
	[results addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						what, JBLibraryKey,
						[NSNumber numberWithDouble:stats.mean], JBAverageTimeKey,
							   nil]];
	
	NSLog(@"%@ %@ min/mean/max (ms): %.3f/%.3f/%.3f - stddev: %.3f", what, direction, stats.min, stats.mean, stats.max, [stats standardDeviation]);
}

@implementation JBAppDelegate

#pragma mark NSObject

- (void)dealloc {
	[_navigationController release];
	[_window release];
	[super dealloc];
}

#pragma mark Benchmarking


- (void)benchmark {
	// This could obviously be better, but I'm trying to keep things simple.
	
	// Configuration
	NSLog(@"Starting benchmarks with %i iterations for each library", kIterations);
	NSStringEncoding stringEncoding = NSUTF8StringEncoding;
	NSStringEncoding dataEncoding = stringEncoding; // NSUTF32BigEndianStringEncoding;	
	
	// Setup result arrays
	NSMutableArray *readingResults = [[NSMutableArray alloc] init];
	NSMutableArray *writingResults = [[NSMutableArray alloc] init];
	
	// Load JSON string
	NSString *jsonString = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"twitter_public_timeline" ofType:@"json"] encoding:stringEncoding error:nil];
	NSData *jsonData = [jsonString dataUsingEncoding:dataEncoding];
	NSArray *array = (NSArray *)[[CJSONDeserializer deserializer] deserialize:jsonData error:nil];
		
	
	
	
	// generate new data for benchmark
	// given json data can not be serialized to plist (null values?)
	NSInteger totalElements = 1000;
	
	NSMutableArray *generatedData = [NSMutableArray arrayWithCapacity:totalElements];
	for (NSInteger elementCount = 0; elementCount < totalElements; elementCount++)
	{
		[generatedData addObject:@"ABCEDFGHIJKLMNOPQRSTUVWXYZ"];
	}
	
	// overwrite data to be used for benchmark
	array = generatedData;
	jsonString = [JSON stringWithObject:array options:0 error:nil];
	jsonData = [jsonString dataUsingEncoding:dataEncoding];
	
	
	NSString *errorDescription = nil;
	// generating XML plist data
	NSData *XMLPlistData = [NSPropertyListSerialization dataFromPropertyList:array
																		  format:NSPropertyListXMLFormat_v1_0
																errorDescription:&errorDescription];
	
	NSAssert1(XMLPlistData != nil, @"error serializing array: %@", errorDescription);
	
	//generating binary plist data
	NSData *binaryPlistData = [NSPropertyListSerialization dataFromPropertyList:array
																	  format:NSPropertyListBinaryFormat_v1_0
															errorDescription:&errorDescription];
	NSAssert1(binaryPlistData != nil, @"error serializing array: %@", errorDescription);
	
	// benchmark Apple XML plist
	bench(@"Apple XML plist", @"read", ^{ x([NSPropertyListSerialization propertyListWithData:XMLPlistData 
																					  options:NSPropertyListImmutable 
																					   format:NULL 
																						error:NULL]);}, readingResults);
	
	bench(@"Apple XML plist", @"write", ^{ x([NSPropertyListSerialization dataFromPropertyList:array
																						format:NSPropertyListXMLFormat_v1_0
																			  errorDescription:NULL]);}, writingResults);
	// benchmark Apple binary plist
	bench(@"Apple Binary plist", @"read", ^{ x([NSPropertyListSerialization propertyListWithData:binaryPlistData 
																					  options:NSPropertyListImmutable 
																					   format:NULL 
																						error:NULL]);}, readingResults);
	
	bench(@"Apple Binary plist", @"write", ^{ x([NSPropertyListSerialization dataFromPropertyList:array
																						format:NSPropertyListBinaryFormat_v1_0
																			  errorDescription:NULL]);}, writingResults);
	
	
	// standard tests by JSONBenchmarks
	bench(@"Apple JSON", @"read", ^{ x([JSON objectWithData:jsonData options:0 error:nil]);}, readingResults);
	bench(@"Apple JSON", @"write", ^{ x([JSON stringWithObject:array options:0 error:nil]);}, writingResults);

	
	SBJsonParser *sbjsonParser = [[SBJsonParser new] autorelease];
	SBJsonWriter *sbjsonWriter = [[SBJsonWriter new] autorelease];
	bench(@"JSON Framework", @"read", ^{ x([sbjsonParser objectWithData:jsonData]); }, readingResults);
	bench(@"JSON Framework", @"write", ^{ x([sbjsonWriter dataWithObject:array]); }, writingResults);

	
	JSONDecoder *jsonKitDecoder = [JSONDecoder decoder];
	bench(@"JSONKit", @"read", ^{ x([jsonKitDecoder parseJSONData:jsonData]); }, readingResults);
	bench(@"JSONKit", @"write", ^{ x([array JSONString]); }, writingResults);
	

	CJSONDeserializer *cjsonDeserialiser = [CJSONDeserializer deserializer];
	CJSONSerializer *cjsonSerializer = [CJSONSerializer serializer];
	bench(@"TouchJSON", @"read", ^{ x([cjsonDeserialiser deserialize:jsonData error:nil]); }, readingResults);
	bench(@"TouchJSON", @"write", ^{ x([cjsonSerializer serializeArray:array error:nil]); }, writingResults);

	bench(@"YAJL", @"read", ^{ x([jsonString yajl_JSON]); }, readingResults);
	bench(@"YAJL", @"write", ^{ x([array yajl_JSONString]); }, writingResults);

	// Sort results
	[readingResults sortUsingFunction:_compareResults context:nil];
	[writingResults sortUsingFunction:_compareResults context:nil];
	
	// Post notification
	NSDictionary *allResults = [[NSDictionary alloc] initWithObjectsAndKeys:
								readingResults, JBReadingKey,
								writingResults, JBWritingKey,
								nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:JBDidFinishBenchmarksNotification object:allResults];
	
	// Clean up
	[readingResults release];
	[writingResults release];
	[allResults release];
}


#pragma mark UIApplicationDelegate

- (void)applicationDidFinishLaunching:(UIApplication *)application {
	
	// Setup UI
	_window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	JBResultsViewController *viewController = [[JBResultsViewController alloc] init];
	_navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
	[viewController release];
	[_window addSubview:_navigationController.view];
	[_window makeKeyAndVisible];
	
	// Perform after delay so UI doesn't block
	[self performSelector:@selector(benchmark) withObject:nil afterDelay:0.1];
}

@end
