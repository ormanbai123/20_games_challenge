package src

import "core:fmt"
import mat "core:math"

import rl "vendor:raylib"

import "core:slice"

import "core:mem"
import vmem "core:mem/virtual"

camera : rl.Camera2D

AABB :: struct {
    pos         : rl.Vector2, 
    size        : rl.Vector2, // width, height
    velocity    : rl.Vector2, 
}

Entity_kind :: enum {
    NONE = 0, WALL, SPIKE, PLATFORM, 
}

Collider :: struct {
    pos     : rl.Vector2,
    size    : rl.Vector2,
    kind    : Entity_kind,
}

Direction :: enum {
    LEFT, RIGHT
}


Player :: struct {
    pos : rl.Vector2,
    size : rl.Vector2,

    direction : Direction,

    velocity : rl.Vector2,
    acceleration : rl.Vector2,

    on_wall : bool,
    is_dead : bool,
}

Platform_kind :: enum {
    HORIZONTAL, VERTICAL
}

Platform :: struct {
    start_pos : rl.Vector2,
    end_pos   : rl.Vector2,
    pos       : rl.Vector2,

    size : rl.Vector2,
    
    kind : Platform_kind,

    destroyable : bool,
    destroyed : bool,

    is_one_way : bool, 

    velocity : rl.Vector2,
}

Reverser :: struct {
    pos : rl.Vector2,
    size : rl.Vector2,
}

Monster :: struct {
    pos, start_pos, end_pos : rl.Vector2,
    size : rl.Vector2,
    velocity, acceleration : rl.Vector2,
}

// TODO
// Sometimes collision does not work (vertically)
// Probably the issue with the change of gravity
// or with the order of statements in the main loop
ray_vs_rect :: proc (ray_origin, ray_dir : rl.Vector2, rect : AABB) -> (bool, f32, rl.Vector2, rl.Vector2) {
    contact_point, contact_normal : rl.Vector2

    t_near, t_far : rl.Vector2

    inv_dir := 1.0 / ray_dir 

    t_near = (rect.pos - ray_origin) * inv_dir
    t_far  = (rect.pos + rect.size - ray_origin) * inv_dir

    if mat.is_nan_f32(t_far.y) || mat.is_nan_f32(t_far.x) {return false, 1.0, {}, {}}
    if mat.is_nan_f32(t_near.y) || mat.is_nan_f32(t_near.x) {return false, 1.0, {}, {}}
    
    // sort near and far points
    if t_near.x > t_far.x { t_near.x, t_far.x = t_far.x, t_near.x}
    if t_near.y > t_far.y { t_near.y, t_far.y = t_far.y, t_near.y}

    // early rejection
    if t_near.x > t_far.y || t_near.y > t_far.x {return false, 1.0, {}, {}}

    t_hit_near := max(t_near.x, t_near.y)
    t_hit_far  := min(t_far.x, t_far.y)

    // Check if collision time between [0,1]
    if t_hit_near < 0.0 || t_hit_near >= 1.0 {
        return false, 1.0, {}, {}
    }

    if t_hit_far < 0 {return false, 1.0, {}, {}}

    contact_point = ray_origin + t_hit_near * ray_dir

    if t_near.x > t_near.y {
        contact_normal = ray_dir.x < 0 ? {1,0} : {-1,0}  
    } else if t_near.x < t_near.y {
        contact_normal = ray_dir.y < 0 ? {0,1} : {0,-1}
    }

    return true, t_hit_near, contact_point, contact_normal
}

rect_vs_rect :: proc(r1, r2 : AABB, dt : f32) -> (bool, f32, rl.Vector2, rl.Vector2) {
    if (abs(r1.velocity.x) < mat.F32_EPSILON) && (abs(r1.velocity.y) < mat.F32_EPSILON) 
    {
        return false, 1.0, {},{} 
    }

    expanded_target : AABB
    expanded_target.pos     = r2.pos - r1.size / 2
    expanded_target.size    = r2.size + r1.size

    ray_origin := r1.pos + r1.size / 2
    ray_dir    := r1.velocity * dt


    rect_max := expanded_target.pos + expanded_target.size
    rect_min := expanded_target.pos
    inside_box := (ray_origin.x > rect_min.x) && (ray_origin.x < rect_max.x) && 
                    (ray_origin.y > rect_min.y) && (ray_origin.y < rect_max.y) 

    if inside_box { 
        ray_dir = -ray_dir
    }

    hit, time, point, normal := ray_vs_rect(ray_origin, ray_dir, expanded_target)

    if inside_box {
        time *= -1.0
        normal = -normal
    }

    return hit, time, point, normal
    //return ray_vs_rect(ray_origin, ray_dir, expanded_target)
}

GRAVITY := f32(800)
DEBUG_ON := false

Sort_pair :: struct {
    indx           : u32,
    bb             : AABB,
    collision_time : f32,
}

collision_sort_func :: proc (a,b : Sort_pair) -> bool {
    return a.collision_time < b.collision_time
}

main :: proc () { 

    //---------------------------------Track allocations-----------------------------------------------
    // Uncomment to check for memory leaks

    // when ODIN_DEBUG {
    //     track: mem.Tracking_Allocator
	// 	mem.tracking_allocator_init(&track, context.allocator)
	// 	context.allocator = mem.tracking_allocator(&track)

	// 	defer {
	// 		if len(track.allocation_map) > 0 {
	// 			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
	// 			for _, entry in track.allocation_map {
	// 				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
	// 			}
	// 		}
	// 		if len(track.bad_free_array) > 0 {
	// 			fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
	// 			for entry in track.bad_free_array {
	// 				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
	// 			}
	// 		}
	// 		mem.tracking_allocator_destroy(&track)
	// 	}
    // }
//---------------------------------------------------------------------------------------------------------

    // Allocation stuff
    g_level_allocator = vmem.arena_allocator(&g_level_arena)
    defer vmem.arena_destroy(&g_level_arena)
    levels = make([]Level, 2, g_level_allocator) // Create levels array

    // Create level 1
    create_level1()
    current_level := levels[0]


    player := Player{
        pos = current_level.rooms[current_level.current_room].player_start_pos,
        size = {TILE_SIZE * 0.60, TILE_SIZE},
        direction = .RIGHT, acceleration = {0, GRAVITY}
    }

    rl.InitWindow(1280, 640, "Demo")
    defer rl.CloseWindow()

    rl.SetTargetFPS(144)

    camera = {
        {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)}, // Camera position in Screen space
        current_level.rooms[current_level.current_room].camera_pos,    // Camera position in World  space
        0.0,                                                           // Rotation
        2.0                                                            // Zoom
    }

    atlas := rl.LoadTexture("assets/atlas.png")
    defer rl.UnloadTexture(atlas)

    // background_tex := rl.LoadTexture("assets/background.png")
    // defer rl.UnloadTexture(background_tex)

    // background_pos_x := f32(0)


    accumulated_time : f32

    // Game logic is run in 60HZ
    DT :: 1.0 / 60.0

    for !rl.WindowShouldClose() {

        accumulated_time += rl.GetFrameTime()

        for accumulated_time >= DT {
            if rl.IsKeyDown(.D) {
                if player.direction == .LEFT {
                    player.direction = .RIGHT
                    player.velocity.x = 0
                } else {
                    player.velocity.x = 250
                }
            } else if rl.IsKeyDown(.A) {
                if player.direction == .RIGHT {
                    player.direction = .LEFT
                    player.velocity.x = 0
                } else {
                    player.velocity.x = -250
                }
            } else {
                player.velocity.x = 0
            }
    
    
            if rl.IsKeyDown(.SPACE) && player.on_wall {
                player.acceleration.y = -player.acceleration.y 
                player.on_wall = false
            }
            if rl.IsKeyDown(.F1) {
                DEBUG_ON = !DEBUG_ON
            }
    
            player.velocity += player.acceleration * DT
    
            player.on_wall = false
    
            
            // Collision with PLATFORMS
            for platform in current_level.rooms[current_level.current_room].platforms {
    
                // Subtract platform's velocity from player's to get relative velocity
                // This way, the platform appears to be stationary
                relative_velocity := player.velocity - platform.velocity
    
                player_aabb := AABB{player.pos, player.size, relative_velocity}
                plat_aabb := AABB{platform.pos, platform.size, 0}
                // Do the collision
                collided, collision_time, _, normal := rect_vs_rect(player_aabb, plat_aabb, DT)
                // Handle the collision 
                relative_velocity += normal * rl.Vector2{abs(relative_velocity.x), abs(relative_velocity.y)} * (1-collision_time)

                player.velocity = relative_velocity + platform.velocity
    
                if collided && (abs(normal.y) > mat.F32_EPSILON) {
                    if platform.kind == .VERTICAL {
                        // player.velocity.y = platform.velocity.y

                        player.velocity += normal * {0, 0.001} // Add epsilon
                    } else {
                        player.velocity += platform.velocity
                    }
    
                    player.on_wall = true
                } 
            }

            // Sort collision rects
            collision_arr : [dynamic]Sort_pair
    
            for i := 0; i < LEVEL_TILES_Y; i += 1 {
                for j := 0; j < LEVEL_TILES_X; j += 1 {
                    tile_indx := u32(i * LEVEL_TILES_X + j)
                    if current_level.rooms[current_level.current_room].tile_map[tile_indx] > 0 {
                        starting_pos := current_level.rooms[current_level.current_room].pos
    
                        player_aabb := AABB{player.pos, player.size, player.velocity}
    
                        wall_aabb := AABB{{starting_pos.x + f32(j * TILE_SIZE) + TILE_SIZE * 0.1,
                             starting_pos.y + f32(i * TILE_SIZE)},
                         {TILE_SIZE * 0.8, TILE_SIZE}, 0}
    
                         // Do the collision
                        collided, collision_time, _, _ := rect_vs_rect(player_aabb, wall_aabb, DT)
                        
                        if collided {
                            append(&collision_arr, Sort_pair{tile_indx, wall_aabb, collision_time})
                        }
                    } 
                }
            }
    
            // Do the actual sorting
            slice.sort_by(collision_arr[:], collision_sort_func)
            
            for i in collision_arr {
                starting_pos := current_level.rooms[current_level.current_room].pos
    
                player_aabb := AABB{player.pos, player.size, player.velocity}
    
                    // Do the collision
                collided, collision_time, _, normal := rect_vs_rect(player_aabb, i.bb, DT)
    
                if collided {
                    // Handle the collision 
                    player.velocity += normal * rl.Vector2{abs(player.velocity.x), abs(player.velocity.y)} * (1-collision_time)
                    
                    // TODO CHANGE THIS?
                    //player.velocity += normal * rl.Vector2{0, 0.1}
    
                    player.on_wall = (abs(normal.y) > mat.F32_EPSILON)
                    
                    // Check if collided with killable obstacles
                    if Entity_kind(current_level.rooms[current_level.current_room].tile_map[i.indx]) == .SPIKE {
                        player.is_dead = true
                    }
                }
            }
    
            // Collision with REVERSER
            for reverser in current_level.rooms[current_level.current_room].reversers {
                player_aabb := AABB{player.pos, player.size, player.velocity}
    
                _aabb := AABB{ reverser.pos, reverser.size, 0}
    
                  // Do the collision
                  collided, collision_time, _, normal := rect_vs_rect(player_aabb, _aabb, DT)
    
                  if collided {
                      // Handle the collision 
                      player.velocity += normal * rl.Vector2{abs(player.velocity.x), abs(player.velocity.y)} * (1-collision_time)
                      
                      // Reverse gravity and player's direction
                      player.velocity = -player.velocity
                      player.acceleration = -player.acceleration
                  }
            }

            // Collision with monsters
            for monster in current_level.rooms[current_level.current_room].monsters {
                relative_velocity := player.velocity - monster.velocity
    
                player_aabb := AABB{player.pos, player.size, relative_velocity}
                _aabb := AABB{monster.pos, monster.size, 0}
                // Do the collision
                collided, collision_time, _, normal := rect_vs_rect(player_aabb, _aabb, DT)
                // Handle the collision 
                relative_velocity += normal * rl.Vector2{abs(relative_velocity.x), abs(relative_velocity.y)} * (1-collision_time)
    
                if collided {
                    player.is_dead = true
                } 
            }
    
            // Move platforms
            for &platform in current_level.rooms[current_level.current_room].platforms {
                platform.pos += platform.velocity * DT
                
                left_pos, right_pos := platform.start_pos, platform.end_pos
                if left_pos.x >= right_pos.x {
                    left_pos, right_pos = right_pos, left_pos
                }
                down_pos, up_pos := platform.start_pos, platform.end_pos
                if down_pos.y <= up_pos.y {
                    down_pos, up_pos = up_pos, down_pos
                }

                if platform.kind == .HORIZONTAL {
                    if ((platform.pos.x > right_pos.x) && platform.velocity.x > 0) ||
                        ((platform.pos.x < left_pos.x) && platform.velocity.x < 0) 
                    {
                        if platform.is_one_way {
                            platform.velocity = 0
                        } else {
                            platform.velocity.x = -platform.velocity.x
                        }
                    } 
                } else {
                    if ((platform.pos.y > down_pos.y) && platform.velocity.y > 0) || 
                        ((platform.pos.y < up_pos.y) && platform.velocity.y < 0)
                    {
                        platform.velocity.y = -platform.velocity.y
                    }
                }
            }
            
            // Move monsters
            for &monster in current_level.rooms[current_level.current_room].monsters {
                monster.velocity += monster.acceleration * DT
                monster.pos += monster.velocity * DT

                if ((monster.pos.x > monster.end_pos.x) && monster.velocity.x > 0) || 
                    ((monster.pos.x < monster.start_pos.x) && monster.velocity.x < 0)
                {
                    monster.velocity.x = 0
                    monster.acceleration.x = -monster.acceleration.x
                } 
            }

            // If player is dead logic 
            if !player.is_dead {
                player.pos += player.velocity * DT
    
                // Change rooms if needed
                room_changed, new_roomid, new_player_pos := check_room_bounds(&player, &current_level.rooms[current_level.current_room])
                if room_changed {

                    // Reset everything in the rooms (platforms, monster, etc.)
                    reset_room(&current_level.rooms[current_level.current_room])

                    current_level.current_room = new_roomid
                    
                    player.pos = new_player_pos
        
                    camera.target = current_level.rooms[current_level.current_room].camera_pos
                }
    
            } else {
                // If is dead, move player to checkpoint (or start) position of level
                player.pos = current_level.checkpoint_pos
    
                current_level.current_room = current_level.checkpoint_room
                camera.target = current_level.rooms[current_level.current_room].camera_pos
                
                // Reset everything in all rooms
                for &room in current_level.rooms {
                    reset_room(&room)
                }

                player.is_dead = false
            }

            accumulated_time -= DT
        }

        rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)
            
            rl.BeginMode2D(camera)

            // Draw Tiles
            for i := 0; i < LEVEL_TILES_Y; i += 1 {
                for j := 0; j < LEVEL_TILES_X; j += 1 {
                    tile_indx := i * LEVEL_TILES_X + j
                    tile_pos := current_level.rooms[current_level.current_room].pos
                    tile_pos = {tile_pos.x + f32(TILE_SIZE * j), tile_pos.y + f32(TILE_SIZE * i)}
                    switch current_level.rooms[current_level.current_room].tile_map[tile_indx] {
                        case 0: {

                        }
                        case 1: {
                            // Wall
                            rl.DrawTexturePro(atlas,
                                rl.Rectangle{TILE_SIZE * 2, 0, TILE_SIZE, TILE_SIZE},
                                rl.Rectangle{tile_pos.x, tile_pos.y, TILE_SIZE, TILE_SIZE}, {}, 0, rl.WHITE)
                        }
                        case 2: {
                            // Spike
                            rl.DrawTexturePro(atlas,
                                rl.Rectangle{TILE_SIZE * 3, 0, TILE_SIZE, TILE_SIZE},
                                rl.Rectangle{tile_pos.x, tile_pos.y, TILE_SIZE, TILE_SIZE}, {}, 0, rl.WHITE)
                        }
                    }
                }
            }

            // Draw PLATFORM
            for platform in current_level.rooms[current_level.current_room].platforms {
                rl.DrawTexturePro(atlas, rl.Rectangle{0, TILE_SIZE, platform.size.x, platform.size.y},
                     rl.Rectangle{platform.pos.x, platform.pos.y, platform.size.x, platform.size.y},
                      {}, 0, rl.WHITE)
            }

            // Draw REVERSER
            for rev in current_level.rooms[current_level.current_room].reversers {
                // Currently handles only horizontal reversers
                rl.DrawRectangleV(rev.pos, rev.size, rl.PINK)
            }

            // Draw Monsters
            for monster in current_level.rooms[current_level.current_room].monsters {
                rl.DrawRectangleV(monster.pos, monster.size, rl.GRAY)
            }

            // Drawing player
            rl.DrawTexturePro(atlas,
                 rl.Rectangle{0,0,
                    player.direction == .RIGHT ? TILE_SIZE : -TILE_SIZE,
                    player.acceleration.y > 0 ? TILE_SIZE : -TILE_SIZE}, 
                    rl.Rectangle{player.pos.x, player.pos.y, player.size.x, player.size.y},
            rl.Vector2{}, 0.0, rl.WHITE )
            
            // Debug 
            if DEBUG_ON {
                p_pos_center := rl.Vector2{player.pos.x + player.size.x / 2, player.pos.y + player.size.y / 2} 
                rl.DrawLineEx(p_pos_center, p_pos_center + (player.velocity * 5), 5, rl.BROWN)
                rl.DrawRectangleLinesEx(rl.Rectangle{player.pos.x, player.pos.y,
                player.size.x, player.size.y}, 2, rl.YELLOW)
            }

            rl.EndMode2D()

            if DEBUG_ON {
                screen_w, screen_h := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())

                rl.DrawFPS(i32(screen_w * 0.9), i32(screen_h * 0.1))
            }
        rl.EndDrawing()
    }

    
}