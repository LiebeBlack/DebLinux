#!/bin/sh
# /etc/profile.d/99-autostart-labwc.sh
# Autostart Labwc directly upon login on TTY1 when no DISPLAY is active

if [ -z "${WAYLAND_DISPLAY}" ] && [ -z "${DISPLAY}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "Starting lightweight Wayland session (Labwc) on TTY1..."
        exec /usr/local/bin/launch-labwc
    fi
fi
