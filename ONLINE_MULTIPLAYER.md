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

The host owns P1, authoritative P2 movement/shooting, enemy AI/spawning, bullets, collisions, damage, drops, score, lives, win/loss state, destructible terrain, base walls and placed structures.

The client sends P2 input at 30 Hz, receives host snapshots at 20 Hz, interpolates replicated actors, and mirrors host HUD/game-over state. It does not run a competing enemy/game-rule simulation.

## Replicated state

`NetworkBattleSync` mirrors players, enemies, bullets, power-ups, coins, placed buildings, brick/steel terrain state, base-wall changes, HUD state and host-driven round restarts. Client gameplay processing/collision is disabled for replicas so simulation remains authoritative on the host.

## Controls

Host controls P1 normally. The remote player controls P2; on the client machine either the P1 or P2 action set is accepted to simplify two-PC keyboard/controller testing.

## Testing

### Same PC / loopback

1. Launch two game instances.
2. Instance A: choose `HOST ONLINE CO-OP`.
3. Instance B: leave the address as `127.0.0.1` and choose `JOIN ONLINE CO-OP`.
4. Verify A controls P1 and B controls P2.
5. Verify enemy movement, bullets, terrain destruction, drops, deaths and HUD remain consistent.
6. Finish a round and restart from the host; the client should rebuild from the authoritative round state.
7. Close one instance and verify the remaining peer returns to the title flow.

### LAN / internet

For LAN, enter the host's LAN IPv4 address and allow UDP `24567` through the host firewall. Direct internet hosting also requires UDP `24567` to reach the host (normally router port forwarding); a VPN/overlay network can avoid manual port forwarding.

## Known limitations / next work

- no client-side movement prediction yet; remote P2 visibly reflects network latency
- no matchmaking, relay or NAT traversal yet
- online Campaign remains disabled until spire-map choices and persistent RPG state are synchronized
- replicated VFX/audio are best-effort visuals; authoritative gameplay state is prioritized
- this branch still needs a two-instance Godot 4.5 runtime test before merging to `main`

The RPC layout was checked against the Godot 4.5 multiplayer API documentation. This environment does not contain the project's Godot 4.5 executable, so engine parse/runtime validation still needs to be performed on the development machine.

A later Steam release can replace the connection/lobby transport with Steam Networking while keeping the same host-authoritative gameplay model.
