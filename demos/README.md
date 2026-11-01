# Zigine demos

These are small games built directly on Zigine's current 2D internals. The
engine currently exposes a renderer command buffer rather than a complete
window/input backend, so each demo runs a deterministic simulation and reports
its rendered command count. The game state and drawing code are deliberately
separated at the point where a platform backend can consume the commands.

Run one with:

```sh
cd demos/space_invaders && zig build run
cd demos/flappy_bird && zig build run
cd demos/pacman && zig build run
```

Space Invaders and Flappy Bird are the most complete examples and include
restart/game-over behavior and collision handling. Space Invaders now shows a
victory overlay when every invader is destroyed.

Controls:

- Space Invaders: Arrow keys or A/D to move, Space to fire, Escape to quit.
- Flappy Bird: Space to flap; Space again after game over to restart.
- Pacman: Arrow keys or WASD to move, Escape to quit.

The editor scene for each game is stored at `zigine/main.scene`, so opening
the demo directory as a Zigine project displays its game-specific hierarchy.
