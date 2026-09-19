# Campfire

**Find your guildies out in the world, in WoW: Forever.**

Campfire shows which guildies are near you: how many yards away they are, in which direction and in which
zone. It's handy for meeting up, grouping for a quest or finding the guildie who's crafting something for you.
Click a name to whisper them.

> **Status: beta (0.1.0-beta1).** Built for the WoW: Forever beta. Expect rough edges, and please report what
> you find.

## What it does

- **Who is nearby?** A small window lists guildies who run Campfire, nearest first, with the distance in
  yards, the direction (north, southeast and so on) and their zone.
- **Too far to measure.** Guildies on another continent show their zone instead of a distance.
- **Indoors or in an instance.** The game gives no position there, so Campfire says so instead of showing an
  old one.
- **Whisper in one click.** Click a name in the list.

## Sharing your position

The game only tells an addon where *you* are, not where other players are. So everyone who runs Campfire
shares their own position with the guild, and that's how the list is built.

- **On by default.** While Campfire is on, your position is shared with your guild over the guild addon
  channel. Only guildies who also run Campfire can see it; nothing goes to anyone outside your guild.
- **Easy to turn off.** Untick **Share my position with my guild** in the Campfire window, in Options or on
  the welcome page, or type `/campfire share`. Guildies stop seeing you straight away. You still see guildies
  who share.
- **Light on traffic.** Your position goes out when you've moved a bit, at most every 15 seconds, and about
  every 90 seconds when you stand still. Nothing is sent while the game locks down chat.

## Getting started

1. Install Campfire. Guildies who want to show up in your list install it too.
2. Click the Campfire icon on the minimap, or type `/campfire`. If you use several YippYapp addons, the icon
   sits behind the YippYapp button there.

### Commands

| Command | What it does |
|---|---|
| `/campfire` | Open or close the Campfire window |
| `/campfire share` | Turn sharing your position on or off |
| `/campfire list` | Print the list in chat |
| `/campfire options` | Open the settings |

Settings are under **Options → AddOns → YippYapp → Campfire**. Right-clicking the Campfire icon opens them
too.

## Part of YippYapp

Campfire is part of **YippYapp**, a set of addons for WoW: Forever that work even better together. Each one
works fully on its own. With more of them installed:

- **One minimap button.** They share a single YippYapp button on the minimap. Click it for a row with each
  addon's icon. There is also an optional launcher bar at the screen edge, off by default, that you can turn
  on in the YippYapp settings.
- **One group in the AddOn list.** They appear together under **YippYapp** in the in-game AddOn list.
- **With Guildhall**, find out who in your guild can craft an item, then open Campfire to see how far away
  they are and whisper them to meet up.

Other YippYapp addons:
- **Guildhall** is your guild's crafting directory: who can make what, spares and wanted posts.
- **Skillwright** plans the cheapest or fastest route to max skill in a profession.
- **AutoFeed** keeps one-button macros for your best food, water, potions, scrolls and bandages.
- **BuffWarden** shows the buffs you and your group are missing, and casts or requests them in one click.

## Installing from source

Releases will come through CurseForge. To run the source directly:

1. Clone this repo into `Interface\AddOns\Campfire`.
2. Clone [LibForever-1.0](https://github.com/vBaustad/LibForever-1.0) into `Campfire\Libs\LibForever-1.0`.
   The packaged releases include it automatically.

## License

MIT. Bundles LibStub, CallbackHandler-1.0, AceComm-3.0, ChatThrottleLib, LibDataBroker-1.1 and LibDBIcon-1.0
(see LICENSE).
