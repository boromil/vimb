# Native macOS backend for vimb (AppKit + WKWebView).
#
# This builds a self-contained vimb.app bundle from Objective-C sources.
# It is only used on Darwin; on other platforms the GTK4/WebKitGTK build in
# ../src is used instead.

APP      := vimb.app
NAME     := vimb
BUNDLE_ID := org.vimb.browser

SDK      := $(shell xcrun --show-sdk-path)
CC       ?= cc
FRAMEWORKS := -framework Cocoa -framework WebKit -framework JavaScriptCore
CFLAGS   := -O2 -Wall -Wextra -fobjc-arc \
            -F $(SDK)/System/Library/Frameworks \
            -DPROJECT=\"$(NAME)\" -DPROJECT_UCFIRST=\"Vimb\" \
            -DMBUNDLE_ID=\"$(BUNDLE_ID)\"
LDFLAGS  := $(FRAMEWORKS)

SRCS := main.m \
        VimbAppDelegate.m \
        BrowserWindowController.m \
        KeyboardWebView.m \
        TabView.m \
        VimController.m \
        VimbEngine.m \
        VimbStorage.m \
        VimbConfig.m \
        VimbEx.m \
        VimbMenu.m \
        VimbAutocmd.m \
        VimbCommandField.m \
        VimbWindow.m \
        VimbHandler.m \
        VimbEditor.m \
        VimbHintEngine.m \
        VimbPermissionPolicy.m

OBJS := $(SRCS:.m=.o)

all: $(APP)

$(APP): $(OBJS) Contents/Info.plist vimb.icns
	@echo "  LD    $(APP)/Contents/MacOS/$(NAME)"
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@$(CC) $(OBJS) $(LDFLAGS) -o $(APP)/Contents/MacOS/$(NAME)
	@install -m 644 Contents/Info.plist $(APP)/Contents/Info.plist
	@install -m 644 ../vimb.metainfo.xml $(APP)/Contents/Resources/ 2>/dev/null || true
	@install -m 644 vimb.icns $(APP)/Contents/Resources/vimb.icns
	@# ad-hoc sign so the app is launchable locally without Xcode
	@codesign --force --sign - $(APP) >/dev/null 2>&1 || true

# Regenerate the app icon from make_icon.swift when Swift sources/newer plist
# change. Kept lightweight: only rebuild if the script is newer than the icns.
vimb.icns: make_icon.swift
	@echo "  ICON  $@"
	@d="$$(mktemp -d)"; \
	swift make_icon.swift "$$d" >/dev/null 2>&1 && \
	iconutil -c icns "$$d/vimb.iconset" -o $@; \
	rm -rf "$$d"

Contents/Info.plist: Info.plist.in
	@echo "  PLIST $(APP)"
	@mkdir -p Contents
	@sed -e "s!@BUNDLE_ID@!$(BUNDLE_ID)!g" -e "s!@PROJECT@!$(NAME)!g" Info.plist.in > $@

%.o: %.m
	@echo "  CC    $<"
	@$(CC) $(CFLAGS) -c -o $@ $<

clean:
	@rm -f $(OBJS) $(APP) Contents/Info.plist
	@rm -rf $(APP)
	@rm -f tests/vimb_tests tests/*.o tests/*.stamp tests/*.profraw tests/*.profdata

.PHONY: all clean test test-clean

# ---------------------------------------------------------------------------
# Unit tests + line coverage (Foundation-only, home-rolled harness).
# ---------------------------------------------------------------------------
TEST_CC     := cc
TEST_CFLAGS := $(CFLAGS) -fprofile-instr-generate -fcoverage-mapping \
               -I . -I tests
TEST_LDFLAGS := -fprofile-instr-generate -framework Foundation

TEST_SRCS := \
        VimbEngine.m \
        VimbStorage.m \
        VimbConfig.m \
        VimbEx.m \
        VimbAutocmd.m \
        VimController.m \
        VimbHandler.m \
        VimbEditor.m \
        VimbHintEngine.m \
        VimbPermissionPolicy.m

TEST_OBJS := $(patsubst %.m,tests/%.o,$(TEST_SRCS))
TEST_BIN  := tests/vimb_tests

LLVM_PROFDATA ?= $(shell xcrun --find llvm-profdata 2>/dev/null || echo llvm-profdata)
LLVM_COV     ?= $(shell xcrun --find llvm-cov 2>/dev/null || echo llvm-cov)
COVERAGE_PROF := tests/coverage.profdata
COVERAGE_RAW  := tests/default.profraw

# Compile the testable app sources into objects with coverage instrumentation.
$(TEST_OBJS): tests/%.o: %.m
	@echo "  CC(T) $<"
	@$(TEST_CC) $(TEST_CFLAGS) -c -o $@ $<

$(TEST_BIN).stamp: $(TEST_OBJS) tests/test_main.m tests/test_behavior.m
	@echo "  LD    $(TEST_BIN)"
	@$(TEST_CC) $(TEST_CFLAGS) $(TEST_OBJS) tests/test_main.m tests/test_behavior.m $(TEST_LDFLAGS) -o $(TEST_BIN)
	@touch $(TEST_BIN).stamp

tests: $(TEST_BIN).stamp
	@echo "  TEST  $(TEST_BIN)"
	@LLVM_PROFILE_FILE="$(COVERAGE_RAW)" $(TEST_BIN)

test: tests
	@echo "  MERGE profdata"
	@$(LLVM_PROFDATA) merge -o $(COVERAGE_PROF) $(COVERAGE_RAW) 2>/dev/null || true
	@echo "  COVERAGE report"
	@$(LLVM_COV) report $(TEST_BIN) -instr-profile=$(COVERAGE_PROF) 2>/dev/null || true

test-clean:
	@rm -f $(TEST_OBJS) $(TEST_BIN) $(TEST_BIN).stamp \
	        tests/*.profraw tests/*.profdata tests/*.o

