DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

.PHONY: build test app install run clean

build:
	xcrun --sdk macosx swift build -c release

test:
	xcrun --sdk macosx swift test

app:
	./Scripts/build-app.sh

install: app
	@-pkill -x EasyBarcode 2>/dev/null || true
	@rm -rf /Applications/EasyBarcode.app
	@ditto build/EasyBarcode.app /Applications/EasyBarcode.app || \
		(echo "没有写入 /Applications 的权限，请执行：sudo ditto build/EasyBarcode.app /Applications/EasyBarcode.app" && exit 1)
	@echo "已安装到 /Applications/EasyBarcode.app"

run: app
	open build/EasyBarcode.app --args --show

clean:
	rm -rf .build build
