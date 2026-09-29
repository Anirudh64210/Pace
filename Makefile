# Pace: build, run, test, bundle.
#
#   make install    build Pace.app and copy it to /Applications   <- start here
#   make run        build and run from the terminal (menu bar item appears)
#   make demo       same, with demo data that cycles through every state
#   make check      test both data sources once and print what they see
#   make test       unit tests
#   make app        build build/Pace.app (release, ad hoc signed)
#   make uninstall  quit Pace and remove /Applications/Pace.app
#   make screenshots  re-render docs/screenshots from demo data
#   make icon       draw Support/Pace.icns from the apple artwork (make app does this)
#   make clean

APP      = build/Pace.app
BIN      = .build/release/Pace
CONTENTS = $(APP)/Contents

.PHONY: run demo check test app install uninstall screenshots icon clean open

run:
	swift run Pace

demo:
	swift run Pace --demo

check:
	swift run Pace --check

test:
	swift test

screenshots:
	swift build
	.build/debug/Pace --snapshot build/snapshots
	for n in normal expanded-all onboarding pill; do cp build/snapshots/$$n.png docs/screenshots/; done

$(BIN): $(shell find Sources -name '*.swift') Package.swift
	swift build -c release

app: $(BIN) Support/Pace.icns
	rm -rf "$(APP)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BIN)" "$(CONTENTS)/MacOS/Pace"
	cp Support/Info.plist "$(CONTENTS)/Info.plist"
	cp Support/Pace.icns "$(CONTENTS)/Resources/Pace.icns"
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP)"

Support/Pace.icns: scripts/make-icon.swift
	swift scripts/make-icon.swift Support/Pace.icns

icon:
	swift scripts/make-icon.swift Support/Pace.icns

open: app
	open "$(APP)"

# Only ever replace or remove a Pace.app that is this app.
BUNDLE_ID = org.pace-menubar.Pace
define ensure_ours
	@if [ -d /Applications/Pace.app ] && [ "$$(defaults read /Applications/Pace.app/Contents/Info CFBundleIdentifier 2>/dev/null)" != "$(BUNDLE_ID)" ]; then \
		echo "/Applications/Pace.app is a different app. Not touching it."; exit 1; fi
endef

install: app
	$(ensure_ours)
	-osascript -e 'tell application id "$(BUNDLE_ID)" to quit' 2>/dev/null; true
	rm -rf /Applications/Pace.app
	cp -R "$(APP)" /Applications/Pace.app
	open /Applications/Pace.app
	@echo "Installed and opened /Applications/Pace.app. Look for the apple in your menu bar."

uninstall:
	$(ensure_ours)
	-osascript -e 'tell application id "$(BUNDLE_ID)" to quit' 2>/dev/null; true
	rm -rf /Applications/Pace.app
	@echo "Removed /Applications/Pace.app. To remove the Claude Code status line too, use Settings > Remove before uninstalling, or see the README."

clean:
	rm -rf .build build
