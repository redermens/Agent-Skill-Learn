#!/bin/bash
#
# Copyright (c) 2026 Huawei Device Co., Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
set -euo pipefail

# ==============================================================
# coverage_pipeline.sh
# Automated coverage pipeline for OpenHarmony developer tests.
#
# Usage:
#   ./cicd/coverage_pipeline.sh -p <part_name1,part_name2,...> [options]
#
# Required:
#   -p <parts>       Comma-separated part names (e.g. graphic_2d,graphic_3d)
#
# Options:
#   -d <ip:port>     HDC device address (e.g. 192.168.1.100:8710)
#   -b <path>        Baseline lcov .info file for coverage comparison
#   -t <target>      Specific build target (defaults to part name)
#   -i               Install prerequisites first (lcov, pip packages)
#   -c <percent>     Target coverage threshold for exit message (default: 95)
#   -h               Show help
#
# Pipeline stages:
#   P1: Build part(s) with use_clang_coverage=true
#   P2: Push coverage-instrumented .so to device
#   P3: Execute UT on device to generate .gcda
#   P4: Pull .gcda from device
#   P5: Generate HTML coverage report + lcov .info
#   P6: Analyze uncovered branches → JSON report for agent (P7)
#
# Environment:
#   Must run from within a full OpenHarmony source tree.
#   This script lives at <OHOS_ROOT>/test/testfwk/developer_test/cicd/
# ==============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVTEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Resolve OHOS root ---
resolve_ohos_root() {
    local dir="$DEVTEST_DIR"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/build.sh" ] && [ -d "$dir/prebuilts" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo ""
}

OHOS_ROOT="$(resolve_ohos_root)"
if [ -z "$OHOS_ROOT" ]; then
    echo "ERROR: Cannot find OpenHarmony root (no build.sh + prebuilts/ found above $DEVTEST_DIR)"
    echo "       Run this script from within a full OpenHarmony source tree."
    exit 1
fi

# --- Defaults ---
PARTS=""
DEVICE_IP=""
DEVICE_PORT=""
BASELINE_INFO=""
BUILD_TARGET=""
INSTALL_DEPS=false
TARGET_COV=95

usage() {
    sed -n 's/^# //p; s/^#$//p' "$0"
    exit 0
}

while getopts "p:d:b:t:ic:h" opt; do
    case "$opt" in
        p) PARTS="$OPTARG" ;;
        d) DEVICE_IP="${OPTARG%:*}"; DEVICE_PORT="${OPTARG##*:}" ;;
        b) BASELINE_INFO="$OPTARG" ;;
        t) BUILD_TARGET="$OPTARG" ;;
        i) INSTALL_DEPS=true ;;
        c) TARGET_COV="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$PARTS" ]; then
    echo "ERROR: -p <parts> is required"
    usage
fi

echo "=========================================="
echo " Coverage Pipeline"
echo "=========================================="
echo " OHOS_ROOT:       $OHOS_ROOT"
echo " DEVTEST_DIR:     $DEVTEST_DIR"
echo " Parts:           $PARTS"
echo " Device:          ${DEVICE_IP:-<from config>}:${DEVICE_PORT:-8710}"
echo " Baseline:        ${BASELINE_INFO:-<none>}"
echo " Target coverage: ${TARGET_COV}%"
echo ""

# --- Validate config/user_config.xml ---
USER_CONFIG="$DEVTEST_DIR/config/user_config.xml"
if [ ! -f "$USER_CONFIG" ]; then
    echo "ERROR: $USER_CONFIG not found!"
    exit 1
fi

# --- Write device IP:Port into user_config.xml ---
if [ -n "$DEVICE_IP" ] && [ -n "$DEVICE_PORT" ]; then
    echo ">>> Writing device $DEVICE_IP:$DEVICE_PORT to user_config.xml..."
    python3 -c "
import xml.etree.ElementTree as ET
cfg = '$USER_CONFIG'
tree = ET.parse(cfg)
root = tree.getroot()
for device in root.findall('environment/device'):
    if device.attrib.get('type') == 'usb-hdc':
        info = device.find('info')
        if info is not None:
            info.set('ip', '$DEVICE_IP')
            info.set('port', '$DEVICE_PORT')
            info.set('sn', '')
tree.write(cfg, encoding='utf-8', xml_declaration=True)
print('    Done.')
"
fi

# --- Check all_subsystem_config.json for all parts ---
CONFIG_JSON="$DEVTEST_DIR/local_coverage/all_subsystem_config.json"
MISSING_PARTS=""
IFS=',' read -ra PART_LIST <<< "$PARTS"
for part in "${PART_LIST[@]}"; do
    if ! python3 -c "import json; f=open('$CONFIG_JSON'); d=json.load(f); exit(0 if '$part' in d else 1)" 2>/dev/null; then
        MISSING_PARTS="$MISSING_PARTS $part"
    fi
done
if [ -n "$MISSING_PARTS" ]; then
    echo ""
    echo "    ================================================================"
    echo "    WARNING: Some parts not found in all_subsystem_config.json:$MISSING_PARTS"
    echo "    Without this mapping:"
    echo "      - P5 (coverage report) will include ALL source files, not filtered by part"
    echo "      - P6 (uncovered analysis) will show branches from all system code"
    echo ""
    echo "    To fix, add entries like this to $CONFIG_JSON:"
    echo '      "your_part_name": {'
    echo '        "name": "your_part_name",'
    echo '        "path": ["foundation/your_subsystem/your_component"]'
    echo '      }'
    echo "    ================================================================"
    echo ""
    echo "    Continue anyway? (y/N): "
    read -r CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
fi

# --- Install prerequisites (once) ---
if [ "$INSTALL_DEPS" = true ]; then
    echo ">>> Installing prerequisites..."
    sudo apt-get install -y lcov dos2unix 2>/dev/null
    python3 -m pip install lxml selectolax CppHeaderParser 2>/dev/null || true
    # Enable branch coverage in /etc/lcovrc
    if [ -f /etc/lcovrc ]; then
        sudo sed -i 's/lcov_branch_coverage = 0/lcov_branch_coverage = 1/' /etc/lcovrc
    fi
fi

# --- Build lcov rc files ---
python3 -c "
import sys, os
sys.path.insert(0, '$DEVTEST_DIR/local_coverage')
from coverage_tools import generate_coverage_rc
generate_coverage_rc('$DEVTEST_DIR')
"

# ---- P1: Build with coverage ----
echo ""
echo ">>> [P1] Building parts with coverage..."
cd "$OHOS_ROOT"
IFS=',' read -ra PART_LIST <<< "$PARTS"
for part in "${PART_LIST[@]}"; do
    target="${BUILD_TARGET:-$part}"
    echo "    Building: $target"
    ./build.sh --product-name rk3568 --build-target "$target" \
        --gn-args use_clang_coverage=true --ccache
done

# ---- P2: Push coverage .so to device ----
cd "$DEVTEST_DIR"
echo ">>> [P2] Pushing coverage .so to device..."
python3 local_coverage/push_coverage_so/push_coverage.py "testpart" "$PARTS" || {
    echo "    WARNING: push_coverage.py failed (maybe HDC not connected?)"
    echo "    Continuing anyway. Fix device connection and re-run."
}

# ---- P3: Execute UT via framework ----
echo ">>> [P3] Executing UT..."
{
    echo "1"
    IFS=',' read -ra PART_LIST <<< "$PARTS"
    for part in "${PART_LIST[@]}"; do
        echo "run -t UT -tp $part -cov coverage"
    done
    echo "quit"
    echo "exit(0)"
} | ./start.sh

# ---- P4: Pull .gcda from device ----
echo ">>> [P4] Pulling .gcda from device..."
# Read device ip/port from config if not set via -d
if [ -z "$DEVICE_IP" ]; then
    CFG_IP=$(python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$USER_CONFIG')
for d in tree.findall('environment/device'):
    if d.attrib.get('type') == 'usb-hdc':
        info = d.find('info')
        if info is not None:
            print(info.get('ip',''), info.get('port','8710'))
" 2>/dev/null)
    DEVICE_IP=$(echo "$CFG_IP" | awk '{print $1}')
    DEVICE_PORT=$(echo "$CFG_IP" | awk '{print $2}')
fi
DEVICE_IP="${DEVICE_IP:-localhost}"
DEVICE_PORT="${DEVICE_PORT:-8710}"

SYSTEM_PART_SERVICE="$DEVTEST_DIR/local_coverage/resident_service/system_part_service.json"
if [ -f "$SYSTEM_PART_SERVICE" ]; then
    python3 local_coverage/resident_service/pull_service_gcda.py \
        "command_str= -tp ${PARTS}"
else
    echo ""
    echo "    ================================================================"
    echo "    WARNING: $SYSTEM_PART_SERVICE not found."
    echo "    Cannot auto-pull .gcda without service→part mapping."
    echo ""
    echo "    Options:"
    echo "      1) Add service mapping to $SYSTEM_PART_SERVICE"
    echo "         See local_coverage/resident_service/public_method.py for format"
    echo ""
    echo "      2) Pull .gcda manually:"
    echo "         hdc -s $DEVICE_IP:$DEVICE_PORT shell"
    echo "         # cd /data/gcov"
    echo "         # tar -czf gcda_${PARTS//,/_}.tar.gz \$(find . -name '*.gcda')"
    echo "         # exit"
    echo "         hdc file recv /data/gcov/gcda_${PARTS//,/_}.tar.gz"
    echo "         # Extract to:"
    echo "         tar -xzf gcda_${PARTS//,/_}.tar.gz -C reports/coverage/data/cxx/"
    echo ""
    echo "    ================================================================"
    echo ""
    echo "    After pulling manually, press Enter to continue..."
    read -r _
fi

# ---- P5: Generate HTML coverage report ----
echo ">>> [P5] Generating coverage report..."
python3 local_coverage/coverage_tools.py "testpart=${PARTS}"

REPORT_DIR="$DEVTEST_DIR/local_coverage/code_coverage/results/coverage/reports/cxx"
INFO_FILE="$REPORT_DIR/ohos_codeCoverage.info"
HTML_DIR="$REPORT_DIR/html"
echo "    HTML report: $HTML_DIR/index.html"
echo "    Lcov info:   $INFO_FILE"

# ---- P6: Analyze uncovered branches ----
echo ">>> [P6] Analyzing uncovered branches..."
if [ -f "$INFO_FILE" ]; then
    ANALYSIS_DIR="$DEVTEST_DIR/reports/coverage_analysis"
    mkdir -p "$ANALYSIS_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_JSON="$ANALYSIS_DIR/uncovered_report_${TIMESTAMP}.json"

    BASELINE_ARGS=""
    if [ -n "$BASELINE_INFO" ] && [ -f "$BASELINE_INFO" ]; then
        BASELINE_ARGS="--baseline $BASELINE_INFO"
    fi

    python3 "$SCRIPT_DIR/extract_uncovered.py" \
        --info "$INFO_FILE" \
        --src-root "$OHOS_ROOT" \
        --output "$OUTPUT_JSON" \
        --parts "$PARTS" \
        $BASELINE_ARGS

    echo "    Uncovered report: $OUTPUT_JSON"
else
    echo "    WARNING: $INFO_FILE not found. Skipping P6."
fi

# ---- Summary ----
echo ""
echo "=========================================="
echo " Pipeline Complete"
echo "=========================================="
if [ -f "$INFO_FILE" ]; then
    LINE_TOTAL=$(grep '^LF:' "$INFO_FILE" | awk -F: '{s+=$2} END {print s}')
    LINE_HIT=$(grep '^LH:' "$INFO_FILE" | awk -F: '{s+=$2} END {print s}')
    BR_TOTAL=$(grep '^BRF:' "$INFO_FILE" | awk -F: '{s+=$2} END {print s}')
    BR_HIT=$(grep '^BRH:' "$INFO_FILE" | awk -F: '{s+=$2} END {print s}')
    if [ -n "$LINE_TOTAL" ] && [ "$LINE_TOTAL" -gt 0 ]; then
        LINE_PCT=$(awk "BEGIN {printf \"%.1f\", 100*$LINE_HIT/$LINE_TOTAL}")
        BR_PCT=$(awk "BEGIN {printf \"%.1f\", 100*$BR_HIT/$BR_TOTAL}")
        echo " Line coverage:   $LINE_HIT / $LINE_TOTAL ($LINE_PCT%)"
        echo " Branch coverage: $BR_HIT / $BR_TOTAL ($BR_PCT%)"
        echo ""
        if awk "BEGIN {exit !($LINE_PCT >= $TARGET_COV)}"; then
            echo " Target ${TARGET_COV}% line coverage REACHED!"
        else
            echo " Target: ${TARGET_COV}% (current: ${LINE_PCT}%)"
            echo ""
            echo " Next step (P7): Have the agent read the uncovered report and"
            echo " write new UT cases to cover the remaining branches."
            echo " Then re-run this pipeline."
        fi
    fi
fi
echo ""
echo " HTML report:  $HTML_DIR/index.html"
echo " P6 analysis:  ${OUTPUT_JSON:-<not generated>}"
echo "=========================================="
