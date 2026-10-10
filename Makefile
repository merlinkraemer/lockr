APP_NAME := Lockr
# Ad-hoc by default. Override for a stable Accessibility grant across rebuilds:
#   make CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" install
CODESIGN_IDENTITY ?= -
ARCH     := $(shell uname -m)
TARGET   := $(ARCH)-apple-macos14.0

BUILD   := build
APP     := $(BUILD)/$(APP_NAME).app
BIN     := $(APP)/Contents/MacOS/$(APP_NAME)
SOURCES := $(wildcard Sources/*.swift)

.PHONY: all install clean

all: $(APP)

$(APP): $(SOURCES) Resources/Info.plist Resources/AppIcon.icns Makefile
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	swiftc -O -target $(TARGET) -o $(BIN) $(SOURCES)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(CODESIGN_IDENTITY)" $(APP)
	@echo "built $(APP)"

install: $(APP)
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/$(APP_NAME).app
	ditto $(APP) $(HOME)/Applications/$(APP_NAME).app
	@echo "installed $(HOME)/Applications/$(APP_NAME).app"

clean:
	rm -rf $(BUILD)
