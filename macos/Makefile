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
        VimbAutocmd.m

OBJS := $(SRCS:.m=.o)

all: $(APP)

$(APP): $(OBJS) Contents/Info.plist
	@echo "  LD    $(APP)/Contents/MacOS/$(NAME)"
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@$(CC) $(OBJS) $(LDFLAGS) -o $(APP)/Contents/MacOS/$(NAME)
	@install -m 644 Contents/Info.plist $(APP)/Contents/Info.plist
	@install -m 644 ../vimb.metainfo.xml $(APP)/Contents/Resources/ 2>/dev/null || true
	@# ad-hoc sign so the app is launchable locally without Xcode
	@codesign --force --sign - $(APP) >/dev/null 2>&1 || true

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

.PHONY: all clean
