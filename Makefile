APP_NAME := Lockr
SIGN_ID  := -
ARCH     := $(shell uname -m)
TARGET   := $(ARCH)-apple-macos14.0

BUILD   := build
APP     := $(BUILD)/$(APP_NAME).app
BIN     := $(APP)/Contents/MacOS/$(APP_NAME)
SOURCES := $(wildcard Sources/*.swift)

.PHONY: all install clean

all: $(APP)

$(APP): $(SOURCES) Resources/Info.plist Makefile
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	swiftc -O -target $(TARGET) -o $(BIN) $(SOURCES)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" $(APP)
	@echo "built $(APP)"

install: $(APP)
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/$(APP_NAME).app
	ditto $(APP) $(HOME)/Applications/$(APP_NAME).app
	@echo "installed $(HOME)/Applications/$(APP_NAME).app"

clean:
	rm -rf $(BUILD)
