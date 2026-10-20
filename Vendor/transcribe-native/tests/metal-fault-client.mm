#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <cassert>
#include <cstdlib>
#include <cstring>

extern "C" int voicepen_client_main(int argc,char **argv);
static Class device_class;
static IMP buffer_length;
static IMP buffer_bytes;
static IMP library_source;

static id fail_buffer_length(id object,SEL selector,NSUInteger length,MTLResourceOptions options) {return nil;}
static id fail_buffer_bytes(id object,SEL selector,void *bytes,NSUInteger length,MTLResourceOptions options,id deallocator) {return nil;}
static id fail_library(id object,SEL selector,NSString *source,MTLCompileOptions *options,NSError **error) {
    if(error)*error=[NSError errorWithDomain:@"VoicePenNativeFaultTest" code:1 userInfo:nil];
    return nil;
}
static IMP replace(SEL selector,IMP implementation) {
    Method method=class_getInstanceMethod(device_class,selector);assert(method);
    IMP previous=method_getImplementation(method);
    class_replaceMethod(device_class,selector,implementation,method_getTypeEncoding(method));
    return previous;
}
extern "C" void voicepen_fault_arm(void) {
    buffer_length=replace(@selector(newBufferWithLength:options:),(IMP)fail_buffer_length);
    buffer_bytes=replace(@selector(newBufferWithBytesNoCopy:length:options:deallocator:),(IMP)fail_buffer_bytes);
}
extern "C" void voicepen_fault_disarm(void) {
    replace(@selector(newBufferWithLength:options:),buffer_length);
    replace(@selector(newBufferWithBytesNoCopy:length:options:deallocator:),buffer_bytes);
}
int main(int argc,char **argv) {
    @autoreleasepool {
        id<MTLDevice> device=MTLCreateSystemDefaultDevice();assert(device);
        device_class=object_getClass(device);
        const char *failure=std::getenv("VOICEPEN_TEST_METAL_FAILURE");
        bool library_failure=failure && std::strcmp(failure,"library")==0;
        if(library_failure)library_source=replace(@selector(newLibraryWithSource:options:error:),(IMP)fail_library);
        int result=voicepen_client_main(argc,argv);
        if(library_failure)replace(@selector(newLibraryWithSource:options:error:),library_source);
        return result;
    }
}
