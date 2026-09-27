# Campfire

## Unreleased

- **Guildies who log out leave the map.** Their dot used to stay where they were standing and sit there for as long as you kept the map open. The window already knew to forget someone who had gone quiet; the map did not. Both follow the same rule now, so the dot goes as soon as the guild roster says they're offline.
- **You no longer show up as a player near yourself.** Your own messages come back to you, and the check that should drop them went by name - which failed whenever your own surname was hidden from you, so you were stored as a player like any other and drawn on the map and in the window. The check doesn't go by name any more. It was costing everyone else as well: with yourself in the list Campfire thought someone was standing next to you and sent your position three times as often as it needed to.
- **No Campfire dot on top of your party and raid.** The game draws them for you, so two dots fought over the same spot and hovering picked one of them at random. Campfire is meant to leave them to the game, but the check never matched anyone: it read a Forever surname as a realm name, so "Duplo Bonk" in your group and "Duplo Bonk" on the map looked like two different players. It reads your group properly now, and the dot comes back when the group breaks up. If everyone Campfire can see is in your group, the window says so instead of looking empty.
- **Whispers reach the player you clicked.** Clicking a name opened a whisper to the first name only and sent the surname as the message.

## 0.1.0-beta6

- Updated shared YippYapp library.

## 0.1.0-beta5

- Updated shared YippYapp library.

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
