//
//  CouchDBSyncerBulkFetch.m
//  CouchDBSyncer
//
//  Created by Andrew on 13/03/11.
//  Copyright 2011 2moro mobile. All rights reserved.
//
// curl -d '{"keys":["bar","baz"]}' -X POST http://127.0.0.1:5984/foo/_all_docs?include_docs=true

#import "CouchDBSyncerBulkFetch.h"
#import "NSObject+SBJson.h"

@interface CouchDBSyncerFetch (CouchDBSyncerPrivate)
- (void)finish;
@end

@implementation CouchDBSyncerBulkFetch

- (id)initWithServerPath:(NSString *)path delegate:(id<CouchDBSyncerFetchDelegate>)d {
    NSString *urlPath = [NSString stringWithFormat:@"%@/_all_docs?include_docs=true", path];
    if((self = [super initWithURL:[NSURL URLWithString:urlPath] delegate:d])) {
        fetchType = CouchDBSyncerFetchTypeBulkDocuments;
    }
    return self;
}

- (void)dealloc {
    [super dealloc];
}

#pragma mark -

- (void)setFetchType:(CouchDBSyncerFetchType)ft {
    // do nothing (fetch type is fixed to bulk)
}

- (NSString *)httpBody {
    NSMutableArray *keys = [NSMutableArray array];
    for(CouchDBSyncerDocument *doc in response.objects) {
        [keys addObject:doc.documentId];
    }
    NSDictionary *req = [NSDictionary dictionaryWithObjectsAndKeys:keys, @"keys", nil];
    return [req JSONRepresentation];
}

- (NSMutableURLRequest *)urlRequest {
    NSMutableURLRequest *req = [super urlRequest];
    
    NSString *body = [self httpBody];
    if(body) {
        [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
        [req setHTTPMethod:@"POST"];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    
    return req;
}

#pragma mark -

- (void)addDocument:(CouchDBSyncerDocument *)doc {
    [response addObject:doc];
}

- (int)documentCount {
    return [response.objects count];
}

#pragma mark Private methods

// update the content of the documents list from fetched data
- (void)updateContent {
    NSDictionary *dict = [self dictionary];
    NSArray *rows = [dict valueForKey:@"rows"];
    NSMutableDictionary *docById = [NSMutableDictionary dictionary];
    
    for(NSDictionary *row in rows) {
        NSDictionary *doc = [row valueForKey:@"doc"];
        NSString *documentId = [row valueForKey:@"id"];        
        [docById setValue:doc forKey:documentId];
    }
    
    // update document content
    for(CouchDBSyncerDocument *doc in response.objects) {
        doc.dictionary = [docById valueForKey:doc.documentId];
    }
}

- (void)finish {
    // populate content in documents
    [self updateContent];
    
    // call superclass method to finish connection
    [super finish];
}

@end