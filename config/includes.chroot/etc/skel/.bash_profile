# ~/.bash_profile
# Executed by bash for login shells

if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Auto-launch Labwc on TTY1 if no display server is running
if [ -z "${WAYLAND_DISPLAY}" ] && [ -z "${DISPLAY}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    exec /usr/local/bin/launch-labwc
fi
