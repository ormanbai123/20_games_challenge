package src

import rl "vendor:raylib"

import "core:mem"
import vmem "core:mem/virtual"

import "ldtk"

import "core:strings"
import "core:math/big"

import "core:fmt"

import "core:encoding/json"


import "base:intrinsics"

g_level_id := u8(0)

g_level_arena : vmem.Arena
g_level_allocator : mem.Allocator 

levels : []Level 

TILE_SIZE :: 32

LEVEL_TILES_X :: 20
LEVEL_TILES_Y :: 10 

LEVEL_WIDTH :: TILE_SIZE * LEVEL_TILES_X
LEVEL_HIGHT :: TILE_SIZE * LEVEL_TILES_Y


// Atlas offsets for Sprites
ATLAS_OFFSET__PLAYER_IDLE := rl.Vector2{0, 224}
ATLAS_OFFSET__PLAYER_RUN  := rl.Vector2{0, 256}

ATLAS_OFFSET__PLATFORM := rl.Vector2{192, 0}
ATLAS_OFFSET__DESTROYABLE_PLATFORM := rl.Vector2{192,32}
ATLAS_OFFSET__CHECKPOINT := rl.Vector2{192, 64}


generate_level_id :: proc () -> u8 {
    id := g_level_id
    g_level_id += 1
    return id
}

Tile :: struct {
    pos : rl.Vector2,
    src : rl.Vector2,
    not_empty : bool,
}

Room :: struct {
    pos                 : rl.Vector2, // World coordinates of top left corner of Room.

    checkpoint : Checkpoint,

    tile_map            : [LEVEL_TILES_X * LEVEL_TILES_Y]Tile, // Sprite map
    collision_map       : [LEVEL_TILES_X * LEVEL_TILES_Y]u8, // Collision map

    platforms           : []Platform, 

    reversers           : []Reverser,

    monsters            : []Monster,

    uuid                : u128,

    id_left, id_right, id_top, id_down : u128, // indices of neighbour rooms
}

get_room_centre :: proc (room : ^Room) -> rl.Vector2 {
    return {room.pos.x + LEVEL_WIDTH / 2, room.pos.y + LEVEL_HIGHT / 2} 
}

reset_room :: proc (r : ^Room) {
    for &p in r^.platforms {
        p.pos = p.start_pos
        p.velocity = p.initial_velocity

        // Reset one_way platform's settings
        p.started_moving = false

        reset_animation(&p.anim_data)
        p.destroyed = false
    }
    for &m in r^.monsters {
        // if m.accelerated {
        //     m.velocity = 0
        // }
        m.velocity, m.acceleration = m.initial_velocity, m.initial_acceleration
        m.pos = m.start_pos
    }
}

Level :: struct {
    name    : string,
    id      : u8,
    rooms   : []Room,

    current_room : u8,

    checkpoint : ^Checkpoint,
}

check_room_bounds :: proc (p : ^Player, room : ^Room) -> (bool, u8, rl.Vector2) {
    // Right
    if (p.pos.x + p.size.x / 2) > (room.pos.x + LEVEL_WIDTH) {
        return true, map_uuid_id[room.id_right], {room.pos.x + LEVEL_WIDTH + p.size.x / 4, p.pos.y}
    }   
    // Left 
    if (p.pos.x + p.size.x / 2) < (room.pos.x) {
        return true, map_uuid_id[room.id_left], {room.pos.x - p.size.x - (p.size.x / 4), p.pos.y}
    } 
    // Down
    if (p.pos.y + p.size.y / 2) > (room.pos.y + LEVEL_HIGHT) {
        return true, map_uuid_id[room.id_down], {p.pos.x, room.pos.y + LEVEL_HIGHT + (p.size.y / 4)}
    } 
    // Top 
    if (p.pos.y + p.size.y / 2) < (room.pos.y) {
        return true, map_uuid_id[room.id_top], {p.pos.x, room.pos.y - p.size.y - (p.size.y / 4)}
    } 

    return false, map_uuid_id[room.uuid], {}
}

map_uuid_id : map[u128]u8

uuid_to_id :: proc(uuid : string) -> u128 {
    temp_num : big.Int

    newstr, was_allocation := strings.remove_all(uuid, "-")

    big.int_atoi(&temp_num, newstr, 16)
    num, err := big.int_get_u128(&temp_num)

    // Free memory
    if was_allocation {
        delete(newstr)
    }
    delete(temp_num.digit)

    return num
}

get_bool_from_Value :: proc(val : json.Value) -> bool {
    #partial switch v in val {
        case json.Boolean: {
            return v
        }
    }

    return false
}

get_num_from_Value :: proc ($T: typeid, val : json.Value) -> T {
    #partial switch v in val {
        case json.Integer: {
            return T(v)
        }
        case json.Float: {
            return T(v)
        }
    }

    return T(-1)
}

get_vec_from_Value :: proc ($T: typeid, val : json.Value) -> [2]T {
    res : [2]T
    #partial switch v in val {
        case json.Array: {
            for field, i in v do res[i] = get_num_from_Value(T, field) 
        }
    }
    return res
}

load_level :: proc(filename : string){
    level := new(Level, g_level_allocator)
    level.id = generate_level_id()
    level.name = "Tutorial"

    if project, ok := ldtk.load_from_file(filename, context.temp_allocator).?; ok {
        level.rooms = make([]Room, len(project.levels), g_level_allocator)

        using level

        // Currently this is hardcoded
        checkpoint = &rooms[0].checkpoint
        checkpoint.activated = true

        for room, indx in project.levels {
            rooms[indx].uuid = uuid_to_id(room.iid)

            //rooms[indx].id = u8(indx)

            map_uuid_id[rooms[indx].uuid] = u8(indx)

            rooms[indx].pos = rl.Vector2{f32(room.world_x), f32(room.world_y)}

            for neighbour in room.neighbours {
                neigh_id := uuid_to_id(neighbour.level_iid)
    
                switch neighbour.dir {
                    case "w": {
                        rooms[indx].id_left = neigh_id 
                    }
                    case "e": {
                        rooms[indx].id_right = neigh_id 
                    }
                    case "n": {
                        rooms[indx].id_top = neigh_id 
                    }
                    case "s": {
                        rooms[indx].id_down = neigh_id 
                    }
                }
            }

            tile_indx : u32

            rooms[indx].platforms = make([]Platform, 4, g_level_allocator)
            rooms[indx].reversers = make([]Reverser, 3, g_level_allocator)
            rooms[indx].monsters  = make([]Monster, 4, g_level_allocator)

            for layer in room.layer_instances {
                switch layer.type {
                case .IntGrid: {
                    for val, i in layer.int_grid_csv {
                        rooms[indx].collision_map[i] = u8(val)
                    }
                }
                case .Entities: {
                    platform_indx := u8(0)
                    rev_indx := u8(0)
                    monster_indx := u8(0)
    
                    for entity in layer.entity_instances {
                        switch entity.identifier {
                            case "Platform": {
                                rooms[indx].platforms[platform_indx].pos = rooms[indx].pos + {f32(entity.px[0]), f32(entity.px[1])}
                                rooms[indx].platforms[platform_indx].size = {f32(entity.width), f32(entity.height)}
                                rooms[indx].platforms[platform_indx].start_pos = rooms[indx].pos + {f32(entity.px[0]), f32(entity.px[1])}

                                for field in entity.field_instances {
                                    switch field.identifier {
                                        case "velocity": {
                                            rooms[indx].platforms[platform_indx].velocity = get_vec_from_Value(f32, field.value)
                                            rooms[indx].platforms[platform_indx].initial_velocity = rooms[indx].platforms[platform_indx].velocity
                                        }
                                        case "end_pos": {
                                            rooms[indx].platforms[platform_indx].end_pos = rooms[indx].pos + get_vec_from_Value(f32, field.value)
                                        }
                                        case "platform_kind": {
                                            rooms[indx].platforms[platform_indx].kind = Platform_kind(get_num_from_Value(i16, field.value))
                                        }
                                        case "destroyable": {
                                            rooms[indx].platforms[platform_indx].destroyable = get_bool_from_Value(field.value)
                                        }
                                        case "is_one_way": {
                                            rooms[indx].platforms[platform_indx].is_one_way = get_bool_from_Value(field.value)
                                        }
                                    }
                                }
                                
                                // Animation data
                                rooms[indx].platforms[platform_indx].anim_data = {
                                    num_of_frames = 5,
                                    frame_timer = 0,
                                    current_frame = 0,
                                    frame_length = 0.05, // TODO Change this.
                                }

                                platform_indx += 1
                            }
                            case "Reverser": {
                                rooms[indx].reversers[rev_indx].pos = rooms[indx].pos + {f32(entity.px[0]), f32(entity.px[1])}
                                rooms[indx].reversers[rev_indx].size = {f32(entity.width), f32(entity.height)}
                                rev_indx += 1
                            }
                            case "Key": {
    
                            }
                            case "Checkpoint": {
                                // (Note) Current assumption is that each room will have only ONE Checkpoint
                                rooms[indx].checkpoint.valid = true
                                rooms[indx].checkpoint.pos = rooms[indx].pos + {f32(entity.px[0]), f32(entity.px[1])}
                                rooms[indx].checkpoint.size = {f32(entity.width), f32(entity.height)}
                                rooms[indx].checkpoint.room_uuid = rooms[indx].uuid
                            }
                            case "Monster": {
                                rooms[indx].monsters[monster_indx].pos = rooms[indx].pos + {f32(entity.px[0]), f32(entity.px[1])}
                                rooms[indx].monsters[monster_indx].start_pos = rooms[indx].pos + {f32(entity.px[0]), f32(entity.px[1])}
                                rooms[indx].monsters[monster_indx].size =  {f32(entity.width), f32(entity.height)}

                                for field in entity.field_instances {
                                    switch field.identifier {
                                        case "velocity": {
                                            rooms[indx].monsters[monster_indx].velocity = get_vec_from_Value(f32, field.value)
                                            rooms[indx].monsters[monster_indx].initial_velocity = rooms[indx].monsters[monster_indx].velocity
                                        }
                                        case "acceleration": {
                                            rooms[indx].monsters[monster_indx].acceleration = get_vec_from_Value(f32, field.value)
                                            rooms[indx].monsters[monster_indx].initial_acceleration = rooms[indx].monsters[monster_indx].acceleration
                                        }
                                        case "accelerated": {
                                            rooms[indx].monsters[monster_indx].accelerated = get_bool_from_Value(field.value)
                                        }
                                        case "is_vertical": {
                                            rooms[indx].monsters[monster_indx].is_vertical = get_bool_from_Value(field.value)
                                        }
                                        case "end_pos": {
                                            rooms[indx].monsters[monster_indx].end_pos = rooms[indx].pos + get_vec_from_Value(f32, field.value)
                                        }
                                    }
                                }

                                monster_indx += 1
                            }
                        }
                    }
                }
                case .Tiles: {
                    for tile in layer.grid_tiles {
                        rooms[indx].tile_map[tile_indx].pos = rooms[indx].pos + {f32(tile.px[0]), f32(tile.px[1])}
                        rooms[indx].tile_map[tile_indx].src = {f32(tile.src[0]), f32(tile.src[1])}
                        rooms[indx].tile_map[tile_indx].not_empty = true
    
                        tile_indx += 1
                    }
                }
                case .AutoLayer: {
                        for tile in layer.auto_layer_tiles {
                            rooms[indx].tile_map[tile_indx].pos = rooms[indx].pos + {f32(tile.px[0]), f32(tile.px[1])}
                            rooms[indx].tile_map[tile_indx].src = {f32(tile.src[0]), f32(tile.src[1])}
                            rooms[indx].tile_map[tile_indx].not_empty = true
    
                            tile_indx += 1
                        }
                    }
                }
            }
        }
    }

    levels[level.id] = level^

    // Free temporary arena
    free_all(context.temp_allocator)
}

unload_level :: proc() {

}