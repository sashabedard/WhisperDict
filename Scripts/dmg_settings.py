# dmgbuild settings for WhisperDict — see ./Scripts/make_dmg.sh
# https://dmgbuild.readthedocs.io
import os.path

_here = os.path.dirname(os.path.abspath(__file__))

application = defines.get("app", "WhisperDict.app")
appname = os.path.basename(application)

format = "UDZO"                       # compressed, read-only
files = [application]
symlinks = {"Applications": "/Applications"}

# Window: 600x400 points, positioned on screen. Icon coordinates below are in
# that 600x400 space (origin top-left). The background art (dmg_background.png,
# rendered at 2x) draws the arrow between these two slots.
window_rect = ((200, 120), (600, 400))
background = os.path.join(_here, "assets", "dmg_background.png")
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
