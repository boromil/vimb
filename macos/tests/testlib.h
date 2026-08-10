// Minimal home-rolled unit-test harness for the Foundation-only vimb sources.
// Compiles cleanly under -fobjc-arc with Foundation and without AppKit.
//
// Usage:
//   static void test_something(void) { ... TEST_ASSERT(...) ... }
//   int main(void) {
//       RUN_TEST(test_something);
//       return RUN_ALL_TESTS();
//   }
#ifndef TESTLIB_H
#define TESTLIB_H

#import <Foundation/Foundation.h>

// Optional global setup/teardown hooks (assigned from a test file).
extern id _Nullable TEST_SETUP;   // unused placeholder to keep arity uniform
extern id _Nullable TEST_TEARDOWN;

static int test_pass_count = 0;
static int test_fail_count = 0;

#define TEST_ASSERT(cond)                                                        \
    do {                                                                         \
        if (cond) {                                                              \
            test_pass_count++;                                                   \
        } else {                                                                 \
            test_fail_count++;                                                   \
            printf("FAIL %s:%d: TEST_ASSERT(%s)\n",                              \
                   __FILE__, __LINE__, #cond);                                   \
        }                                                                        \
    } while (0)

#define TEST_ASSERT_TRUE(cond)  TEST_ASSERT(cond)
#define TEST_ASSERT_FALSE(cond) TEST_ASSERT(!(cond))
#define TEST_ASSERT_NOTNULL(p)  TEST_ASSERT((p) != NULL)

#define TEST_ASSERT_EQ_I(a, b)                                                   \
    do {                                                                         \
        long long _a = (long long)(a);                                           \
        long long _b = (long long)(b);                                           \
        if (_a == _b) {                                                          \
            test_pass_count++;                                                   \
        } else {                                                                 \
            test_fail_count++;                                                   \
            printf("FAIL %s:%d: TEST_ASSERT_EQ_I(%s, %s): %lld != %lld\n",       \
                   __FILE__, __LINE__, #a, #b, _a, _b);                          \
        }                                                                        \
    } while (0)

#define TEST_ASSERT_EQ_STR(a, b)                                                 \
    do {                                                                         \
        NSString *_sa = (a);                                                     \
        NSString *_sb = (b);                                                     \
        BOOL _eq = (_sa == nil && _sb == nil) || [_sa isEqualToString:_sb];       \
        if (_eq) {                                                               \
            test_pass_count++;                                                   \
        } else {                                                                 \
            test_fail_count++;                                                   \
            printf("FAIL %s:%d: TEST_ASSERT_EQ_STR(%s, %s): \"%s\" != \"%s\"\n", \
                   __FILE__, __LINE__, #a, #b,                                   \
                   _sa.UTF8String ?: "(null)", _sb.UTF8String ?: "(null)");      \
        }                                                                        \
    } while (0)

// Runs a single test function, reporting pass/fail and guarding the body so
// unused-result / unused-variable warnings don't leak onto the build.
#define RUN_TEST(name)                                                           \
    do {                                                                         \
        int beforeFail = test_fail_count;                                        \
        test_current_name = #name;                                               \
        name();                                                                  \
        if (test_fail_count == beforeFail) {                                     \
            printf("PASS %s\n", #name);                                          \
        } else {                                                                 \
            printf("FAIL %s\n", #name);                                          \
        }                                                                        \
    } while (0)

// Reports the aggregate result and returns the correct process exit code.
#define RUN_ALL_TESTS()                                                          \
    ({                                                                           \
        printf("-------------------------------------------\n");                 \
        printf("Tests passed: %d, failed: %d\n", test_pass_count, test_fail_count); \
        test_fail_count == 0 ? 0 : 1;                                            \
    })

static const char *_Nullable test_current_name = NULL;

// Suppress "declared but not defined"/unused warnings for the externs above
// if a test never assigns them.
static inline void testlib_unused_hooks(void) __attribute__((unused));
static inline void testlib_unused_hooks(void) {
    (void)TEST_SETUP;
    (void)TEST_TEARDOWN;
}

#endif /* TESTLIB_H */
