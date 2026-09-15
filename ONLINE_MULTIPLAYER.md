# Online Multiplayer (ENet)

This branch introduces the network session foundation for 2-player online co-op while preserving the existing local 2-player modes.

## Current implementation

- Godot 4 `ENetMultiplayerPeer`
- Host/client connection flow on the title screen
- Default UDP port: `24567`
- Maximum peers: 2
- Host waits for the second player before entering online arcade
- Client enters online arcade only after `connected_to_server`
- Network role/address/port/peer metadata stored in `GameState`
- Existing single-player and local 2-player buttons explicitly reset any network peer
- Connection failure/server disconnect restores the title-screen controls cleanly

## Architecture direction

Online play should be **host authoritative**:

1. Host owns enemy spawning, AI, damage, drops, score, lives and win/loss state.
2. P1 input is produced by host; P2 input is produced by client and submitted to host.
3. Host broadcasts authoritative player/enemy snapshots with unreliable ordered traffic where appropriate.
4. Discrete gameplay events (spawn, death, pickup, battle result, scene transition) use reliable RPCs.
5. Client-side interpolation/prediction should be used for movement only; game-rule decisions remain on the host.

## Next synchronization pass

The session layer is intentionally separated from simulation changes. Before this branch is merged to `main`, the following battle synchronization should be completed and tested:

- player ownership and P2 input RPC
- authoritative player position/health sync
- enemy spawn IDs and transform snapshots
- bullet spawn/fire replication
- authoritative damage/death handling
- pickup and building replication
- shared restart/disconnect flow
- campaign-map choice/state synchronization if online campaign is enabled later

The first online mode is intentionally **Arcade only**. Campaign remains local until map choices and persistent RPG state are synchronized.

## Connectivity

LAN/VPN users can enter the host machine's reachable IPv4 address. Direct internet hosting requires UDP `24567` to be reachable (typically by router port-forwarding) unless a VPN/overlay network is used.

A later Steam release can replace the transport/lobby layer with Steam Networking while preserving the host-authoritative gameplay synchronization model.
