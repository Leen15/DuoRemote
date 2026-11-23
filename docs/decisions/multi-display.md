# Multi-display Macs: manual equal-grid switching

## What happens

A Mac with several displays (tested: a MacBook Pro plus three external monitors) arrives over
macOS Screen Sharing as **one stitched framebuffer** covering every display in its arranged
layout. DuoRemote shows it as one large desktop: the pointer moves across all displays and you
pinch-zoom to whichever area you want. That works and is what the app does.

## Why automatic display discovery is unavailable

- The VNC protocol has a standard way for a server to list its displays: the
  `ExtendedDesktopSize` pseudo-encoding's screen list (RoyalVNCKit exposes it as
  `VNCFramebuffer.screens`).
- **macOS Screen Sharing reports a single screen covering the whole framebuffer to non-Apple
  clients.** Confirmed on the 4-display Mac: the switcher's tab never appeared, because only
  one screen was reported.
- Apple's own Screen Sharing app picks displays using Apple's private, undocumented RFB
  extensions. Building on those would be fragile and isn't planned.
- Asking the Mac directly (e.g. `system_profiler SPDisplaysDataType` over SSH) would need
  Remote Login on the Mac and an SSH client in the app. That breaks the "nothing to set up on
  the Mac" design.

## Options considered and declined

1. A built display switcher: an edge tab plus a glass panel with a colour-bordered, numbered
   live map and All / 1–N buttons. Mockups are in `docs/mockups/displays/`. It was built
   (commits `e525a3e`, `13eab99`), worked against simulated layouts of 1–8 displays, and was
   **removed** (reverted) because macOS never supplies the layout.
2. Detecting displays from the picture: black gaps between displays plus seams between
   touching ones. Started, then stopped. It's a heuristic that can't be dependable for an
   arbitrary set of monitors.
3. A general per-Mac manual arrangement editor was declined as too fiddly. A limited equal-grid
   option is now supported, as described below.

## If automatic discovery is revisited

- If a future macOS reports real screens via `ExtendedDesktopSize`, consider using that screen list instead of the
  manual grid. The earlier switcher code is in history.
- Check what a Mac reports by logging `framebuffer.screens` when the framebuffer is created.

## Manual equal-grid layout (2026-11-23)

Edit Mac → Display layout offers Single (the default), 2 side by side, 3 side by side, 2×2,
and Custom with 1–4 columns and rows. The stitched framebuffer is divided into equal cells,
numbered left to right, then top to bottom. Integer boundaries distribute leftover pixels
without gaps or overlaps. This supports only equal-resolution displays in a regular grid;
it cannot represent mixed resolutions, gaps, offsets, or irregular arrangements.

In both full screen and the laptop-pose deck, ••• → Display offers All and 1–N. Selecting a
display fits its cell and moves the pointer to its centre; All fits the whole framebuffer.
Pinch and pan remain available. The last selection is saved per Mac and re-applied when a
connection or reconnection receives its framebuffer, and whenever the framebuffer is resized.
No private macOS extensions or screen-image heuristics are used.
