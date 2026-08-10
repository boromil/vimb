version = 4.0.0
include config.mk

APP = vimb.app

ifneq "$(NATIVE)" "1"
all: version.h src.subdir-all
else
all: $(MACOSDIR)/$(APP)
endif

version.h: Makefile $(wildcard .git/index)
	@echo "create $@"
	$(Q)v="$$(git describe --tags 2>/dev/null)"; \
	echo "#define VERSION \"$${v:-$(version)}\"" > $@

# Native macOS build is handled entirely in macos/Makefile.
$(MACOSDIR)/$(APP):
	$(Q)$(MAKE) -C $(MACOSDIR)

options:
	@echo "vimb build options:"
	@echo "LIBS      = $(LIBS)"
	@echo "CFLAGS    = $(CFLAGS)"
	@echo "LDFLAGS   = $(LDFLAGS)"
	@echo "EXTCFLAGS = $(EXTCFLAGS)"
	@echo "CC        = $(CC)"

install: all
ifneq "$(NATIVE)" "1"
	@# binary
	install -d $(BINPREFIX)
	install -m 755 src/vimb $(BINPREFIX)/vimb
	@# extension
	install -d $(LIBDIR)
	install -m 644 src/webextension/$(EXTTARGET) $(LIBDIR)/$(EXTTARGET)
	@# man page
	install -d $(MANPREFIX)/man1
	@sed -e "s!VERSION!$(version)!g" \
		-e "s!PREFIX!$(PREFIX)!g" \
		-e "s!DATE!`date -u -r $(DOCDIR)/vimb.1 +'%m %Y' 2>/dev/null || date +'%m %Y'`!g" $(DOCDIR)/vimb.1 > $(MANPREFIX)/man1/vimb.1
	@# .desktop file
	install -d $(DOTDESKTOPPREFIX)
	install -m 644 vimb.desktop $(DOTDESKTOPPREFIX)/vimb.desktop
	@# .metainfo.xml file
	install -d $(METAINFOPREFIX)
	install -m 644 vimb.metainfo.xml $(METAINFOPREFIX)/vimb.metainfo.xml
else
	@# copy the native .app bundle into the run/system prefix
	install -d $(RUNPREFIX)/../$(APP)
	tar -cf - -C $(MACOSDIR) Contents | tar -xf - -C $(RUNPREFIX)/../$(APP)
endif

uninstall:
ifneq "$(NATIVE)" "1"
	$(RM) $(BINPREFIX)/vimb
	$(RM) $(DESTDIR)$(MANDIR)/man1/vimb.1
	$(RM) $(LIBDIR)/$(EXTTARGET)
	$(RM) $(DOTDESKTOPPREFIX)/vimb.desktop
	$(RM) $(METAINFOPREFIX)/vimb.metainfo.xml
else
	$(RM) -rf $(RUNPREFIX)/../$(APP)
endif

clean:
ifneq "$(NATIVE)" "1"
	src.subdir-clean test-clean
else
	$(Q)$(MAKE) -C $(MACOSDIR) clean
endif

sandbox:
ifneq "$(NATIVE)" "1"
	$(Q)$(MAKE) clean
	$(Q)$(MAKE) RUNPREFIX=$(CURDIR)/sandbox/usr PREFIX=/usr EXTENSIONDIR=$(CURDIR)/sandbox/usr/lib/vimb DESTDIR=./sandbox install
else
	$(Q)$(MAKE) -C $(MACOSDIR) all
endif

runsandbox: sandbox
ifneq "$(NATIVE)" "1"
	sandbox/usr/bin/vimb
else
	$(Q)open $(MACOSDIR)/$(APP)
endif

test: version.h
	$(MAKE) -C src vimb.so
	$(MAKE) -C tests

test-clean:
	$(MAKE) -C tests clean

%.subdir-all:
	$(Q)$(MAKE) -C $*

%.subdir-clean:
	$(Q)$(MAKE) -C $* clean

.PHONY: all options install uninstall clean sandbox runsandbox
