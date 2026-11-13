#!/bin/zsh
#
#  install.sh — QuadFinder를 Release로 빌드해서 응용 프로그램 폴더에 설치
#
#  사용법 (Mac 터미널, 프로젝트 폴더에서):
#    ./Tools/install.sh
#
#  하는 일
#  1) Release 빌드 (Debug보다 가볍고 빠른 배포용 빌드). 결과물은 프로젝트의 build/ 폴더에 생김
#  2) QuadFinder가 실행 중이면 종료 (복사 중이면 앱이 "계속할지" 물어봄)
#  3) 응용 프로그램 폴더에 예전 버전이 있으면 휴지통으로 옮김 (완전 삭제하지 않음)
#  4) 새 버전을 응용 프로그램 폴더에 복사하고 macOS에 등록
#

set -e   # 중간에 하나라도 실패하면 바로 멈춤

PROJECT_DIR="${0:A:h:h}"                 # 이 스크립트가 있는 Tools/ 의 한 단계 위
APP_NAME="QaudFInder.app"
BUNDLE_ID="net.tissant.QaudFInder"
BUILD_DIR="$PROJECT_DIR/build"
BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
TARGET="/Applications/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "▶ 1/4  Release 빌드 중… (1~2분 걸릴 수 있어요)"
cd "$PROJECT_DIR"
if ! xcodebuild -project QaudFInder.xcodeproj -scheme QaudFInder -configuration Release \
        -derivedDataPath "$BUILD_DIR" build > "$BUILD_DIR.log" 2>&1; then
    echo "✖ 빌드 실패. 자세한 내용: $BUILD_DIR.log"
    grep -E "error:" "$BUILD_DIR.log" | head -10
    exit 1
fi
rm -f "$BUILD_DIR.log"
echo "  빌드 완료"

echo "▶ 2/4  실행 중인 QuadFinder 종료"
if pgrep -f "$APP_NAME/Contents/MacOS" > /dev/null; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
    # 최대 30초 기다림 (복사 중 확인 창이 떠 있을 수 있음)
    for i in {1..30}; do
        pgrep -f "$APP_NAME/Contents/MacOS" > /dev/null || break
        sleep 1
    done
    if pgrep -f "$APP_NAME/Contents/MacOS" > /dev/null; then
        echo "✖ QuadFinder가 아직 실행 중이라 설치를 멈춥니다. 앱을 끈 뒤 다시 실행하세요."
        exit 1
    fi
fi

echo "▶ 3/4  예전 버전 정리"
if [[ -e "$TARGET" ]]; then
    STAMP=$(date "+%Y-%m-%d %H.%M.%S")
    mv "$TARGET" "$HOME/.Trash/QaudFInder (이전 버전 $STAMP).app"
    echo "  예전 버전을 휴지통으로 옮겼습니다"
fi

echo "▶ 4/4  응용 프로그램 폴더에 설치"
ditto "$BUILT_APP" "$TARGET"
"$LSREGISTER" -f "$TARGET"

echo "✔ 설치 완료: $TARGET"
echo "  Launchpad나 Spotlight(⌘Space)에서 \"QaudFInder\"를 찾아 실행하세요."
