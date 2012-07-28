//
//  CLJMRT.m
//  CLJMRuntime
//
//  Created by Josh Abernathy on 7/26/12.
//  Copyright (c) 2012 Josh Abernathy. All rights reserved.
//

#import <pthread.h>
#import "CLJMRT.h"
#import "CLJMVar.h"

static dispatch_queue_t CLJMRuntimeKeywordsQueue;
static dispatch_queue_t CLJMRuntimeSymbolsQueue;
static dispatch_queue_t CLJMRuntimeDefsQueue;

static NSMutableDictionary *CLJMRuntimeKeywords = nil;
static NSMutableDictionary *CLJMRuntimeSymbols = nil;
static NSMutableDictionary *CLJMRuntimeDefs = nil;

static pthread_key_t CLJMRuntimeBindingsKey = 0;

__attribute__((constructor))
static void cljm_rt_init(void) {
	CLJMRuntimeKeywordsQueue = dispatch_queue_create("com.cljm.keywords_queue", 0);
	CLJMRuntimeSymbolsQueue = dispatch_queue_create("com.cljm.symbols_queue", 0);
	CLJMRuntimeDefsQueue = dispatch_queue_create("com.cljm.defs_queue", 0);
	
	CLJMRuntimeKeywords = [[NSMutableDictionary alloc] init];
	CLJMRuntimeSymbols = [[NSMutableDictionary alloc] init];
	CLJMRuntimeDefs = [[NSMutableDictionary alloc] init];
	
	pthread_key_create(&CLJMRuntimeBindingsKey, NULL);
}

__attribute__((destructor))
static void cljm_rt_teardown(void) {
	dispatch_release(CLJMRuntimeKeywordsQueue);
	dispatch_release(CLJMRuntimeSymbolsQueue);
	dispatch_release(CLJMRuntimeDefsQueue);
	
	pthread_key_delete(CLJMRuntimeBindingsKey);
}

BOOL cljm_truthy(id object) {
	if(object == nil) return NO;
	if([object isKindOfClass:[NSNumber class]]) return [object boolValue];
	
	return YES;
}

static id cljm_rt_lookup(NSString *key, dispatch_queue_t dispatchQueue, NSMutableDictionary *dictionary, id defaultValue) {
	__block id value = defaultValue;
	dispatch_sync(dispatchQueue, ^{
		value = [dictionary objectForKey:key];
		if(value == nil && defaultValue != nil) {
			[dictionary setObject:defaultValue forKey:key];
			value = defaultValue;
		}
	});
	
	return value;
}

static void cljm_rt_set(NSString *key, id value, dispatch_queue_t dispatchQueue, NSMutableDictionary *dictionary) {
	dispatch_sync(dispatchQueue, ^{
		[dictionary setObject:value forKey:key];
	});
}

id<NSCopying> cljm_keyword(NSString *literal) {
	return cljm_rt_lookup(literal, CLJMRuntimeKeywordsQueue, CLJMRuntimeKeywords, literal);
}

id<NSCopying> cljm_symbol(NSString *literal) {
	return cljm_rt_lookup(literal, CLJMRuntimeSymbolsQueue, CLJMRuntimeSymbols, literal);
}

CLJMVar * cljm_var_def(NSString *name, id<NSCopying> value) {
	// Don't intern a nil value for a def.
	if(value == nil) return nil;

	CLJMVar *var = [[CLJMVar alloc] initWithValue:value];
	cljm_rt_set(name, value, CLJMRuntimeDefsQueue, CLJMRuntimeDefs);
	
	return var;
}

NSMutableDictionary * cljm_rt_get_top_bindings(void) {
	NSMutableArray *bindingsStack = (__bridge NSMutableArray *) pthread_getspecific(CLJMRuntimeBindingsKey);
	NSMutableDictionary *topBindings = [bindingsStack lastObject];
	return topBindings;
}

CLJMVar * cljm_var_lookup(NSString *name) {
	NSMutableArray *bindingsStack = (__bridge NSMutableArray *) pthread_getspecific(CLJMRuntimeBindingsKey);
	for(NSDictionary *bindings in [bindingsStack reverseObjectEnumerator]) {
		id boundValue = [bindings objectForKey:name];
		if(boundValue != nil) return boundValue;
	}
	
	return cljm_rt_lookup(name, CLJMRuntimeDefsQueue, CLJMRuntimeDefs, nil);
}

CLJMVar * cljm_var_bind(NSString *name, id<NSCopying> value) {
	// Don't bind a nil value.
	if(value == nil) return nil;
	
	NSMutableDictionary *topBindings = cljm_rt_get_top_bindings();
	CLJMVar *var = [[CLJMVar alloc] initWithValue:value];
	[topBindings setObject:var forKey:name];
	
	return var;
}

void cljm_push_binding(void) {
	NSMutableArray *bindingsStack = (__bridge NSMutableArray *) pthread_getspecific(CLJMRuntimeBindingsKey);
	if(bindingsStack == nil) {
		bindingsStack = [NSMutableArray array];
		pthread_setspecific(CLJMRuntimeBindingsKey, (__bridge const void *) bindingsStack);
	}
	
	[bindingsStack addObject:[NSMutableDictionary dictionary]];
}

void cljm_pop_binding(void) {
	NSMutableArray *bindingsStack = (__bridge NSMutableArray *) pthread_getspecific(CLJMRuntimeBindingsKey);
	[bindingsStack removeLastObject];
}
