#!/bin/sh
# Out-of-tree i915 builds hit several quote-included headers that assume the
# driver lives inside the real kernel source tree (tracepoint headers use
# TRACE_INCLUDE_PATH relative to $(srctree), and some display/gt files
# #include sibling headers by relative path that only resolves that way too).
# This symlinks the pieces the build needs into the installed kernel headers
# tree so those includes resolve, without touching any files that actually
# belong to the linux-headers package.
set -e

# $1: kernel_source_dir, passed explicitly by dkms.conf's PRE_BUILD line --
# DKMS expands ${kernel_source_dir} etc. when building that command string,
# but does NOT export those as environment variables to the script it runs.
KSRC="$1"

D="$KSRC/drivers/gpu/drm/i915"
B="$(pwd)/drivers/gpu/drm/i915"

mkdir -p "$D/gvt"
ln -sfn "$B/display" "$D/display"
ln -sfn "$B/gt" "$D/gt"
ln -sf "$B/intel_uncore_trace.h" "$D/intel_uncore_trace.h"
ln -sf "$B/i915_trace.h" "$D/i915_trace.h"
ln -sf "$B/gvt/trace.h" "$D/gvt/trace.h"

mkdir -p "$KSRC/drivers/platform/x86"
ln -sf "$(pwd)/drivers/platform/x86/intel_ips.h" \
       "$KSRC/drivers/platform/x86/intel_ips.h"
