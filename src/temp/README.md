# Cruise: Temporary Storage

A  thread-safe temporary storage system for Nim with automatic expiration, event system, and type erasure.
Provided by Cruise in case you want to do some global access shenaningan.

## Features

- **Type Erasure** - Store any type safely with compile-time type checking
- **Thread-Safe** - Lock-based synchronization for concurrent access
- **Auto-Expiration (TTL)** - Set time-to-live on any entry
- **Event System** - React to add, delete, expire, and clear events
- **Namespaces** - Organize data hierarchically with minimal performance cost
- **Async Cleanup** - Background task for automatic expired entry removal
- **JSON Serialization** - Save/load storage state to disk
- **Zero Dependencies** - Only uses Nim's standard library

### Basic Usage

```nim
import temporary_storage
import std/[times, options]

# Create a new storage
var ts = newTempStorage()

# Add values
ts.addVar("username", "alice")
ts.addVar("score", 9000)
ts.addVar("position", (x: 10.0, y: 20.0))

# Retrieve values
let username = ts.getVar("username", "")
let score = ts.getVar("score", 0)

# Check existence
if ts.hasVar("username"):
  echo "User is logged in"

# Delete a value
ts.delVar("score")
```

### With Auto-Expiration (TTL)

```nim
# Add a temporary value that expires in 5 seconds
ts.addVar("speed_boost", 2.0, ttl = some(initDuration(seconds = 5)))

# After 5 seconds, the value is automatically removed
sleep(6000)
echo ts.hasVar("speed_boost")  # false
```

### Using Namespaces

```nim
# Organize data by category
ts.addVar("health", 100, ns = "player1")
ts.addVar("health", 80, ns = "player2")
ts.addVar("quest_progress", 50, ns = "player1")

# Retrieve from specific namespace
let p1Health = ts.getVar("health", 0, ns = "player1")  # 100
let p2Health = ts.getVar("health", 0, ns = "player2")  # 80

# List all variables in a namespace
echo ts.listVars("player1")  # @["health", "quest_progress"]

# Clear entire namespace
ts.clear("player1")
```

### Event System

```nim
# React to events
ts.on(ekAddKey) do (key: string, value: pointer):
  echo "Added: ", key

ts.on(ekExpire) do (key: string, value: pointer):
  echo "Expired: ", key

ts.on(ekDeleteKey) do (key: string, value: pointer):
  echo "Deleted: ", key

# Add a value with TTL - triggers both add and expire events
ts.addVar("temp_buff", true, ttl = some(initDuration(seconds = 3)))
```

### Auto-Cleanup

```nim
# Start automatic cleanup every 10 seconds
ts.startAutoCleanup(initDuration(seconds = 10))

# ... your application logic ...

# Stop cleanup when shutting down
ts.stopAutoCleanup()
```

### Save/Load

```nim
# Save storage to JSON file
ts.saveToFile("game_state.json")

# Note: Full deserialization not yet implemented
# Currently saves metadata and TTL information
```

## Warning

Often abusing this kind of KV store leads bad performances. Use it just for global access and logics in your projet, not as the main piece.