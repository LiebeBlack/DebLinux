#!/bin/sh
# Dynamic environment variables for Intel Graphics & Wayland
# Auto-detects hardware and sets optimal drivers

case $- in
    *i*) ;;
      *) return ;;
esac

if [ -d /sys/class/drm ]; then
    if ls /sys/class/drm/*/device/*/i915 2>/dev/null | grep -q "xe"; then
        export LIBVA_DRIVER_NAME=xe
        export MESA_LOADER_DRIVER_NAME=iris
    elif ls /sys/class/drm/card0/device/i915 2>/dev/null; then
        export LIBVA_DRIVER_NAME=i915
        export MESA_LOADER_DRIVER_NAME=iris
    else
        export LIBVA_DRIVER_NAME=i915
        unset MESA_LOADER_DRIVER_NAME
    fi
fi

if [ -z "$GDK_BACKEND" ]; then
    export GDK_BACKEND=wayland,x11
fi

if [ -z "$QT_QPA_PLATFORM" ]; then
    export QT_QPA_PLATFORM=wayland;xcb
fi

if [ -z "$CLUTTER_BACKEND" ]; then
    export CLUTTER_BACKEND=wayland
fi

if [ -z "$SDL_VIDEODRIVER" ]; then
    export SDL_VIDEODRIVER=wayland
fi

if [ -z "$VDPAU_DRIVER" ]; then
    export VDPAU_DRIVER=va_gl
fi

if [ -z "$INTEL_IOMMU" ]; then
    export INTEL_IOMMU=on
fi

if [ -z "$IOMMU" ]; then
    export IOMMU=pt
fi

export EGL_PLATFORM=wayland
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

