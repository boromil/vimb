ifneq ($(V),1)
Q := @
endif

PREFIX           ?= /usr/local
BINPREFIX        := $(DESTDIR)$(PREFIX)/bin
MANPREFIX        := $(DESTDIR)$(PREFIX)/share/man
EXAMPLEPREFIX    := $(DESTDIR)$(PREFIX)/share/vimb/example
DOTDESKTOPPREFIX := $(DESTDIR)$(PREFIX)/share/applications
METAINFOPREFIX   := $(DESTDIR)$(PREFIX)/share/metainfo
LIBDIR           := $(DESTDIR)$(PREFIX)/lib/vimb
RUNPREFIX        := $(PREFIX)
EXTENSIONDIR     := $(RUNPREFIX)/lib/vimb
OS               := $(shell uname -s)
PKG_CONFIG       ?= pkg-config

# Native backend selection. On macOS/Darwin we build against Apple's native
# WebKit/AppKit frameworks (see macos/). On every other OS the classic
# GTK4 + WebKitGTK build is used and validated via pkg-config below.
ifeq "$(OS)" "Darwin"
NATIVE = 1
else
NATIVE = 0
endif

# define some directories
SRCDIR  = src
DOCDIR  = doc
MACOSDIR = macos

ifneq "$(NATIVE)" "1"
# used libs
LIBS = gtk4 webkitgtk-6.0

# Fail fast if the required dev libraries are not discoverable via
# pkg-config. Without this check the $(shell) expansion below yields empty
# CFLAGS/LDFLAGS and the build silently drags in any same-named header found
# on the default search path (e.g. the Objective-C WebKit.framework shipped
# with the macOS SDK) and dies in a pile of cryptic errors.
$(foreach _dep,$(LIBS),\
	$(if $(shell $(PKG_CONFIG) --exists '$(_dep)' 2>/dev/null && echo ok),,\
		$(error vimb: required development package "$(_dep)" was not found by \
			`$(PKG_CONFIG)`. vimb depends on GTK and WebKitGTK; install the \
			matching -dev/-devel packages, e.g. for Debian/Ubuntu: \
			`sudo apt-get install libgtk-4-dev libwebkitgtk-6.0-dev`, for \
			Fedora: `sudo dnf install gtk4-devel webkitgtk6.0-devel`, and make \
			sure PKG_CONFIG_PATH points at them)))
endif

# setup general used CFLAGS
# Use 'override' to ensure these flags are added even when CFLAGS is set on command line
override CFLAGS   += -std=c99 -pipe -Wall -fPIC
CPPFLAGS += -DEXTENSIONDIR=\"${EXTENSIONDIR}\"
CPPFLAGS += -DPROJECT=\"vimb\" -DPROJECT_UCFIRST=\"Vimb\"
ifneq "$(NATIVE)" "1"
CPPFLAGS += -DGSEAL_ENABLE
CPPFLAGS += -DGTK_DISABLE_SINGLE_INCLUDES
CPPFLAGS += -DGDK_DISABLE_DEPRECATED

ifeq "$(findstring $(OS),FreeBSD DragonFly)" ""
CPPFLAGS += -D_XOPEN_SOURCE=500
CPPFLAGS += -D__BSD_VISIBLE
endif

# flags used to build webextension
EXTTARGET   = webext_main.so
EXTCFLAGS   = ${CFLAGS} $(shell $(PKG_CONFIG) --cflags webkitgtk-6.0)
EXTCPPFLAGS = $(CPPFLAGS)
EXTLDFLAGS  = ${LDFLAGS} $(shell $(PKG_CONFIG) --libs webkitgtk-6.0) -shared

# flags used for the main application
# Use 'override' to ensure these flags are added even when CFLAGS/LDFLAGS is set on command line
override CFLAGS     += $(shell $(PKG_CONFIG) --cflags $(LIBS))
override LDFLAGS    += $(shell $(PKG_CONFIG) --libs $(LIBS))
endif
