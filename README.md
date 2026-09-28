# CampKit

A World of Warcraft addon: a standalone, movable campfire button with a hover flyout of your camp items.

- **Left-click** the button to set down your campfire.
- **Right-drag** to move it.
- **Hover** to see your other camp items and how many of each you're carrying.

Camp items are detected automatically from known camping recipes and items in your bags. Known recipes stay on the flyout at 0 so you can see what to craft more of. Add anything else with `/campkit add` in game.

## Install

Copy the `CampKit` folder into `World of Warcraft/_retail_/Interface/AddOns/` (or the matching folder for your client) and reload.

## Configuration

Item IDs, button size, spacing, flyout direction, and hide delay are set at the top of `CampKit.lua`.

## License

MIT. See [LICENSE](LICENSE).
