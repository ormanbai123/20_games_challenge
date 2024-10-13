package src

import rl "vendor:raylib"

import "core:mem"
import vmem "core:mem/virtual"

import "ldtk"

import "core:strings"
import "core:math/big"

import "core:fmt"

g_level_id := u8(0)

g_level_arena : vmem.Arena
g_level_allocator : mem.Allocator 

levels : []Level 

TILE_SIZE :: 32

LEVEL_TILES_X :: 20
LEVEL_TILES_Y :: 10 

LEVEL_WIDTH :: TILE_SIZE * LEVEL_TILES_X
LEVEL_HIGHT :: TILE_SIZE * LEVEL_TILES_Y


generate_level_id :: proc () -> u8 {
    id := g_level_id
    g_level_id += 1
    return id
}

Room :: struct {
    pos                 : rl.Vector2, // World coordinates of top left corner of Room.

    player_start_pos    : rl.Vector2, 
    camera_pos          : rl.Vector2,

    tile_map            : [LEVEL_TILES_X * LEVEL_TILES_Y]u8, // Sprite map
    colliders           : []Collider,

    platforms           : []Platform, 

    reversers           : []Reverser,

    monsters            : []Monster,

    id                  : u8,
    id_left, id_right, id_top, id_down : u8, // indices of neighbour rooms
}

reset_room :: proc (r : ^Room) {
    for &p in r^.platforms {
        p.pos = p.start_pos
    }
    for &m in r^.monsters {
        m.velocity = 0
        m.pos = m.end_pos
    }
}

Level :: struct {
    name    : string,
    id      : u8,
    rooms   : []Room, //map[u128]Room,

    current_room : u8,

    checkpoint_pos      : rl.Vector2,
    checkpoint_room     : u8, // indx of room where checkpoint is
}

check_room_bounds :: proc (p : ^Player, room : ^Room) -> (bool, u8, rl.Vector2) {
    // Right
    if (p.pos.x + p.size.x / 2) > (room.pos.x + LEVEL_WIDTH) {
        return true, room.id_right, {room.pos.x + LEVEL_WIDTH + p.size.x / 4, p.pos.y}
    }   
    // Left 
    if (p.pos.x + p.size.x / 2) < (room.pos.x) {
        return true, room.id_left, {room.pos.x - p.size.x - (p.size.x / 4), p.pos.y}
    } 
    // Down
    if (p.pos.y + p.size.y / 2) > (room.pos.y + LEVEL_HIGHT) {
        return true, room.id_down, {p.pos.x, room.pos.y + LEVEL_HIGHT + (p.size.y / 4)}
    } 
    // Top 
    if (p.pos.y + p.size.y / 2) < (room.pos.y) {
        return true, room.id_top, {p.pos.x, room.pos.y - p.size.y - (p.size.y / 4)}
    } 

    return false, room.id, {}
}

// Call these "create_level#" functions once!
create_level1 :: proc () {
    level := new(Level, g_level_allocator)
    level.id = generate_level_id()
    level.name = "Tutorial"

    n_rooms := 18
    level.rooms = make([]Room, n_rooms, g_level_allocator)

    using level

    // Zeroth room 
    rooms[0].pos = {0,0}
    rooms[0].player_start_pos = {64,224}
    rooms[0].camera_pos = {rooms[0].pos.x + LEVEL_WIDTH / 2, rooms[0].pos.y + LEVEL_HIGHT / 2} 
    rooms[0].tile_map = {
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,
						1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,
						1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,1,1,1,1,1,1,1
    } 

    rooms[0].id = 0
    rooms[0].id_right = 1

    // First room
    rooms[1].pos = {640, 0}
    rooms[1].player_start_pos = {}
    rooms[1].camera_pos = {rooms[1].pos.x + LEVEL_WIDTH / 2, rooms[1].pos.y + LEVEL_HIGHT / 2}
    rooms[1].tile_map = {
        1,1,1,1,1,2,2,2,2,2,2,1,1,1,1,2,2,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,
						0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,
						1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,
						2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    }

    // Platforms
    rooms[1].platforms = make([]Platform, 1, g_level_allocator)
    rooms[1].platforms[0] = {
        start_pos = {rooms[1].pos.x + 160, rooms[1].pos.y + 160},
        end_pos = {rooms[1].pos.x + 352, rooms[1].pos.y + 160},
        pos = {rooms[1].pos.x + 96, rooms[1].pos.y + 160},
        size = {TILE_SIZE * 3, TILE_SIZE / 2},
        velocity = {150, 0},
        kind = .HORIZONTAL
    }

    rooms[1].id = 1
    rooms[1].id_left = 0
    rooms[1].id_right = 2

    // Second room
    rooms[2].pos = {1280, 0}
    rooms[2].player_start_pos = {}
    rooms[2].camera_pos = {rooms[2].pos.x + LEVEL_WIDTH / 2, rooms[2].pos.y + LEVEL_HIGHT / 2}
    rooms[2].tile_map = {
        1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,
						1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
						1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
						1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    }

    rooms[2].id = 2
    rooms[2].id_left = 1
    rooms[2].id_top = 4
    rooms[2].id_right = 3

    //  Third room
    rooms[3].pos = {1920, 0}
    rooms[3].player_start_pos = {}
    rooms[3].camera_pos = {rooms[3].pos.x + LEVEL_WIDTH / 2, rooms[3].pos.y + LEVEL_HIGHT / 2}
    rooms[3].tile_map = {
        1,1,1,2,2,2,2,2,2,2,2,2,1,1,1,2,2,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,1,1,1,1,0,
						0,0,0,0,2,2,2,2,2,2,1,1,1,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
						1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,0,0,0,0,0,0
    }

    rooms[3].id = 3
    rooms[3].id_left = 2
    rooms[3].id_right = 8
    
    // Fourth room
    rooms[4].pos = {1280, -320}
    rooms[4].player_start_pos = {}
    rooms[4].camera_pos = {rooms[4].pos.x + LEVEL_WIDTH / 2, rooms[4].pos.y + LEVEL_HIGHT / 2}
    rooms[4].tile_map = {
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,
						0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,1,1,1,1,
						1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,
						1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1,1
    }
    rooms[4].id = 4
    rooms[4].id_down = 2
    rooms[4].id_left = 7
    rooms[4].id_right = 5
    
    // Fifth room
    rooms[5].pos = {1920, -320}
    rooms[5].player_start_pos = {}
    rooms[5].camera_pos = {rooms[5].pos.x + LEVEL_WIDTH / 2, rooms[5].pos.y + LEVEL_HIGHT / 2}
    rooms[5].tile_map = {
        1,1,1,2,2,2,2,2,1,1,1,1,2,2,2,2,2,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1
    }
    // Reversers
    rooms[5].reversers = make([]Reverser, 1, g_level_allocator)
    rooms[5].reversers[0].pos = {rooms[5].pos.x + 0, rooms[5].pos.y + 224}
    rooms[5].reversers[0].size = {576, TILE_SIZE / 4}

    rooms[5].id = 5 
    rooms[5].id_right = 6
    rooms[5].id_left = 4


    // Sixth room
    rooms[6].pos = {2560, -320}
    rooms[6].player_start_pos = {}
    rooms[6].camera_pos = {rooms[6].pos.x + LEVEL_WIDTH / 2, rooms[6].pos.y + LEVEL_HIGHT / 2}
    rooms[6].tile_map = { 
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
						1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    }
    rooms[6].reversers = make([]Reverser, 1, g_level_allocator)
    rooms[6].reversers[0].pos = {rooms[6].pos.x, rooms[6].pos.y + 32}
    rooms[6].reversers[0].size = {608, TILE_SIZE / 4}

    rooms[6].monsters = make([]Monster, 1, g_level_allocator)
    rooms[6].monsters[0] = {
        end_pos = {rooms[6].pos.x + 544, rooms[6].pos.y + 160},
        start_pos = {rooms[6].pos.x, rooms[6].pos.y + 160},
        pos = {rooms[6].pos.x + 300, rooms[6].pos.y + 160}, 
        size = {TILE_SIZE * 2, TILE_SIZE * 2},
        acceleration = {600, 0} 
    }

    rooms[6].id = 6
    rooms[6].id_left = 5


    // Seventh room
    rooms[7].pos = {640, -320}
    rooms[7].player_start_pos = {}
    rooms[7].camera_pos = {rooms[7].pos.x + LEVEL_WIDTH / 2, rooms[7].pos.y + LEVEL_HIGHT / 2}
    rooms[7].tile_map = {
        2,2,2,2,2,2,2,2,2,2,2,2,1,1,2,2,2,2,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,0,0,0,0,2,2,0,0,0,0,0,1,1,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,1,1,2,2,2,2,2,2,2,1,1,1,2,2,2,2,2,2,2,2
    }

    rooms[7].platforms = make([]Platform, 1, g_level_allocator)
    rooms[7].platforms[0] = {
        is_one_way = true,
        size = {TILE_SIZE * 3, TILE_SIZE / 2},
        start_pos = {rooms[7].pos.x + 480, rooms[7].pos.y + 160},
        end_pos = {rooms[7].pos.x, rooms[7].pos.y + 160},
        pos = {rooms[7].pos.x + 480, rooms[7].pos.y + 160},
        velocity = {-80, 0},
        kind = Platform_kind.HORIZONTAL
    }

    rooms[7].id = 7
    rooms[7].id_right = 4
    rooms[7].id_left = 9

    
    // Eigth room
    rooms[8].pos = {2560, 0}
    rooms[8].player_start_pos = {}
    rooms[8].camera_pos = {rooms[8].pos.x + LEVEL_WIDTH / 2, rooms[8].pos.y + LEVEL_HIGHT / 2}
    rooms[8].tile_map = {
        2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1
    }

    rooms[8].platforms = make([]Platform, 3, g_level_allocator)
    rooms[8].platforms[0] = {
        size = {TILE_SIZE * 3, TILE_SIZE / 2},
        start_pos = {rooms[8].pos.x + 96, rooms[8].pos.y + 32},
        end_pos = {rooms[8].pos.x + 96, rooms[8].pos.y + 224},
        pos = {rooms[8].pos.x + 96, rooms[8].pos.y + 224},
        velocity = {0, 100},
        kind = Platform_kind.VERTICAL
    }
    rooms[8].platforms[1] = {
        size = {TILE_SIZE * 3, TILE_SIZE / 2},
        start_pos = {rooms[8].pos.x + 288, rooms[8].pos.y + 64},
        end_pos = {rooms[8].pos.x + 288, rooms[8].pos.y + 256},
        pos = {rooms[8].pos.x + 288, rooms[8].pos.y + 64},
        velocity = {0, 100},
        kind = Platform_kind.VERTICAL
    }
    rooms[8].platforms[2] = {
        size = {TILE_SIZE * 3, TILE_SIZE / 2},
        start_pos = {rooms[8].pos.x + 448, rooms[8].pos.y + 64},
        end_pos = {rooms[8].pos.x + 448, rooms[8].pos.y + 224},
        pos = {rooms[8].pos.x + 448, rooms[8].pos.y + 224},
        velocity = {0, 100},
        kind = Platform_kind.VERTICAL
    }

    rooms[8].id = 8
    rooms[8].id_right = 11
    rooms[8].id_left = 3


    // 11'th room
    rooms[11].pos = {3200, 0}
    rooms[11].player_start_pos = {}
    rooms[11].camera_pos = {rooms[11].pos.x + LEVEL_WIDTH / 2, rooms[11].pos.y + LEVEL_HIGHT / 2}
    rooms[11].tile_map = {
        0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,2,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,1,1,1,1,1,
						1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    }
    rooms[11].id = 11
    rooms[11].id_top = 12
    rooms[11].id_left = 8

    // 12'th room
    rooms[12].pos = {3200, -320}
    rooms[12].player_start_pos = {}
    rooms[12].camera_pos = {rooms[12].pos.x + LEVEL_WIDTH / 2, rooms[12].pos.y + LEVEL_HIGHT / 2}
    rooms[12].tile_map = {
        1,0,0,1,0,0,2,0,0,0,0,0,0,0,0,2,1,0,0,0,1,0,0,1,0,0,0,2,0,0,0,0,0,0,0,
						2,1,0,0,0,1,0,0,1,0,0,0,2,0,0,0,0,0,0,0,2,1,1,0,0,0,0,0,1,0,0,0,2,0,0,
						0,0,0,0,0,0,2,1,0,0,0,0,0,1,0,0,0,0,2,0,0,0,0,0,0,0,2,1,0,0,0,0,0,1,0,
						0,0,0,0,2,0,0,0,0,0,0,2,1,0,0,0,0,0,1,0,0,0,0,0,2,0,0,0,0,0,0,2,1,1,0,
						1,1,1,1,0,0,0,0,0,0,2,0,0,0,0,0,0,2,1,0,1,1,1,1,0,0,0,0,0,0,2,0,0,0,0,
						0,0,2,1,0,1,1,1,1,0,0,0,0,0,0,2,0,0,0,0,0,0,2,1,0
    }
    rooms[12].id = 12
    rooms[12].id_down = 11
    rooms[12].id_top = 13

    // 13'th room
    rooms[13].pos = {3200, -640}
    rooms[13].player_start_pos = {}
    rooms[13].camera_pos = {rooms[13].pos.x + LEVEL_WIDTH / 2, rooms[13].pos.y + LEVEL_HIGHT / 2}
    rooms[13].tile_map = {
        1,1,1,1,1,1,1,1,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,0,0,0,
						0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
						0,0,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,0,0,0,0,0,0,1,0,0,1,2,
						0,0,0,0,0,0,0,2,1,0,0,0,0,0,0,1,0,0,1,0,2,0,0,0,0,0,0,0,2,1,1,0,0,0,0,
						1,0,0,1,0,2,0,0,0,0,0,0,0,0,2,1,0,0,0,0,1,0,0,1,0,0,2,0,0,0,0,0,0,0,2,
						1,1,0,0,0,1,0,0,1,0,0,2,0,0,0,0,0,0,0,0,2,1,0,0,0
    }
    rooms[13].id = 13
    rooms[13].id_down = 12
    rooms[13].id_left = 14

    level.checkpoint_pos = rooms[0].player_start_pos
    level.checkpoint_room = 0
    levels[id] = level^
} 

//uuid_to_id : map[u128]u8

uuid_to_id :: proc(uuid : string) -> u128 {
    temp_num : big.Int

    newstr, was_allocation := strings.remove_all(uuid, "-")

    big.int_atoi(&temp_num, newstr, 16)
    num, err := big.int_get_u128(&temp_num)

    return num
}

load_level :: proc(filename : string){
    // level := new(Level, g_level_allocator)
    // level.id = generate_level_id()
    // level.name = "Tutorial"

    // if project, ok := ldtk.load_from_file(filename).?; ok {
    //     level.rooms = make(map[u128]Room, len(project.levels), g_level_allocator)

    //     using level

    //     for room in project.levels {
    //         this_room_id := uuid_to_id(room.iid)

    //         for neighbour in room.neighbours {
    //             neigh_id := uuid_to_id(neighbour.level_iid)
    
    //             switch neighbour.dir {
    //                 case "w": {
    //                     rooms[this_room_id].id_left = neigh_id 
    //                 }
    //                 case "e": {
    //                     rooms[this_room_id].id_right = neigh_id 
    //                 }
    //                 case "n": {
    //                     rooms[this_room_id].id_top = neigh_id 
    //                 }
    //                 case "s": {
    //                     rooms[this_room_id].id_down = neigh_id 
    //                 }
    //             }
    //         }


    //     }
    // }

    // levels[level.id] = level^
}

unload_level :: proc() {

}