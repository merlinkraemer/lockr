APP_NAME := Lockr
# Ad-hoc by default, so each rebuild needs a fresh Accessibility grant. Sign with
# your own identity to keep the grant across rebuilds:
#   make CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" install
# Releases are built by scripts/release.sh.
CODESIGN_IDENTITY ?= -
ARCH     := $(shell uname -m)
TARGET   := $(ARCH)-apple-macos14.0

BUILD   := build
APP     := $(BUILD)/$(APP_NAME).app
BIN     := $(APP)/Contents/MacOS/$(APP_NAME)
SOURCES := $(wildcard Sources/*.swift)

.PHONY: all install clean

all: $(APP)

$(APP): $(SOURCES) $(wildcard Resources/*) $(wildcard Resources/LaunchAgents/*) Makefile
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources $(APP)/Contents/Library
	swiftc -O -swift-version 5 -target $(TARGET) -o $(BIN) $(SOURCES)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp -R Resources/LaunchAgents $(APP)/Contents/Library/LaunchAgents
	codesign --force --sign "$(CODESIGN_IDENTITY)" $(APP)
	@echo "built $(APP)"

install: $(APP)
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/$(APP_NAME).app
	ditto $(APP) $(HOME)/Applications/$(APP_NAME).app
	@echo "installed $(HOME)/Applications/$(APP_NAME).app"

clean:
	rm -rf $(BUILD)
