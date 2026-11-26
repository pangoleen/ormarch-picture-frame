# Sourced by wifi/build.sh and image/build.sh: the radxa-pkg/aic8800 commit that
# both the Wi-Fi driver build and the root-filesystem firmware are taken from.
# The clone at $AIC_CLONE has no checked-out working tree; read it with
# `git -C "$AIC_CLONE" archive "$BASE_COMMIT" <path>`.
# Expects ROOT to be set by the sourcing script.
BASE_REPO="https://github.com/radxa-pkg/aic8800"
BASE_COMMIT="e9e43ed79c50483080e9bcdfb08caeeb869d7191"   # 2026-10-12, release 5.0+git20260123.5f7be68d-10
AIC_CLONE="$ROOT/refs/aic/radxa-pkg_aic8800"
