# dmgbuild settings for Pith — see ./Scripts/make_dmg.sh
# https://dmgbuild.readthedocs.io
# Paths come in via -D defines because dmgbuild execs this file without __file__.
import os.path

application = defines.get("app", "Pith.app")
appname = os.path.basename(application)

format = "UDZO"                       # compressed, read-only
files = [application]
symlinks = {"Applications": "/Applications"}

# Window: 600x400 points, positioned on screen. Icon coordinates below are in
# that 600x400 space (origin top-left). The background art (dmg_background.png,
# rendered at 2x) draws the arrow between these two slots.
window_rect = ((200, 120), (600, 400))
background = defines.get("bg", "dmg_background.png")
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 100
text_size = 13
icon_locations = {
    appname: (150, 210),
    "Applications": (450, 210),
}
