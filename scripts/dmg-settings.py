"""Finder layout for the drag-to-install disk image, including on headless CI."""

# dmgbuild provides the command-line definitions when loading this file.
files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"
compression_level = 9
# Do not set FinderInfo on the signed app bundle; strict codesign rejects it.
hide_extensions = []
icon_locations = {"FrameCut.app": (180, 210), "Applications": (480, 210)}
window_rect = ((200, 160), (660, 468))
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
grid_spacing = 80
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 14
icon_size = 112
