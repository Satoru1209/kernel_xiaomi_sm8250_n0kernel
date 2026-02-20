#!/bin/bash
set -euo pipefail
# 内核编译脚本 - 适配GitHub Actions CI环境
# 支持参数：<device_codename> [ksu]

# ===================== 全局配置 =====================
# 工具链路径（与build.yml中Toolchain路径一致）
TOOLCHAIN_PATH="${HOME}/zyc-clang/bin"
# ccache缓存目录（与build.yml中Cache路径一致）
CCACHE_DIR="${HOME}/.cache/ccache_mikernel"
# KernelSU版本
KSU_VERSION="v1.1.1"
# AnyKernel3仓库信息
AK3_REPO="https://github.com/liyafe1997/AnyKernel3"
AK3_BRANCH="kona"
# 编译参数
MAKE_BASE_ARGS="ARCH=arm64 SUBARCH=arm64 O=out CC=clang"
MAKE_CROSS_ARGS="CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- CLANG_TRIPLE=aarch64-linux-gnu-"
MAKE_ARGS="${MAKE_BASE_ARGS} ${MAKE_CROSS_ARGS}"
# 颜色输出（CI友好）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===================== 函数定义 =====================
# 日志输出
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查依赖命令
check_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "依赖命令 $1 未找到，请检查环境"
    fi
}

# ===================== 入参校验 =====================
if [ $# -lt 1 ]; then
    log_error "缺少参数！使用方法：bash $0 <device_codename> [ksu]
    示例：bash $0 umi        # 编译umi，不启用KSU
    示例：bash $0 lmi ksu   # 编译lmi，启用KSU"
fi
TARGET_DEVICE="$1"
KSU_ENABLE=0
if [ $# -eq 2 ] && [ "$2" = "ksu" ]; then
    KSU_ENABLE=1
    log_info "已启用 KernelSU (${KSU_VERSION})"
else
    log_info "未启用 KernelSU"
fi

# ===================== 环境检查 =====================
log_info "开始检查编译环境"
# 检查工具链目录
if [ ! -d "${TOOLCHAIN_PATH}" ]; then
    log_error "工具链目录不存在：${TOOLCHAIN_PATH}"
fi
export PATH="${TOOLCHAIN_PATH}:${PATH}"
# 检查核心编译命令
check_cmd "clang"
check_cmd "aarch64-linux-gnu-ld"
check_cmd "arm-linux-gnueabi-ld"
check_cmd "ccache"
check_cmd "git"
check_cmd "zip"
check_cmd "curl"
# 检查设备defconfig
DEFCONFIG_FILE="arch/arm64/configs/vendor/${TARGET_DEVICE}_defconfig"
if [ ! -f "${DEFCONFIG_FILE}" ]; then
    log_error "设备${TARGET_DEVICE}的defconfig不存在！可用defconfig：
    $(ls arch/arm64/configs/*_defconfig | sed 's/arch\/arm64\/configs\///g')"
fi
# 打印clang版本
log_info "Clang 版本信息："
clang --version | head -1

# ===================== 缓存配置 =====================
log_info "配置ccache缓存，目录：${CCACHE_DIR}"
export CCACHE_DIR
export CC="ccache gcc"
export CXX="ccache g++"
export PATH="/usr/lib/ccache:${PATH}"
ccache -z >/dev/null 2>&1 # 重置统计
ccache -M 20G >/dev/null 2>&1 # 限制缓存大小20G（CI环境适配）

# ===================== KernelSU 安装 =====================
if [ ${KSU_ENABLE} -eq 1 ]; then
    log_info "开始拉取并安装 KernelSU ${KSU_VERSION}"
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s "${KSU_VERSION}" || log_error "KernelSU 安装失败"
fi

# ===================== 清理旧文件 =====================
log_info "清理旧编译产物和临时文件"
rm -rf out/ anykernel/ .dts.bak
mkdir -p out

# ===================== MIUI 设备树适配 =====================
log_info "开始适配MIUI设备树配置"
DTS_SOURCE="arch/arm64/boot/dts/vendor/qcom"
# 备份原始设备树
cp -a "${DTS_SOURCE}" .dts.bak
# 修正面板尺寸
sed -i 's/<154>/<1537>/g' "${DTS_SOURCE}"/dsi-panel-j1s*
sed -i 's/<154>/<1537>/g' "${DTS_SOURCE}"/dsi-panel-j2*
sed -i 's/<155>/<1544>/g' "${DTS_SOURCE}"/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
sed -i 's/<155>/<1545>/g' "${DTS_SOURCE}"/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
sed -i 's/<155>/<1546>/g' "${DTS_SOURCE}"/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
sed -i 's/<155>/<1546>/g' "${DTS_SOURCE}"/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
sed -i 's/<70>/<695>/g' "${DTS_SOURCE}"/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
sed -i 's/<70>/<695>/g' "${DTS_SOURCE}"/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
sed -i 's/<70>/<695>/g' "${DTS_SOURCE}"/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
sed -i 's/<70>/<695>/g' "${DTS_SOURCE}"/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
sed -i 's/<71>/<710>/g' "${DTS_SOURCE}"/dsi-panel-j1s*
sed -i 's/<71>/<710>/g' "${DTS_SOURCE}"/dsi-panel-j2*
# 启用小米智能帧率，关闭QSync最低刷新率
sed -i 's/\/\/ mi,mdss-dsi-pan-enable-smart-fps/mi,mdss-dsi-pan-enable-smart-fps/g' "${DTS_SOURCE}"/dsi-panel*
sed -i 's/\/\/ mi,mdss-dsi-smart-fps-max_framerate/mi,mdss-dsi-smart-fps-max_framerate/g' "${DTS_SOURCE}"/dsi-panel*
sed -i 's/\/\/ qcom,mdss-dsi-pan-enable-smart-fps/qcom,mdss-dsi-pan-enable-smart-fps/g' "${DTS_SOURCE}"/dsi-panel*
sed -i 's/qcom,mdss-dsi-qsync-min-refresh-rate/\/\/qcom,mdss-dsi-qsync-min-refresh-rate/g' "${DTS_SOURCE}"/dsi-panel*
# 启用MIUI支持的刷新率
sed -i 's/120 90 60/120 90 60 50 30/g' "${DTS_SOURCE}"/dsi-panel-g7a-36-02-0c-dsc-video.dtsi
sed -i 's/120 90 60/120 90 60 50 30/g' "${DTS_SOURCE}"/dsi-panel-g7a-37-02-0a-dsc-video.dtsi
sed -i 's/120 90 60/120 90 60 50 30/g' "${DTS_SOURCE}"/dsi-panel-g7a-37-02-0b-dsc-video.dtsi
sed -i 's/144 120 90 60/144 120 90 60 50 48 30/g' "${DTS_SOURCE}"/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
# 启用设备树亮度控制
sed -i 's/\/\/39 00 00 00 00 00 03 51 03 FF/39 00 00 00 00 00 03 51 03 FF/g' "${DTS_SOURCE}"/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
sed -i 's/\/\/39 00 00 00 00 00 03 51 0D FF/39 00 00 00 00 00 03 51 0D FF/g' "${DTS_SOURCE}"/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi
sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' "${DTS_SOURCE}"/dsi-panel-j1s*
sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' "${DTS_SOURCE}"/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' "${DTS_SOURCE}"/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' "${DTS_SOURCE}"/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' "${DTS_SOURCE}"/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' "${DTS_SOURCE}"/dsi-panel-j1s*
sed -i 's/\/\/39 01 00 00 01 00 03 51 03 FF/39 01 00 00 01 00 03 51 03 FF/g' "${DTS_SOURCE}"/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
sed -i 's/\/\/39 01 00 00 11 00 03 51 03 FF/39 01 00 00 11 00 03 51 03 FF/g' "${DTS_SOURCE}"/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi

# ===================== 内核编译 =====================
log_info "开始生成${TARGET_DEVICE}配置文件"
make ${MAKE_ARGS} "${TARGET_DEVICE}_defconfig"

log_info "调整内核编译配置"
scripts/config --file out/.config \
    --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
    -e PERF_CRITICAL_RT_TASK \
    -e SF_BINDER \
    -e OVERLAY_FS \
    -d DEBUG_FS \
    -e MIGT \
    -e MIGT_ENERGY_MODEL \
    -e MIHW \
    -e PACKAGE_RUNTIME_INFO \
    -e BINDER_OPT \
    -e KPERFEVENTS \
    -e MILLET \
    -e PERF_HUMANTASK \
    -d LTO_CLANG \
    -e XIAOMI_MIUI \
    -d MI_MEMORY_SYSFS \
    -e TASK_DELAY_ACCT \
    -e MIUI_ZRAM_MEMORY_TRACKING \
    -d CONFIG_MODULE_SIG_SHA512 \
    -d CONFIG_MODULE_SIG_HASH \
    -e MI_FRAGMENTION \
    -e PERF_HELPER \
    -e BOOTUP_RECLAIM \
    -e MI_RECLAIM \
    -e RTMM
# KSU配置开关
if [ ${KSU_ENABLE} -eq 1 ]; then
    scripts/config --file out/.config -e KSU
else
    scripts/config --file out/.config -d KSU
fi
# 重新生成配置
make ${MAKE_ARGS} olddefconfig

log_info "开始编译内核，线程数：$(nproc)"
make ${MAKE_ARGS} -j$(nproc)

# 检查编译产物
IMAGE_FILE="out/arch/arm64/boot/Image"
if [ ! -f "${IMAGE_FILE}" ]; then
    log_error "内核编译失败！未找到产物：${IMAGE_FILE}"
fi
log_info "内核编译成功，产物已生成：${IMAGE_FILE}"

# ===================== 生成DTB =====================
log_info "合并DTB文件"
find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + > out/arch/arm64/boot/dtb
if [ ! -f "out/arch/arm64/boot/dtb" ]; then
    log_error "DTB文件合并失败"
fi

# ===================== 恢复原始设备树 =====================
log_info "恢复原始设备树文件"
rm -rf "${DTS_SOURCE}"
mv .dts.bak "${DTS_SOURCE}"
rm -f .dts.bak

# ===================== 打包刷机包 =====================
log_info "拉取AnyKernel3并打包刷机包"
git clone --single-branch --branch "${AK3_BRANCH}" --depth=1 "${AK3_REPO}" anykernel
# 复制编译产物到AnyKernel3
mkdir -p anykernel/kernels/
cp "${IMAGE_FILE}" anykernel/kernels/
cp out/arch/arm64/boot/dtb anykernel/kernels/
# 生成包名（含设备/KS/时间/CommitID）
GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
KSU_SUFFIX=$( [ ${KSU_ENABLE} -eq 1 ] && echo "SukiSU-SUSFS" || echo "NoKernelSU" )
ZIP_FILENAME="Kernel_MIUI_${TARGET_DEVICE}_${KSU_SUFFIX}_$(date +'%Y%m%d_%H%M%S')_${GIT_COMMIT_ID}.zip"
# 打包（排除无用文件）
cd anykernel
zip -r9 "${ZIP_FILENAME}" ./* -x .git .gitignore out/ ./*.zip
mv "${ZIP_FILENAME}" ../
cd ..
# 清理临时目录
rm -rf anykernel/

# ===================== 完成 =====================
log_info "编译打包全部完成！刷机包路径：./${ZIP_FILENAME}"
# 打印ccache统计
ccache -s
exit 0