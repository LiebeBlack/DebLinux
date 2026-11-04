#!/bin/sh
# /etc/profile.d/99-autostart-labwc.sh
# Autostart Labwc directly upon login on TTY1 when no DISPLAY is active
# Optimized for Intel - minimal and error-free

# Only autostart on TTY1 for non-root users
if [ "$(tty 2>/dev/null)" = "/dev/tty1" ] && [ "$(id -u)" -ne 0 ]; then
    # Check if a graphical session is already running
    if [ -z "${WAYLAND_DISPLAY}" ] && [ -z "${DISPLAY}" ]; then
        # Check if labwc is available
        if command -v labwc >/dev/null 2>&1; then
            echo "Starting lightweight Wayland session (Labwc) on TTY1..."
            exec /usr/local/bin/launch-labwc
        else
            echo "Labwc not installed, staying in text mode."
        fi
    fi
fi

