# Game Idea

## Space Travel

This game is inspired by the original game "Space Travel" created by Ken Thompson in 1969. The game is a simple simulation of space travel, where the player controls a spaceship and must navigate through space while avoiding obstacles and managing resources.

So while the player navigate through space, they will have a target planet to reach, but will have to manage their trajectory as planets and asteroids will be in the way AND aplly gravitational force to them, which may empty their fuel if they get dragged to much.

As it's a remote spaceship, they can only be moved with bash commands, the player will have to use bash scripts to control the spaceship (in a controlled environment obviously), and will have to use their knowledge of physics and bash scripting to reach the target planet.

So the game is a top-down 2D space with no sprites, everything is procedural, and made to be fun. THe player can shoot lasers to destroy tiny obstacles but that consume fuel, plus there are some neat gravity effects and space anomalies that can be used to reach the target planet faster but are risky to use.

Also the travelling speed is relative to the current camera zoom, so the player can zoom out to travel faster but will have less control over the spaceship, or zoom in to have more control but will travel slower.

And there is a latency between inputs and execution as the players goes further away from the station, so the player can add relays to take down the ping.