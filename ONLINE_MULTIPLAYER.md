# Online Multiplayer (ENet)

This branch adds 2-player online co-op while preserving the existing single-player and local 2-player modes.

## Current implementation

- Godot 4 `ENetMultiplayerPeer`
- Host/client connection flow on the title screen
- Default UDP port: `24567`
- Exactly one remote client per host (2 players total)
- Online mode currently starts in Arcade only
- Host waits for the remote player before entering the battle
- Client enters only after `connected_to_server`
- Local and remote peer IDs are tracked separately in `GameState`
- Local modes explicitly close/reset any active network peer
- Disconnects return both sides to the title flow

## Battle authority model

Online battles are **host authoritative**.

The host owns:

- P1 simulation
- P2 authoritative movement/shooting after receiving remote input
- enemy spawning and AI
- bullets, collision and damage
- enemy deaths and score
- power-up and coin drops
- player lives and win/loss state
- destructible terrain and base-wall state
- placed structures

The client:

- sends P2 input to the host at 30 Hz
- does not run a competing enemy/game-rule simulation
- receives host snapshots at 20 Hz
- interpolates player, enemy, bullet, pickup and building transforms
- mirrors host HUD/game-over state

Input and world snapshots use separate ENet transfer channels. Gameplay decisions always remain on the host.

## Replicated state

`NetworkBattleSync` currently mirrors:

- P1/P2 position, facing, HP, tier and invulnerability
- enemy type, position, rotation and HP
- active bullets and projectile properties
- power-ups and gold coins
- placed buildings
- brick/steel terrain destruction and base-wall material changes
- score/lives/enemy count/RPG HUD text
- battle result and host-driven round restart

The client disables `MainGame._process()` during online play so it cannot independently spawn enemies, advance shovel timers, or restart a round. Client-side actor replicas also have gameplay processing/collision disabled.

## Controls

Host controls P1 normally.

The remote player controls P2, but on the client machine either the P1 action set or P2 action set is accepted. This makes two-PC keyboard/controller testing possible without requiring the remote player to use the second local keyboard layout.

## Testing

### Same PC / loopback

1. Launch two game instances.
2. Instance A: choose `HOST ONLINE CO-OP`.
3. Instance B: leave the address as `127.0.0.1` and choose `JOIN ONLINE CO-OP`.
4. Verify that A controls P1 and B controls P2.
5. Verify enemy movement, bullets, terrain destruction, drops, deaths and HUD remain consistent on both windows.
6. Finish a round and restart from the host; the client should rebuild the arena from the new authoritative round state.
7. Close one instance and verify the remaining peer returns to the title flow.

### LAN

On the client, enter the host machine's LAN IPv4 address. Allow UDP `24567` through the host firewall.

### Internet

Direct internet hosting requires UDP `24567` to reach the host (normally router port forwarding). A VPN/overlay network can avoid manual port forwarding.

## Known limitations / next work

- no client-side movement prediction yet; remote P2 uses interpolation and therefore visibly reflects network latency
- no matchmaking, relay or NAT traversal yet
- online Campaign is still disabled because spire-map choices and persistent RPG state are not synchronized
- replicated VFX/audio are best-effort visuals; authoritative gameplay state is prioritized
- this branch still needs a two-instance Godot 4.5 runtime test before merging to `main`

The RPC layout was checked against the Godot 4.5 multiplayer API documentation. This environment does not contain the project's Godot 4.5 executable, so engine parse/runtime validation still needs to be performed on the development machine.

A later Steam release can replace the connection/lobby transport with Steam Networking while keeping the same host-authoritative gameplay model.
