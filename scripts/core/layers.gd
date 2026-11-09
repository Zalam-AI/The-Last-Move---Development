class_name Layers
## Central physics layer bit assignments. Keeping these in one place avoids the classic
## "everything collides with everything" bug that makes physics-based games feel mushy.

const WORLD := 1 << 0          # 1  static architecture
const FURNITURE := 1 << 1      # 2  grabbable rigid bodies
const PLAYER := 1 << 2         # 4  player characters
const INTERACT := 1 << 3       # 8  interactable volumes / pickups
const DOOR := 1 << 4           # 16 doors
const TRIGGER := 1 << 5        # 32 mission triggers, truck zone, rooms
const CREATURE := 1 << 6       # 64 supernatural agents

const PLAYER_MASK := WORLD | FURNITURE | DOOR | CREATURE
const FURNITURE_MASK := WORLD | FURNITURE | PLAYER | DOOR | CREATURE
const CREATURE_MASK := WORLD | FURNITURE | PLAYER | DOOR
