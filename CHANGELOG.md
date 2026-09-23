# Campfire

## 0.1.0-beta4

- Updated shared YippYapp library.

## 0.1.0-beta3

- **See where players are.** Each row shows the spot they're at ("Goldshire", "Fargodeep Mine") on the right, with how far and which way underneath ("1300 yd SW", or "right here" when they're close). Under the name are their level and class ("20 Priest").
- **Campfire players on the map.** A small dot for each of them on the world map and the zone map, in their class colour, the same size at every zoom. Hover for name, level, class, where they are and how far; click to whisper. Dots are drawn on zone maps only, so the continent map stays clean ("Map dots only in my zone"), at most 40 at a time, nearest first. Turn them off with "Show Campfire players on the map"; they start off when GuildMap is installed.
- **Your zone only.** The list shows players in your zone; players in other zones are counted ("2 in your zone (1 guildie), 3 more elsewhere"). Tick "Show all zones" in the Campfire window to list everyone.
- **Campfire players on your faction outside your guild** also see you, and you see them (grey in the list), over a hidden channel the other faction can't see. Untick "Also share with other Campfire players on my faction" in the settings to share with your guild only.
- **"Hide my position"** replaces "Share my position with my guild": one switch in the Campfire window (and in the settings) that stops sharing with everyone at once. `/campfire hide` does the same. If you had turned sharing off, your position stays hidden.

## 0.1.0-beta2

- **Positions are shared again.** Messages were held back during the game's chat lockdown, so guildies never saw each other.
- Whispers from the list reach players on your own realm.
- /campfire debug shows messages sent and received.

## 0.1.0-beta1

The first beta of Campfire for WoW: Forever.

- **See which guildies are nearby.** The Campfire window lists guildies who run Campfire, nearest first, with how many yards away they are, the direction and their zone. Guildies on another continent show their zone only, and guildies indoors or in an instance say so.
- **Whisper in one click.** Click a name in the list to start a whisper.
- **Your position is shared with your guild by default** while Campfire is on, over the guild addon channel. Only guildies who also run Campfire can see it.
- **Turning sharing off is one click.** Untick "Share my position with my guild" in the Campfire window, in Options or on the welcome page, or type `/campfire share`. Guildies stop seeing you straight away, and you still see guildies who share.
- Open Campfire from its minimap button (behind the YippYapp button if you use several YippYapp addons), the addon compartment or `/campfire`. Right-click the button for settings.
- Settings are under Options -> AddOns -> YippYapp -> Campfire.
