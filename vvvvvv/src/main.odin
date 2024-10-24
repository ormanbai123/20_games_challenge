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

Animation_kind :: enum {
    IDLE, RUN
}

Direction :: enum {
    LEFT, RIGHT
}

Sprite_info :: struct {
    atlas_offset : rl.Vector2,
}

Player :: struct {
    pos : rl.Vector2,
    size : rl.Vector2,

    direction : Direction,

    velocity : rl.Vector2,
    acceleration : rl.Vector2,

    on_wall : bool,
    is_dead : bool,

    current_anim : Animation_kind,
    anims : [2]Animation, // (Note) this is currently hardcoded.
}

Platform_kind :: enum {
    HORIZONTAL, VERTICAL
}

Animation :: struct {
    num_of_frames : u8,
    frame_timer : f32,
    current_frame : u8,
    frame_length : f32,
}

reset_animation :: proc (anim: ^Animation) {
    anim.current_frame = 0
    anim.frame_timer = 0
}

Checkpoint :: struct {
    pos : rl.Vector2,
    size : rl.Vector2,

    room_uuid : u128,
    activated : bool,

    gravity_is_up : bool, // false - down (default value), true - up

    // valid 
    // if true, then checkpoint exists (this is used when checking collision with checkpoint)
    // if false, then the instance of struct is meaningless
    valid : bool, 
}

update_animation :: proc (anim : ^Animation, elapsed_time : f32) -> bool {
    anim.frame_timer += elapsed_time

    reached_end := false

    for anim.frame_timer > anim.frame_length {
        anim.current_frame += 1
        anim.frame_timer -= anim.frame_length

        if anim.current_frame == anim.num_of_frames {
            reached_end = true
            anim.current_frame = 0
        }
    } 

    return reached_end
}

Platform :: struct {
    start_pos : rl.Vector2,
    end_pos   : rl.Vector2,
    pos       : rl.Vector2,

    size : rl.Vector2,
    
    kind : Platform_kind,

    // Fields for destroyable platforms
    destroyable : bool,
    destroyed : bool,
    anim_data : Animation,
    // 


    is_one_way : bool, 
    started_moving : bool, // only applicable to one_way platforms

    velocity : rl.Vector2,
    initial_velocity : rl.Vector2, // Reset velocity
}

Reverser :: struct {
    pos : rl.Vector2,
    size : rl.Vector2,
}

Monster :: struct {
    pos, start_pos, end_pos : rl.Vector2,
    size : rl.Vector2,
    velocity, acceleration : rl.Vector2,

    initial_velocity, initial_acceleration : rl.Vector2,

    
    accelerated : bool,
    
    is_vertical : bool,
    anim_data : Animation, // (TODO) finish this.
}

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

make_positive :: proc (num : f32) -> f32 {
    if num < 0 {
        return -num
    }
    return num
}
make_negative :: proc (num : f32) -> f32 {
    if num > 0 {
        return -num
    }
    return num
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
    levels = make([]Level, 1, g_level_allocator) // Create levels array

    // Create level 1    
    load_level("assets/level/level1.ldtk")
    current_level := levels[0]


    player := Player{
        pos = current_level.rooms[current_level.current_room].checkpoint.pos,
        size = {TILE_SIZE * 0.8, TILE_SIZE},
        direction = .RIGHT, acceleration = {0, GRAVITY},
        anims = {
            {
                num_of_frames = 11,
                frame_length = 1 / 15.0
            },
            {
                num_of_frames = 12,
                frame_length = 1 / 15.0
            }
        }
    }

    rl.InitWindow(1280, 640, "Demo")
    defer rl.CloseWindow()

    //rl.SetTargetFPS(144)

    camera = {
        {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)}, // Camera position in Screen space
        get_room_centre(&current_level.rooms[current_level.current_room]),    // Camera position in World  space
        0.0,                                                           // Rotation
        2.0                                                            // Zoom
    }

    atlas := rl.LoadTexture("assets/icetile.png")
    defer rl.UnloadTexture(atlas)

    // background_tex := rl.LoadTexture("assets/background.png")
    // defer rl.UnloadTexture(background_tex)

    // background_pos_x := f32(0)


    accumulated_time : f32

    // Game logic is run in 60HZ
    DT :: 1.0 / 60.0

    collision_arr := make([]Sort_pair, LEVEL_TILES_X * LEVEL_TILES_Y)
    defer delete(collision_arr)
    collision_arr_size := 0

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

                player.current_anim = .RUN
                update_animation(&player.anims[Animation_kind.RUN], DT)

            } else if rl.IsKeyDown(.A) {
                if player.direction == .RIGHT {
                    player.direction = .LEFT
                    player.velocity.x = 0
                } else {
                    player.velocity.x = -250
                }

                player.current_anim = .RUN
                update_animation(&player.anims[Animation_kind.RUN], DT)

            } else {
                player.current_anim = .IDLE
                update_animation(&player.anims[Animation_kind.IDLE], DT)
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
            for &platform in current_level.rooms[current_level.current_room].platforms {
                if !platform.destroyed {
                    // Subtract platform's velocity from player's to get relative velocity
                    // This way, the platform appears to be stationary
                    relative_velocity := player.velocity - platform.velocity

                    player_aabb := AABB{{player.pos.x + player.size.x * 0.1, player.pos.y}, player.size, relative_velocity}
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

                        if platform.is_one_way {
                            platform.started_moving = true
                        }

                        if platform.destroyable {
                            platform.destroyed = update_animation(&platform.anim_data, DT)
                        }

                        player.on_wall = true
                    } 
                }
            }

            // Sort collision rects
            collision_arr_size = 0

            for i := 0; i < LEVEL_TILES_Y; i += 1 {
                for j := 0; j < LEVEL_TILES_X; j += 1 {
                    tile_indx := u32(i * LEVEL_TILES_X + j)
                    if current_level.rooms[current_level.current_room].collision_map[tile_indx] > 0 {
                        starting_pos := current_level.rooms[current_level.current_room].pos
    
                        player_aabb := AABB{{player.pos.x + player.size.x * 0.2, player.pos.y}, player.size, player.velocity}
    
                        wall_aabb := AABB{{starting_pos.x + f32(j * TILE_SIZE) + TILE_SIZE * 0.1,
                             starting_pos.y + f32(i * TILE_SIZE)},
                         {TILE_SIZE * 0.8, TILE_SIZE}, 0}
    
                         // Do the collision
                        collided, collision_time, _, _ := rect_vs_rect(player_aabb, wall_aabb, DT)
                        
                        if collided {
                            collision_arr[collision_arr_size].indx = tile_indx
                            collision_arr[collision_arr_size].bb = wall_aabb
                            collision_arr[collision_arr_size].collision_time = collision_time

                            collision_arr_size += 1
                            //append(&collision_arr, Sort_pair{tile_indx, wall_aabb, collision_time})
                        }
                    } 
                }
            }
    
            // Do the actual sorting
            slice.sort_by(collision_arr[:collision_arr_size], collision_sort_func)
            
            for i in collision_arr {
                starting_pos := current_level.rooms[current_level.current_room].pos
    
                player_aabb := AABB{{player.pos.x + player.size.x * 0.2, player.pos.y}, player.size, player.velocity}
    
                    // Do the collision
                collided, collision_time, _, normal := rect_vs_rect(player_aabb, i.bb, DT)
    
                if collided {
                    // Handle the collision 
                    player.velocity += normal * rl.Vector2{abs(player.velocity.x), abs(player.velocity.y)} * (1-collision_time)
                    
                    // TODO CHANGE THIS?
                    //player.velocity += normal * rl.Vector2{0, 0.1}
    
                    player.on_wall = (abs(normal.y) > mat.F32_EPSILON)
                    
                    // Check if collided with killable obstacles
                    if Entity_kind(current_level.rooms[current_level.current_room].collision_map[i.indx]) == .SPIKE {
                        player.is_dead = true
                    }
                }
            }
            
            // Collision with REVERSER
            for reverser in current_level.rooms[current_level.current_room].reversers {
                player_aabb := AABB{{player.pos.x + player.size.x * 0.2, player.pos.y}, player.size, player.velocity}
    
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
    
                player_aabb := AABB{{player.pos.x + player.size.x * 0.2, player.pos.y}, player.size, relative_velocity}
                _aabb := AABB{monster.pos, monster.size, 0}
                // Do the collision
                collided, collision_time, _, normal := rect_vs_rect(player_aabb, _aabb, DT)
                // Handle the collision 
                relative_velocity += normal * rl.Vector2{abs(relative_velocity.x), abs(relative_velocity.y)} * (1-collision_time)
    
                if collided {
                    player.is_dead = true
                } 
            }
            
            // Collision with Checkpoints
            {
                player_aabb := AABB{{player.pos.x + player.size.x * 0.2, player.pos.y}, player.size, player.velocity}
    
                _aabb := AABB{ current_level.rooms[current_level.current_room].checkpoint.pos,
                    current_level.rooms[current_level.current_room].checkpoint.size, 0}
    
                  // Do the collision
                  collided, _, _, _ := rect_vs_rect(player_aabb, _aabb, DT)
    
                  if current_level.rooms[current_level.current_room].checkpoint.valid && collided {
                      // Handle the collision 
                      if !current_level.rooms[current_level.current_room].checkpoint.activated {
                            // Deactivate previous checkpoint and set the current one
                            current_level.checkpoint.activated = false
                            current_level.rooms[current_level.current_room].checkpoint.activated = true
                            current_level.checkpoint = &current_level.rooms[current_level.current_room].checkpoint
                      }
                  }
            }

            // Move platforms
            for &platform in current_level.rooms[current_level.current_room].platforms {

                if (platform.is_one_way && platform.started_moving) || (!platform.is_one_way) {
                    platform.pos += platform.velocity * DT
                } 

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
                            platform.pos = platform.end_pos
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

                left_pos, right_pos := monster.start_pos, monster.end_pos
                if left_pos.x >= right_pos.x {
                    left_pos, right_pos = right_pos, left_pos
                }
                up_pos, down_pos := monster.start_pos, monster.end_pos
                if down_pos.y <= up_pos.y {
                    down_pos, up_pos = up_pos, down_pos
                }

                if ((monster.pos.x > right_pos.x) && monster.velocity.x > 0) || 
                    ((monster.pos.x < left_pos.x) && monster.velocity.x < 0)
                {
                    if !monster.accelerated {
                        monster.velocity.x = -monster.velocity.x 
                    } else {
                        monster.velocity.x = 0
                        monster.acceleration.x = -monster.acceleration.x
                    }

                } 
                if ((monster.pos.y > down_pos.y) && monster.velocity.y > 0) || 
                    ((monster.pos.y < up_pos.y) && monster.velocity.y < 0)
                {
                    if !monster.accelerated {
                        monster.velocity.y = -monster.velocity.y 
                    } else {
                        monster.velocity.y = 0
                        monster.acceleration.y = -monster.acceleration.y
                    }
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
        
                    camera.target = get_room_centre(&current_level.rooms[current_level.current_room])
                }
    
            } else {
                // If is dead, move player to checkpoint (or start) position of level
                player.pos = current_level.checkpoint.pos
                
                // (TODO) set correct gravity direction when player respawns, so that
                // he won't be flying above at the respawn 

                current_level.current_room = map_uuid_id[current_level.checkpoint.room_uuid]
                camera.target = get_room_centre(&current_level.rooms[current_level.current_room])
                
                if current_level.checkpoint.gravity_is_up  {player.acceleration.y = make_negative(player.acceleration.y) }
                    else { player.acceleration.y = make_positive(player.acceleration.y) }

                // Reset everything in all rooms
                for &room in current_level.rooms {
                    reset_room(&room)
                }

                player.is_dead = false
            }

            accumulated_time -= DT
        }

        rl.BeginDrawing()
            rl.ClearBackground(rl.Color{0xBB, 0xDF, 0xF2, 0xFF})
            
            rl.BeginMode2D(camera)

            // Draw Tiles
            for tile in current_level.rooms[current_level.current_room].tile_map {
                if tile.not_empty {
                    rl.DrawTexturePro(atlas, rl.Rectangle{tile.src.x, tile.src.y, TILE_SIZE, TILE_SIZE},
                        rl.Rectangle{tile.pos.x, tile.pos.y, TILE_SIZE, TILE_SIZE}, {}, 0, rl.WHITE)
                }
            }

            // Draw checkpoint
            if current_level.rooms[current_level.current_room].checkpoint.valid {
                using current_level.rooms[current_level.current_room].checkpoint

                tex_offset := f32(!activated ? 0 : TILE_SIZE)

                rl.DrawTexturePro(atlas, rl.Rectangle{ATLAS_OFFSET__CHECKPOINT.x + tex_offset, ATLAS_OFFSET__CHECKPOINT.y,
                        TILE_SIZE, TILE_SIZE},
                        rl.Rectangle{pos.x, pos.y, size.x, size.y}, {}, 0, rl.WHITE) 
                
            }

            // Draw PLATFORM
            for platform in current_level.rooms[current_level.current_room].platforms {
                if !platform.destroyed {

                    offset := platform.destroyable ? ATLAS_OFFSET__DESTROYABLE_PLATFORM : ATLAS_OFFSET__PLATFORM

                    rl.DrawTexturePro(atlas,
                        rl.Rectangle{offset.x + f32(platform.anim_data.current_frame * TILE_SIZE),
                            offset.y, platform.size.x, platform.size.y},
                        rl.Rectangle{platform.pos.x, platform.pos.y, platform.size.x, platform.size.y},
                            {}, 0, rl.WHITE)
                }
            }

            // Draw REVERSER
            for rev in current_level.rooms[current_level.current_room].reversers {
                // Currently handles only horizontal reversers
                rl.DrawRectangleV(rev.pos, rev.size, rl.BLUE)
            }

            // Draw Monsters
            for monster in current_level.rooms[current_level.current_room].monsters {
                rl.DrawRectangleV(monster.pos, monster.size, rl.GRAY)
            }

            // Draw player
            {
                offset := player.current_anim == .IDLE ? ATLAS_OFFSET__PLAYER_IDLE : ATLAS_OFFSET__PLAYER_RUN
                rl.DrawTexturePro(atlas,
                    rl.Rectangle{offset.x + f32(player.anims[player.current_anim].current_frame * TILE_SIZE),
                        offset.y,
                        player.direction == .RIGHT ? TILE_SIZE : -TILE_SIZE,
                        player.acceleration.y > 0 ? TILE_SIZE : -TILE_SIZE}, 
                        rl.Rectangle{player.pos.x, player.pos.y, TILE_SIZE, TILE_SIZE},
                rl.Vector2{}, 0.0, rl.WHITE )
            }

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

    // Delete map
    delete(map_uuid_id)
}