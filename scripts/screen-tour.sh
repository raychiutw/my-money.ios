#!/usr/bin/env bash
# 截圖巡覽(#70):在專用模擬器上依序切換外觀(淺色、深色)和字級(預設、XXL、AX5),
# 每種組合跑一次 ScreenTourUITests,再把截圖匯出成「外觀-字級-畫面-序號.png」。
# 巡覽的範圍見 tests/MyMoneyUITests/ScreenTourUITests.swift,怎麼用見 DESIGN.md「截圖巡覽」。
#
# 用法:
#   scripts/screen-tour.sh [-o 輸出目錄] [-d 模擬器 UDID] [-t 裝置型號] [-a 外觀] [-s 字級]
#
#   -o  截圖輸出目錄，預設 /tmp/my-money-screen-tour。放在 repo 外，截圖不進 repo。
#       這次要跑的組合，舊的截圖會先刪掉。
#   -d  模擬器 UDID。沒指定時用名為「MyMoney Screen Tour」的 iPhone 17,沒有就建立一台，
#       不佔用其他測試正在用的模擬器。
#   -t  專用模擬器的裝置型號，預設 iPhone 17;例如「iPad Pro 13-inch (M5)」。專用模擬器的名稱會帶型號，
#       不同型號各有一台。指定 -d 時忽略。
#   -a  外觀，逗號分隔:light、dark(預設兩種都跑)。
#   -s  字級，逗號分隔:default、xxl、ax5(預設三種都跑)。
#
# 例:
#   scripts/screen-tour.sh
#   scripts/screen-tour.sh -o /tmp/tour-before -a dark -s ax5
set -euo pipefail

readonly DEFAULT_DEVICE_TYPE="iPhone 17"
readonly TEST_ID="MyMoneyUITests/ScreenTourUITests/testTour"
# 測試失敗時 xcodebuild 預設會收集模擬器診斷，要等十分鐘左右，所以用 -collect-test-diagnostics never 關掉。
# 測試跑完之後 xcodebuild 還是可能卡住不結束(Xcode 27):結果檔寫好(Info.plist 出現)之後再等這麼多秒，還沒結束就砍掉。
readonly EXIT_GRACE_SECONDS=120

output="/tmp/my-money-screen-tour"
udid=""
appearances="light,dark"
sizes="default,xxl,ax5"
device_type="$DEFAULT_DEVICE_TYPE"

usage() {
  sed -n '2,18p' "$0"
  exit 64
}

while getopts "o:d:t:a:s:h" opt; do
  case "$opt" in
    o) output="$OPTARG" ;;
    d) udid="$OPTARG" ;;
    t) device_type="$OPTARG" ;;
    a) appearances="$OPTARG" ;;
    s) sizes="$OPTARG" ;;
    *) usage ;;
  esac
done

# 字級的簡稱 → UIContentSizeCategory 的 launch argument 值。
content_size() {
  case "$1" in
    default) echo "UICTContentSizeCategoryL" ;;
    xxl) echo "UICTContentSizeCategoryXXL" ;;
    ax5) echo "UICTContentSizeCategoryAccessibilityXXXL" ;;
    *) return 1 ;;
  esac
}

for appearance in ${appearances//,/ }; do
  [[ "$appearance" == light || "$appearance" == dark ]] || { echo "不認得的外觀：$appearance(可用 light、dark)" >&2; exit 64; }
done
for size in ${sizes//,/ }; do
  content_size "$size" >/dev/null || { echo "不認得的字級：$size(可用 default、xxl、ax5)" >&2; exit 64; }
done

repo="$(cd "$(dirname "$0")/.." && pwd)"
project="$repo/src/App/MyMoney.xcodeproj"
# 跟一般測試分開的 derived data,不跟同一個 worktree 裡正在跑的建置搶鎖。
derived="$repo/.derivedData/screen-tour"
work="$(mktemp -d -t my-money-screen-tour)"
mkdir -p "$output"

# 專用模擬器:iPhone 17 維持舊名稱「MyMoney Screen Tour」,其他型號帶型號，各有一台。
if [[ "$device_type" == "$DEFAULT_DEVICE_TYPE" ]]; then
  SIMULATOR_NAME="MyMoney Screen Tour"
else
  SIMULATOR_NAME="MyMoney Screen Tour ($device_type)"
fi
if [[ -z "$udid" ]]; then
  udid="$(xcrun simctl list devices available -j |
    jq -r --arg name "$SIMULATOR_NAME" '[.devices[][] | select(.name == $name)][0].udid // empty')"
  if [[ -z "$udid" ]]; then
    echo "建立模擬器「${SIMULATOR_NAME}」($device_type)"
    udid="$(xcrun simctl create "$SIMULATOR_NAME" "$device_type")"
  fi
fi
xcrun simctl bootstatus "$udid" -b >/dev/null
original_appearance="$(xcrun simctl ui "$udid" appearance)"

failed=()
cleanup() {
  xcrun simctl ui "$udid" appearance "$original_appearance" || true
  xcrun simctl status_bar "$udid" clear || true
  # 有失敗的組合時留下 log 和結果檔。
  if ((${#failed[@]} == 0)); then rm -rf "$work"; fi
}
trap cleanup EXIT

# 固定狀態列(時間、電量、訊號),改前改後的截圖才比得出差別。
xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --dataNetwork wifi ||
  echo "警告：無法固定狀態列，截圖的時間和電量會不一樣" >&2

echo "建置 app 與 UI 測試(log:$work/build.log)"
if ! xcodebuild build-for-testing -project "$project" -scheme MyMoney \
  -destination "id=$udid" -derivedDataPath "$derived" > "$work/build.log" 2>&1; then
  grep -E "error:|\*\* " "$work/build.log" | tail -20 >&2 || true
  failed+=(build) # 留下 build.log(cleanup 只在沒有失敗時刪掉工作目錄)
  exit 1
fi

# 跑一種組合，等 xcodebuild 結束;卡住時，結果檔寫好後再等一段時間就砍掉。
run_tour() {
  local size="$1" result="$2" log="$3" pid waited=0
  TEST_RUNNER_SCREEN_TOUR_CONTENT_SIZE="$(content_size "$size")" xcodebuild test-without-building \
    -project "$project" -scheme MyMoney -destination "id=$udid" -derivedDataPath "$derived" \
    -parallel-testing-enabled NO -collect-test-diagnostics never -only-testing:"$TEST_ID" \
    -resultBundlePath "$result" > "$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -f "$result/Info.plist" ]]; then
      waited=$((waited + 5))
      if ((waited > EXIT_GRACE_SECONDS)); then
        echo "  xcodebuild 在結果檔寫好後 ${EXIT_GRACE_SECONDS} 秒還沒結束，砍掉"
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        # 砍掉之後 exit status 是 143,成敗改看 log 裡的測試結果。
        grep -qE "^Test Suite '(All|Selected) tests' passed" "$log"
        return
      fi
    fi
    sleep 5
  done
  wait "$pid"
}

for appearance in ${appearances//,/ }; do
  xcrun simctl ui "$udid" appearance "$appearance"
  for size in ${sizes//,/ }; do
    combo="$appearance-$size"
    result="$work/$combo.xcresult"
    log="$work/$combo.log"
    echo "巡覽 $combo"
    if ! run_tour "$size" "$result" "$log"; then
      grep -E "error:|failed|\*\* TEST" "$log" | tail -10 >&2 || true
      failed+=("$combo")
    fi
    if [[ ! -f "$result/Info.plist" ]]; then
      echo "  沒有結果檔，無法匯出截圖" >&2
      [[ " ${failed[*]:-} " == *" $combo "* ]] || failed+=("$combo")
      continue
    fi

    exported="$work/$combo"
    xcrun xcresulttool export attachments --path "$result" --output-path "$exported" >/dev/null
    rm -f "$output/$combo"-*.png
    # 巡覽的 attachment 名稱是「畫面-序號」;suggestedHumanReadableName 是「畫面-序號_編號_UUID.png」。
    count=0
    while IFS=$'\t' read -r file name; do
      cp "$exported/$file" "$output/$combo-${name%%_*}.png"
      count=$((count + 1))
    done < <(jq -r '.[].attachments[] | select(.isAssociatedWithFailure | not)
      | select(.suggestedHumanReadableName | test("^[a-z0-9-]+-[0-9]+_.*\\.png$"))
      | [.exportedFileName, .suggestedHumanReadableName] | @tsv' "$exported/manifest.json")
    echo "  $count 張"
  done
done

echo "截圖在 $output"
if ((${#failed[@]} > 0)); then
  echo "失敗的組合:${failed[*]}。log 和結果檔在 $work" >&2
  exit 1
fi
