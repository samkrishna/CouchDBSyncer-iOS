//
//  CouchDBSyncerStore.m
//  CouchDBSyncer
//
//  Created by ASW on 26/02/11.
//  Copyright 2011 2moro mobile. All rights reserved.
//

#import "CouchDBSyncerStore.h"
#import "CouchDBSyncerError.h"
#import "MOCouchDBSyncerDatabase.h"
#import "MOCouchDBSyncerDocument.h"
#import "MOCouchDBSyncerAttachment.h"

#define DefaultModelTypeKey @"type"

@interface CouchDBSyncerStore(CouchDBSyncerStorePrivate)
- (NSManagedObjectContext *)managedObjectContext;
- (BOOL)saveDatabase;
@end


@implementation CouchDBSyncerStore

@synthesize error, modelTypeKey;

#pragma mark -

// initialise core data
- (void)initDB {
    if(![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(initDB) withObject:nil waitUntilDone:YES];
        return;
    }
    
    // set up core data
    [self managedObjectContext];
    if(managedObjectContext == nil) return;  // error with core data
}

#pragma mark -

- (id)initWithShippedDatabasePath:(NSString *)path {
    self = [super init];
    if(self) {
        self.modelTypeKey = DefaultModelTypeKey;
        shippedPath = [path retain];
        [self initDB];        
    }
    return self;
}

- (id)init {
    self = [self initWithShippedDatabasePath:nil];
    return self;
}

- (void)dealloc {
    [shippedPath release];
    [error release];
    [modelTypeKey release];
    
    [super dealloc];
}

#pragma mark Accessors

- (BOOL)saveDatabase:(NSManagedObjectContext *)moc {
    NSError *err = nil;
    if (![moc save:&err]) {
        LOG(@"error: %@, %@", err, [err userInfo]);
        self.error = err;
    }
    return err ? NO : YES;
}

// save database
- (BOOL)saveDatabase {
    return [self saveDatabase:self.managedObjectContext];
}

#pragma mark -
#pragma mark Conversion to/from managed objects

- (CouchDBSyncerDatabase *)databaseObject:(MOCouchDBSyncerDatabase *)moDatabase {
    if(moDatabase == nil) return nil;
    
    CouchDBSyncerDatabase *database = [[[CouchDBSyncerDatabase alloc] init] autorelease];
    database.name = moDatabase.name;
    database.url = [NSURL URLWithString:moDatabase.url];
    database.sequenceId = [moDatabase.sequenceId intValue];
    return database;
}

- (CouchDBSyncerDocument *)documentObject:(MOCouchDBSyncerDocument *)moDocument {
    CouchDBSyncerDocument *doc = [[CouchDBSyncerDocument alloc] initWithDocumentId:moDocument.documentId revision:moDocument.revision sequenceId:0 deleted:NO];    
    NSDictionary *dict = [NSKeyedUnarchiver unarchiveObjectWithData:moDocument.dictionaryData];
    [doc setDictionary:dict];
    
    return [doc autorelease];
}

// return a CouchDBSyncerAttachment object corresponding to the managed object
// (used for re-downloading unfetched attachments)
- (CouchDBSyncerAttachment *)attachmentObject:(MOCouchDBSyncerAttachment *)attachment {
    
    CouchDBSyncerAttachment *att = [[[CouchDBSyncerAttachment alloc] init] autorelease];
    
    att.filename = attachment.filename;
    att.contentType = attachment.contentType;
    att.documentId = attachment.documentId;
    att.length = [attachment.length intValue];
    att.revpos = [attachment.revpos intValue];
    att.deleted = NO;
    
    // don't need the content as this object is only used for fetch requests currently
    //att.content = attachment.content;
    
    return att;
}

- (MOCouchDBSyncerDatabase *)moDatabaseObjectName:(NSString *)name context:(NSManagedObjectContext *)moc {
    NSError *err = nil;
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:name, @"name", nil];
    NSFetchRequest *fetch = [managedObjectModel fetchRequestFromTemplateWithName:@"databaseByName" substitutionVariables:data];
    NSArray *databases = [moc executeFetchRequest:fetch error:&err];
    MOCouchDBSyncerDatabase *db = databases.count ? [databases objectAtIndex:0] : nil;
    return db;
}

- (MOCouchDBSyncerDatabase *)moDatabaseObjectName:(NSString *)name {
    return [self moDatabaseObjectName:name context:self.managedObjectContext];
}

- (MOCouchDBSyncerDatabase *)moDatabaseObject:(CouchDBSyncerDatabase *)database {
    return [self moDatabaseObjectName:database.name];
}

// return the managed object document for the given document
- (MOCouchDBSyncerDocument *)moDocumentObjectId:(NSString *)documentId context:(NSManagedObjectContext *)moc {
    NSError *err = nil;
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:documentId, @"documentId", nil];
    NSFetchRequest *fetch = [managedObjectModel fetchRequestFromTemplateWithName:@"documentById" substitutionVariables:data];
    NSArray *documents = [moc executeFetchRequest:fetch error:&err];
    return documents.count ? [documents objectAtIndex:0] : nil;	
}

// return the managed object document for the given document
- (MOCouchDBSyncerDocument *)moDocumentObject:(CouchDBSyncerDocument *)doc context:(NSManagedObjectContext *)moc {
    return [self moDocumentObjectId:doc.documentId context:moc];
}

// return the managed object document for the given document
- (MOCouchDBSyncerDocument *)moDocumentObject:(CouchDBSyncerDocument *)doc {
    return [self moDocumentObject:doc context:self.managedObjectContext];
}

// return the managed object attachment for the given attachment
- (MOCouchDBSyncerAttachment *)moAttachmentObject:(CouchDBSyncerAttachment *)att context:(NSManagedObjectContext *)moc {
    NSError *err = nil;
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:att.documentId, @"documentId", att.filename, @"filename", nil];
    NSFetchRequest *fetch = [managedObjectModel fetchRequestFromTemplateWithName:@"attachmentByDocumentIdAndFilename" substitutionVariables:data];
    NSArray *attachments = [moc executeFetchRequest:fetch error:&err];
    return attachments.count ? [attachments objectAtIndex:0] : nil;	
}

// return the managed object attachment for the given attachment
- (MOCouchDBSyncerAttachment *)moAttachmentObject:(CouchDBSyncerAttachment *)att {
    return [self moAttachmentObject:att context:self.managedObjectContext];
}

#pragma mark -

// get database with the given name. if the database is not found locally, creates a new database with the 
// given name and url.
- (CouchDBSyncerDatabase *)database:(NSString *)name url:(NSURL *)url {
    // fetch or create database record
    MOCouchDBSyncerDatabase *db = [self moDatabaseObjectName:name];
    
    if(db == nil) {
        // add database record
        db = [NSEntityDescription insertNewObjectForEntityForName:@"Database" inManagedObjectContext:managedObjectContext];
        db.name = name;
        db.url = [url absoluteString];
        db.sequenceId = 0;

        [self saveDatabase];
    }
    
    return [self databaseObject:db];
}

- (CouchDBSyncerDatabase *)database:(NSString *)name {
    return [self databaseObject:[self moDatabaseObjectName:name]];
}

- (NSArray *)moDatabases {
    NSManagedObjectContext *moc = [self managedObjectContext];
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"Database" inManagedObjectContext:moc];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entityDescription];
    NSArray *list = [moc executeFetchRequest:request error:nil];
    return list;
}

- (NSArray *)databases {
    NSMutableArray *results = [NSMutableArray array];
    for(MOCouchDBSyncerDatabase *moDatabase in [self moDatabases]) {
        [results addObject:[self databaseObject:moDatabase]];
    }
    return results;
}

// remove the specified database completely
- (void)destroy:(CouchDBSyncerDatabase *)database {
    MOCouchDBSyncerDatabase *moDatabase = [self moDatabaseObject:database];
    [managedObjectContext deleteObject:moDatabase];
}

// purge all data for the specified database
- (void)purge:(CouchDBSyncerDatabase *)database {
    MOCouchDBSyncerDatabase *moDatabase = [self moDatabaseObject:database];
    for(MOCouchDBSyncerDocument *moDocument in moDatabase.documents) {
        [managedObjectContext deleteObject:moDocument];
    }
    [self saveDatabase];
}

// purge this store
- (void)purge {
    if(![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(purge) withObject:nil waitUntilDone:YES];
        return;
    }
    LOG(@"purging all content");
    
    for(MOCouchDBSyncerDatabase *moDatabase in [self moDatabases]) {
        [managedObjectContext deleteObject:moDatabase];
    }
    [self saveDatabase];
}

- (int)countForEntityName:(NSString *)entityName {
    NSError *err = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:[NSEntityDescription entityForName:entityName inManagedObjectContext:managedObjectContext]];
    NSUInteger count = [managedObjectContext countForFetchRequest:request error:&err];	
    [request release];
    
    return count;	
}

- (NSDictionary *)statistics:(CouchDBSyncerDatabase *)database {
    int docs = [self countForEntityName:@"Document"];
    int attachments = [self countForEntityName:@"Attachment"];
    
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:attachments], @"attachments",
            [NSNumber numberWithInt:docs], @"documents",
            nil];
}

- (CouchDBSyncerDocument *)document:(CouchDBSyncerDatabase *)database documentId:(NSString *)documentId {
    MOCouchDBSyncerDocument *moDocument = [self moDocumentObjectId:documentId context:self.managedObjectContext];
    return [self documentObject:moDocument];
}

- (NSArray *)documents:(CouchDBSyncerDatabase *)database {
    MOCouchDBSyncerDatabase *moDatabase = [self moDatabaseObject:database];
    NSMutableArray *documents = [NSMutableArray array];
    for(MOCouchDBSyncerDocument *moDocument in moDatabase.documents) {
        CouchDBSyncerDocument *document = [self documentObject:moDocument];
        [documents addObject:document];
    }
    return documents;
}

- (NSArray *)documentsMatching:(NSPredicate *)predicate {	
    NSError *err = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:[NSEntityDescription entityForName:@"Document" inManagedObjectContext:managedObjectContext]];
    [request setPredicate:predicate];
    NSArray *moDocuments = [managedObjectContext executeFetchRequest:request error:&err];
    [request release];
    
    NSMutableArray *documents = [NSMutableArray array];
    for(MOCouchDBSyncerDocument *moDocument in moDocuments) {
        CouchDBSyncerDocument *document = [self documentObject:moDocument];
        [documents addObject:document];
    }
    
    return documents;
}

- (NSArray *)documentsOfType:(NSString *)type {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"type == $type"];
    predicate = [predicate predicateWithSubstitutionVariables:[NSDictionary dictionaryWithObjectsAndKeys:type, @"type", nil]];
    return [self documentsMatching:predicate];
}

- (NSArray *)documentsTagged:(NSString *)tag {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"tags CONTAINS[c] $tag", tag];
    predicate = [predicate predicateWithSubstitutionVariables:[NSDictionary dictionaryWithObjectsAndKeys:tag, @"tag", nil]];
    return [self documentsMatching:predicate];
}

- (NSArray *)documentsOfType:(NSString *)type tagged:(NSString *)tag {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"type == $type AND tags CONTAINS[c] $tag", tag];
    predicate = [predicate predicateWithSubstitutionVariables:[NSDictionary dictionaryWithObjectsAndKeys:type, @"type", tag, @"tag", nil]];
    return [self documentsMatching:predicate];
}

#pragma mark -

/**
 Returns the path to the application's Documents directory.
 */
- (NSString *)applicationDocumentsDirectory {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
}

#pragma mark -
#pragma mark Core Data stack

/**
 Returns the managed object model for the application.
 If the model doesn't already exist, it is created by merging all of the models found in the application bundle.
 */
- (NSManagedObjectModel *)managedObjectModel {
    if (managedObjectModel != nil) return managedObjectModel;
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"CouchDBSyncer" ofType:@"momd"];
    NSURL *momURL = [NSURL fileURLWithPath:path];
    managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:momURL];
    
    return managedObjectModel;
}

/**
 Returns the persistent store coordinator.
 If the coordinator doesn't already exist, it is created and the store added to it.
 */
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    
    if (persistentStoreCoordinator != nil) return persistentStoreCoordinator;
    
    NSError *err = nil;
    NSString *dbfile = [NSString stringWithFormat:@"couchdbsyncer.sqlite"];
    NSURL *storeUrl = [NSURL fileURLWithPath: [[self applicationDocumentsDirectory] stringByAppendingPathComponent:dbfile]];	
    
    // handle db upgrade
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                             [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
    
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:storeUrl.path]) {
        // database doesn't exist.
        // install shipped database if provided
        if(shippedPath) {
            LOG(@"installing shipped database");
            [[NSFileManager defaultManager] copyItemAtPath:shippedPath toPath:storeUrl.path error:&err];
        }
    }
    
    // iteration 0: on failure, delete database, notify delegate  (delegate may install its own database here)
    // iteration 1: no options. on failure, delete database, do not notify delegate
    // iteration 2: failed to work with no database installed - abort
    for(int i = 0; i < 3; i++) {
        
        if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeUrl options:options error:&err]) {
            LOG(@"persistent store error: %@, code = %d", err, [err code]);
        
            // delete the database and try again
            [[NSFileManager defaultManager] removeItemAtPath:storeUrl.path error:&err];

            options = nil;
 
            if(i == 0 && shippedPath) {
                // install shipped database
                LOG(@"installing shipped database");
                [[NSFileManager defaultManager] copyItemAtPath:shippedPath toPath:storeUrl.path error:&err];
            }
            else if(i == 2) {
                // unrecoverable error
                LOG(@"persistent store error: %@", err);
                self.error = [CouchDBSyncerError errorWithCode:CouchDBSyncerErrorStore];
                //[self reportError];
            }
        } else {
            // no error
            break;
        }
    }
    
    return persistentStoreCoordinator;
}

/**
 Returns the managed object context.
 If the context doesn't already exist, it is created and bound to the persistent store coordinator.
 */
- (NSManagedObjectContext *)managedObjectContext {
    
    if (managedObjectContext != nil) return managedObjectContext;
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        managedObjectContext = [[NSManagedObjectContext alloc] init];
        [managedObjectContext setUndoManager:nil];
        [managedObjectContext setPersistentStoreCoordinator: coordinator];
    }
    
    return managedObjectContext;
}

#pragma mark -

// returns all MOCouchDBSyncerAttachment objects that haven't been fetched yet
- (NSArray *)staleAttachments:(CouchDBSyncerDatabase *)database
{
    MOCouchDBSyncerDatabase *moDatabase = [self moDatabaseObject:database];
    NSDictionary *subs = [NSDictionary dictionaryWithObjectsAndKeys:moDatabase, @"database", nil];
    NSFetchRequest *fetch = [managedObjectModel fetchRequestFromTemplateWithName:@"staleAttachments" substitutionVariables:subs];
    NSArray *list = [managedObjectContext executeFetchRequest:fetch error:nil];
    NSMutableArray *result = [NSMutableArray array];
    for(MOCouchDBSyncerAttachment *moAttachment in list) {
        [result addObject:[self attachmentObject:moAttachment]];
    }
    return result;
}

#pragma mark CouchDBSyncerDelegate handlers (to be run on main thread)

/*
- (void)syncerFoundDeletedDocument:(CouchDBSyncerDocument *)doc {

}

- (void)syncerDidFetchDatabaseInformation:(NSDictionary *)info {
    LOG(@"database info: %@", info);
    
    int docDelCount = [[info valueForKey:@"doc_del_count"] intValue];
    int docUpdateSeq = [[info valueForKey:@"doc_update_seq"] intValue];
    NSString *dbName = [info valueForKey:@"db_name"];
    
    if(docDelCount < [db.docDelCount intValue] || docUpdateSeq < [db.docUpdateSeq intValue]) {
        LOG(@"lower deletion or update sequence count on server - removing local store");
        [self purge];
    }
    else if(dbName && ![db.dbName isEqualToString:dbName]) {
        LOG(@"database name changed - removing local store");
        [self purge];
    }
    db.dbName = dbName;
    db.docDelCount = [NSNumber numberWithInt:docDelCount];
    db.docUpdateSeq = [NSNumber numberWithInt:docUpdateSeq];
    
    [self saveDatabase];  // save database without updating sequence
    
    // continue with sync
    [syncer fetchChanges];
}
 */

#pragma mark -
#pragma mark Syncer support

// update methods
// used by couchdbsyncer
// get an update context for the given database and current thread
- (CouchDBSyncerUpdateContext *)updateContext:(CouchDBSyncerDatabase *)database {
    NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] init];
    [moc setPersistentStoreCoordinator:self.persistentStoreCoordinator];    
    CouchDBSyncerUpdateContext *context = [[[CouchDBSyncerUpdateContext alloc] initWithContext:moc] autorelease];
    context.database = database;
    context.moDatabase = [self moDatabaseObjectName:database.name context:moc];
    [moc release];
    
    return context;
}

- (void)update:(CouchDBSyncerUpdateContext *)context database:(CouchDBSyncerDatabase *)database {
    NSManagedObjectContext *moc = context.managedObjectContext;
    MOCouchDBSyncerDatabase *moDatabase = context.moDatabase;
    moDatabase.name = database.name;
    moDatabase.url = [database.url absoluteString];

    [self saveDatabase:moc];
}

- (void)update:(CouchDBSyncerUpdateContext *)context document:(CouchDBSyncerDocument *)document {
    NSManagedObjectContext *moc = context.managedObjectContext;
    MOCouchDBSyncerDatabase *moDatabase = context.moDatabase;
    MOCouchDBSyncerDocument *moDocument = [self moDocumentObject:document context:moc];
    
    LOG(@"document: %@ (seq %d)", document, document.sequenceId);
    
    if(document.deleted) {
        LOG(@"removing document: %@ (seq %d)", document, document.sequenceId);
        
        // delete document & attachments
        if(document) {
            [moc deleteObject:moDocument];
        }
        
        // save database (updates sequence id)
        moDatabase.sequenceId = [NSNumber numberWithInt:document.sequenceId];
        [self saveDatabase:moc];
        return;
    }
    
    // save document
    // add/update server record
    NSDictionary *dict = [document dictionary];
    NSData *dictData = [NSKeyedArchiver archivedDataWithRootObject:dict];
    NSArray *tags = [dict valueForKey:@"tags"];
    
    if(moDocument == nil) {
        // create new document
        moDocument = [NSEntityDescription insertNewObjectForEntityForName:@"Document" inManagedObjectContext:moc];
    }
    
    moDocument.documentId = document.documentId;
    moDocument.revision = document.revision;
    moDocument.dictionaryData = dictData;
    moDocument.type = [dict valueForKey:modelTypeKey];
    moDocument.parentId = [dict valueForKey:@"parent_id"];
    moDocument.tags = [tags isKindOfClass:[NSArray class]] ? [tags componentsJoinedByString:@","] : nil;
    moDocument.database = moDatabase;
    
    NSMutableSet *old = [NSMutableSet setWithSet:moDocument.attachments];
    NSMutableSet *new = [NSMutableSet set];
    
    for(CouchDBSyncerAttachment *att in document.attachments) {
        MOCouchDBSyncerAttachment *moAttachment = [self moAttachmentObject:att context:moc];
        BOOL is_new = NO;
        
        if(moAttachment == nil) {
            is_new = YES;
            moAttachment = [NSEntityDescription insertNewObjectForEntityForName:@"Attachment" inManagedObjectContext:moc];   
        }
        else {
            [old removeObject:moAttachment];
        }
        
        if(is_new || ([moAttachment.revpos intValue] != att.revpos)) {
            // attachment not yet downloaded or revision has changed
            
            // update attachment attributes
            moAttachment.stale = [NSNumber numberWithBool:YES];
            moAttachment.filename = att.filename;
            moAttachment.contentType = att.contentType;
            moAttachment.documentId = att.documentId;
            moAttachment.document = moDocument;
            moAttachment.revpos = [NSNumber numberWithInt:att.revpos];
            
            [new addObject:moAttachment];  // add to list to be downloaded
        }
    }
    
    // remove local attachments that are no longer attached to the document
    if([old count]) {
        LOG(@"removing %d old attachments", [old count]);
        for(MOCouchDBSyncerAttachment *moatt in [old allObjects]) {
            [managedObjectContext deleteObject:moatt];
        }
    }
    
    // save database (updates sequence id)
    moDatabase.sequenceId = [NSNumber numberWithInt:document.sequenceId];
    [self saveDatabase:moc];
}

- (void)update:(CouchDBSyncerUpdateContext *)context attachment:(CouchDBSyncerAttachment *)attachment {
    LOG(@"attachment: %@", attachment);
    NSManagedObjectContext *moc = context.managedObjectContext;
    MOCouchDBSyncerAttachment *moAttachment = [self moAttachmentObject:attachment context:moc];
    if(moAttachment == nil) {
        // attachment record should be in the database (added by didFetchDocument)
        LOG(@"internal error: no attachment record found for %@", attachment);
        return;
    }
    
    moAttachment.content = attachment.content;
    moAttachment.length = [NSNumber numberWithInt:[attachment.content length]];
    moAttachment.stale = [NSNumber numberWithBool:NO];
    moAttachment.revpos = [NSNumber numberWithInt:attachment.revpos];
    moAttachment.database = context.moDatabase;
    
    // save database 
    [self saveDatabase:moc];
}

@end
