# FF.as

## Information
A highly configurable plugin to bring fully functional friendly fire to Sven Co-op. Add chaos, extra challenge, and hilarious player interaction.    
With this plugin you can: 
- Allow players to damage friendly NPCs
- Allow friendly NPCs to damage players
- Allow friendly players to damage each other
- Even works with explosives like grenades and RPG rockets!
- Do it all without messing with player teams and possibly breaking maps

You can configure the exact damage scale as well, even negative numbers can work to make it so the damage heals them (I don't know why you would want this).

## Installation 
Works with the v5.26 Build of Sven Co-Op.    

Download Link of the Last Stable version of Plugin
Installation Instructions
Copy 'FF.as' to 'svencoop\scripts\plugins'. And add this to 'default_plugins.txt':

```
    "plugin"
    {
        "name" "FF"
        "script" "FF"
        "concommandns" "ff"
    }
```

Add this to 'server.cfg'

```
// Friendly Fire
as_command ff.enabled 1
as_command ff.player 1.0
as_command ff.npc 1.0
as_command ff.npcToPlayer 1.0
as_command ff.explosive 1.0
```
  
## Configs:
There are multiple configurations you can manipulate, you have to go to console and type `as_command ff.cvar value`.
Add the below defaults to your "server.cfg" file if you haven't already.

You can use a .cfg file to give a map unique settings for the plugin.
Just navigate to the folder of the map, and find/create a file named mapname.cfg and put lines with `as_command ff.cvar value`

Adjust values above as needed. If a .cfg file is not found for the map, then it will assume the values you put in server.cfg

## CVar Help:
```
enabled - (1 (True) or 0 (False)) Fully enable/disable the plugin
player - (0 - 1) Scale of player to friendly player damage
npc - (0 - 1) 0-1 Scale of player to friendly npc damage
npcToPlayer - (0 - 1) "Scale of friendly npc to player damage
explosive - (0 - 1) Scale of explosive damage
```

## Support

[Support discord here!]( https://discord.gg/3tP3Tqu983)

## License

[CC0](https://creativecommons.org/public-domain/cc0/)
