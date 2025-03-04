package src

import rl "vendor:raylib"
import "core:fmt"

import "core:mem"

MAP_WIDTH : u16
MAP_HEIGHT : u16
PHYSICS_DT :: 1.0 / 15.0


Level :: struct {
    release_rate : u8,
    max_lemmings : u16
}

Lemming_State :: enum {
    WALKER, FALLER, DIGGER,
    CLIMBER, FLOATER, BOMBER, BLOCKER, BUILDER, BASHER, MINER,

    SPLATTER, EXITER,
}

Animation :: struct {
    nframes : int,
    cur_frame : int,

    frame_length : f32,
    frame_time_passed : f32,

    sprite_offset : [2]f32,
}

skill_order := [?]Lemming_State{.BASHER, .BUILDER, .CLIMBER, .BOMBER, .FLOATER, .MINER, .BLOCKER, .DIGGER}

Skill_Set :: bit_set[Lemming_State]

Lemming :: struct {
    state : Lemming_State,
    state_changed : b8,
    
    active_skills : Skill_Set,

    accumulated_time : f32,

    is_dead : bool,

    pos : [2]i32,

    fall_amount : i32,

    foot_pixel      : [2]i32, 
    head_pixel      : [2]i32,

    dir : i8,

    draw_offset : [2]i32,   // This is need to correctly draw Diggers, and etc.

    using anim_data : Animation,
    anim_full_cycle_done : bool,
    anim_half_cycle_done : bool,
}

init_lemming :: proc(lem: ^Lemming) {
    lem.pos = {120,14}

    lem.foot_pixel = {8,16}
    lem.head_pixel = {7,6}
    lem.dir = 1

    set_state(lem, .FALLER)
}


set_state :: proc(lem : ^Lemming, state : Lemming_State) {
    lem.anim_data = Animation{}
    
    lem.anim_full_cycle_done = false
    lem.anim_half_cycle_done = false

    lem.draw_offset = {}

    lem.foot_pixel.y = 16

    #partial switch state {
        case .FALLER: {
            lem.fall_amount = 0

            lem.anim_data.nframes = 4
            lem.anim_data.sprite_offset = {400, 0}
        }
        case .WALKER: {
            lem.anim_data.nframes = 8
            lem.anim_data.sprite_offset = {0,0}
        }
        case .DIGGER: {
            lem.draw_offset = {0, 2}

            lem.anim_data.nframes = 16
            lem.anim_data.sprite_offset = {256, 48}
        }
        case .FLOATER: {
            lem.anim_data.nframes = 11
            lem.anim_data.sprite_offset = {0, 16}
        }
        case .EXITER: {
            lem.anim_data.nframes = 8
            lem.anim_data.sprite_offset = {272, 0}
        }
        case .SPLATTER: {
            lem.anim_data.nframes = 16
            lem.anim_data.sprite_offset = {0, 96}
        }
        case .CLIMBER: {
            lem.foot_pixel.y = 15
            
            lem.anim_data.nframes = 16
            lem.anim_data.sprite_offset = {256, 32}
        }
        case .BOMBER: {
            lem.anim_data.nframes = 17
            lem.anim_data.sprite_offset = {176, 16}
        }
        // case .BASHER: {

        // }
    }

    lem.state = state
    lem.state_changed = true
}

get_collision :: proc(col_map : [^]rl.Color, px, py : i32) -> i32 {
    color := col_map[py * i32(MAP_WIDTH) + px]

    // (Note) Assuming background is transparent.
    if (color.a == 0) {
        return 0
    }

    return 1
}

set_collision :: proc(col_map : [^]rl.Color, px, py : i32, color : rl.Color) {
    col_map[py * i32(MAP_WIDTH) + px] = color
}   

change_direction :: proc(lem : ^Lemming) {
    lem.dir = -lem.dir
    lem.foot_pixel.x += i32(lem.dir)       
    lem.head_pixel.x -= i32(lem.dir)        
}

Object_Kind :: enum {
    Door, Window, Turret
}

Object :: struct {
    using anim_data : Animation,

    kind : Object_Kind,
    sprite_size : [2]int,
    pos : [2]int,
}

explosion_mask := [256]u8 {
    1,1,1,1,1,1, 0,0,0,0, 1,1,1,1,1,1,
    1,1,1,1, 0,0,0,0,0,0,0,0, 1,1,1,1,
    1,1,1, 0,0,0,0,0,0,0,0,0,0, 1,1,1,
    1,1, 0,0,0,0,0,0,0,0,0,0,0,0, 1,1,
    1, 0,0,0,0,0,0,0,0,0,0,0,0,0,0, 1,
    1, 0,0,0,0,0,0,0,0,0,0,0,0,0,0, 1,
    0,0,0,0,0,0, 0,0,0,0, 0,0,0,0,0,0,
    0,0,0,0,0,0, 0,0,0,0, 0,0,0,0,0,0,
    0,0,0,0,0,0, 0,0,0,0, 0,0,0,0,0,0,
    0,0,0,0,0,0, 0,0,0,0, 0,0,0,0,0,0,
    1, 0,0,0,0,0,0,0,0,0,0,0,0,0,0, 1,
    1, 0,0,0,0,0,0,0,0,0,0,0,0,0,0, 1,
    1,1,0,0,0,0, 0,0,0,0, 0,0,0,0,1,1,
    1,1,1, 0,0,0,0,0,0,0,0,0,0, 1,1,1,
    1,1,1,1, 0,0,0,0,0,0,0,0, 1,1,1,1,
    1,1,1,1,1,1, 0,0,0,0, 1,1,1,1,1,1,
}

main :: proc() {
    
    when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    rl.InitWindow(1600, 1000, "Demo")
    defer rl.CloseWindow()

    game_viewport := [2]f32{320,200}

    scale_x, scale_y := i32(rl.GetScreenWidth()/320), i32(rl.GetScreenHeight()/200)
    scale := f32(min(scale_x, scale_y))

    camera := rl.Camera2D {
        offset = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},  // Camera position in Screen space
        target = {game_viewport.x / 2, game_viewport.y / 2},  // Camera position in World space
        rotation = 0,
        zoom = scale
    }
    
    img := rl.LoadImage("assets/collision-02.png")
    rl.ImageFormat(&img, rl.PixelFormat.UNCOMPRESSED_R8G8B8A8)

    my_data := rl.LoadImageColors(img)

    defer rl.UnloadImageColors(my_data)

    bg_tex := rl.LoadTextureFromImage(img)
    defer rl.UnloadTexture(bg_tex)
    MAP_WIDTH, MAP_HEIGHT = u16(bg_tex.width), u16(bg_tex.height)

    rl.UnloadImage(img)

    atlas_tex := rl.LoadTexture("assets/lem_anim.png")
    defer rl.UnloadTexture(atlas_tex)
    
    panel_tex := rl.LoadTexture("assets/panel.png")
    defer rl.UnloadTexture(panel_tex)

    objects : [dynamic]Object
    defer delete(objects)

    // Exit door
    append(&objects, Object{anim_data = {
        nframes = 6,
        sprite_offset = {0, 192},
        frame_length = PHYSICS_DT,
    }, sprite_size = {48, 32}, pos = {325, 124}})

    selected_panel := -1

    lemmings_arr : [dynamic]Lemming
    defer delete(lemmings_arr)

    release_time_passed : f32
    lems_released       : u16
    release_rate        := f32(1.5)


    // select_shader := rl.LoadShaderFromMemory(nil, `
    //     void main() {
    //         gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
    //     }
    // `)
    // defer rl.UnloadShader(select_shader)

    selected_lem_indx := -1

    for !rl.WindowShouldClose() {

        dt := rl.GetFrameTime()

        release_time_passed += dt
        for len(lemmings_arr) < 6 && release_time_passed > release_rate {
            lem_to_add : Lemming
            init_lemming(&lem_to_add)
            append(&lemmings_arr, lem_to_add)

            release_time_passed -= release_rate
        }

        if rl.IsKeyDown(rl.KeyboardKey.A) {
            camera.target.x -= 100 * dt
        }
        if rl.IsKeyDown(rl.KeyboardKey.D) {
            camera.target.x += 100 * dt
        }

        // if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
        //     mpos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

        //     x, y := i32(mpos.x), i32(mpos.y)
        //     if x >= 0 && x < i32(MAP_WIDTH) && y >= 0 && y < i32(MAP_HEIGHT) {
        //         set_collision(my_data, i32(mpos.x), i32(mpos.y), rl.BLANK)
                
        //         rl.UpdateTexture(bg_tex, my_data)
        //     }
        // }
    
        camera.zoom += (rl.GetMouseWheelMove() * 0.5)

        for &lem in lemmings_arr {
            lem.accumulated_time += dt

            for lem.accumulated_time > PHYSICS_DT {

                if !lem.is_dead {
                    #partial switch lem.state {
                        case .FALLER: {
                            dy := i32(0)
        
                            on_ground : bool
        
                            for c := i32(0); c < 3; c += 1 {
                                if get_collision(my_data, lem.pos.x + lem.foot_pixel.x, c + lem.pos.y + lem.foot_pixel.y) == 0 {
                                    dy += 1
                                } else {
                                    on_ground = true
                                    break
                                }
                            }
                            
                            lem.pos.y += dy
                            lem.fall_amount += dy
        
                            if /*dy == 0*/ on_ground  {
                                if lem.fall_amount > 53 {
                                    set_state(&lem, Lemming_State.SPLATTER)
                                } else {
                                    set_state(&lem, Lemming_State.WALKER)
                                }
                            } else {
                                if .FLOATER in lem.active_skills && lem.fall_amount > 20 {
                                    set_state(&lem, Lemming_State.FLOATER) 
                                }
                            }                        
        
                        }
                        case .WALKER: {
                            dy := i32(0)
                            for i in 1..=5 {
                                if get_collision(my_data, lem.pos.x + lem.foot_pixel.x, lem.foot_pixel.y + lem.pos.y - i32(i)) == 0 {
                                    break
                                } else {
                                    dy -= 1
                                }
                            }
        
                            if dy == 0 {
                                for i in 0..=4 {
                                    if get_collision(my_data, lem.pos.x + lem.foot_pixel.x, lem.foot_pixel.y + lem.pos.y + i32(i)) == 0 {
                                        dy += 1
                                    } else {
                                        break
                                    }
                                }
                            }
        
                            if dy == -5 {
                                if .CLIMBER in lem.active_skills {
                                    set_state(&lem, .CLIMBER);
                                    break       // (Note) break from case statement
                                } else {
                                    change_direction(&lem)
                                }
    
                            } else {
                                lem.pos.y += dy 
                            }
                            
                            if dy < 4 {
                                lem.pos.x += i32(lem.dir)
                            }
                            
                            if dy >= 4 {
                                set_state(&lem, .FALLER)
                            } 
        
                            // 346, 148
                            hitbox := lem.pos + lem.foot_pixel
                            hitbox.y -= 1   // get pixel exactly AT the foot.
                            if hitbox.x == 1200 && hitbox.y == 148 {
                                set_state(&lem, .EXITER)
                            }
        
                        }
                        case .FLOATER: {
                            lem.pos.y += 1
                            if get_collision(my_data, lem.pos.x + lem.foot_pixel.x, 
                                            lem.pos.y + lem.foot_pixel.y) != 0 {
                                set_state(&lem, .WALKER)
                            }
                        }
                        case .DIGGER: {
                            should_keep_digging := false
                            for i := lem.pos.x + 4; i <= lem.pos.x + lem.foot_pixel.x + 4; i += 1 {
                                if get_collision(my_data, i, lem.pos.y + lem.foot_pixel.y) != 0 {
                                    should_keep_digging = true
                                    break
                                }
                            }
                            if should_keep_digging {
                                if lem.anim_full_cycle_done || lem.anim_half_cycle_done {
                                    for i := lem.pos.x + 4; i <= lem.pos.x + lem.foot_pixel.x + 4; i += 1 {
                                        set_collision(my_data, i, lem.pos.y + lem.foot_pixel.y, rl.BLANK)
                                    }
                                    rl.UpdateTexture(bg_tex, my_data)
                                    lem.pos.y += 1
                                }
                            } else do set_state(&lem, .FALLER)
    
                        }
                        case .CLIMBER: {
                            if get_collision(my_data, lem.pos.x + lem.foot_pixel.x,
                                 lem.pos.y + lem.foot_pixel.y) == 0 {
                                set_state(&lem, .WALKER)
                            } else {
                                if get_collision(my_data, lem.pos.x + lem.head_pixel.x, lem.pos.y + lem.head_pixel.y) != 0 {
                                    set_state(&lem, .FALLER)
                                    change_direction(&lem)
    
                                } else do lem.pos.y -= 1
                            }
                        }
                        case .BOMBER: {
                            if lem.anim_full_cycle_done {
                                lem.is_dead = true
    
                                start_pos := lem.pos + {0,8}
                                for row := i32(0); row < 16; row+=1 {
                                    for col := i32(0); col < 16; col+=1 {
                                        pixel := start_pos + {col, row}
                                        if explosion_mask[16*row+col] == 0 && pixel.x < i32(MAP_WIDTH) && pixel.y < i32(MAP_HEIGHT) {
                                            set_collision(my_data, pixel.x, pixel.y, rl.BLANK)
                                        } 
                                    }
                                }
                                rl.UpdateTexture(bg_tex, my_data)
                            }
                        }
                        case .EXITER: {
                            
                        }
                        case .SPLATTER: {
                            if lem.anim_full_cycle_done do lem.is_dead = true
                        }
                    }
    
                    if !lem.state_changed {
                        if lem.state == .FLOATER && lem.cur_frame + 1 == lem.nframes {
                            lem.cur_frame = 4
                        } else {
                            lem.cur_frame += 1
        
                            if lem.cur_frame == (lem.nframes / 2 - 1) {
                                lem.anim_half_cycle_done = true
                            } else if lem.cur_frame == lem.nframes - 1 {
                                lem.anim_full_cycle_done = true
                            } else {
                                lem.anim_full_cycle_done = false
                                lem.anim_half_cycle_done = false
                            }
        
                            lem.cur_frame = lem.cur_frame % lem.nframes
                        }
                    } else do lem.state_changed = false
    
                }

                lem.accumulated_time -= PHYSICS_DT
            }
        } 


        rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)

            rl.BeginMode2D(camera)

            rl.ClearBackground(rl.BLACK)

            rl.DrawTexturePro(bg_tex, {0,0,f32(bg_tex.width), f32(bg_tex.height)},
                {0,0, f32(bg_tex.width), f32(bg_tex.height)}, {}, 0, rl.WHITE)

            // Draw Static objects
            // Draw exit door
            for &obj in objects {
                rl.DrawTexturePro(atlas_tex, {obj.sprite_offset.x + f32(obj.cur_frame * obj.sprite_size.x),
                     obj.sprite_offset.y, f32(obj.sprite_size.x), f32(obj.sprite_size.y)},
                    {f32(obj.pos.x), f32(obj.pos.y), f32(obj.sprite_size.x), f32(obj.sprite_size.y)}, {}, 0, rl.WHITE)
                
                // Update animation data
                obj.frame_time_passed += dt
                for obj.frame_time_passed > obj.frame_length {
                    obj.cur_frame = (obj.cur_frame + 1) % obj.nframes

                    obj.frame_time_passed -= obj.frame_length
                }
            }


            // Draw Lemmings

            for lem, indx in lemmings_arr {
                if !lem.is_dead {
                    // rl.BeginShaderMode(select_shader)

                    tint := rl.WHITE
                    if indx == selected_lem_indx {
                        tint = rl.RED
                    }

                    rl.DrawTexturePro(atlas_tex, {lem.sprite_offset.x + f32(lem.cur_frame * 16),
                        lem.sprite_offset.y, 16 * f32(lem.dir), 16},
                    {f32(lem.pos.x + lem.draw_offset.x),
                        f32(lem.pos.y + lem.draw_offset.y), 16, 16}, {}, 0, tint)
                
                    // rl.EndShaderMode()
                }
            }

            // Draw Crosshair
            mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

            selected_lem_indx = -1
            min_diff_x, min_diff_y := i32(6), i32(5)

            for &lem, indx in lemmings_arr {
                if !lem.is_dead && abs(lem.pos.x + 8 - i32(mouse_pos.x)) < min_diff_x && 
                    abs(lem.pos.y + 9 - i32(mouse_pos.y)) < min_diff_y {
                        selected_lem_indx = indx
                        
                        min_diff_x = abs(lem.pos.x + 8 - i32(mouse_pos.x))
                        min_diff_y = abs(lem.pos.y + 9 - i32(mouse_pos.y))
                }
            }

            if selected_lem_indx >= 0 && rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && selected_panel >= 2 && selected_panel <= 9 {
                skill_index := selected_panel - 2
                #partial switch skill_order[skill_index] {
                    // permanent skills 
                    case .FLOATER, .CLIMBER: {
                        lemmings_arr[selected_lem_indx].active_skills |= {skill_order[skill_index]}
                    }
                    case: {
                        if skill_order[skill_index] != lemmings_arr[selected_lem_indx].state {
                            set_state(&lemmings_arr[selected_lem_indx], skill_order[skill_index])
                        }
                    }
                }
            }

            crosshair_offset : [2]f32
            crosshair_offset = (selected_lem_indx >= 0) ? {480, 0} : {464, 0}

            rl.DrawTexturePro(atlas_tex, {crosshair_offset.x, crosshair_offset.y, 15, 15},
                {mouse_pos.x - (15/2), mouse_pos.y - (15/2), 15, 15}, {}, 0, rl.WHITE)            

            rl.EndMode2D()

            sw, sh := rl.GetScreenWidth(), rl.GetScreenHeight()
            scale = f32(sh / 200)
            
            // Draw Panel
            rl.DrawTexturePro(panel_tex, {0,0,320,40},
                {0, f32(sh) - scale * 40, scale * 320, scale * 40}, {}, 0, rl.WHITE)

            mpos := rl.GetMousePosition()
            
            if selected_panel != -1 {
                rl.DrawTexturePro(panel_tex, {320, 16, 16, 24},
                    {f32(selected_panel) * 16 * scale, f32(sh) - scale * 24, scale * 16, scale * 24},
                    0, 0, rl.WHITE)
            }
            
            if mpos.y > (200-24) * scale {
                for i := 1; i <= 11; i += 1 {
                    if mpos.x < (f32(i * 16) * scale) {
                        rl.DrawTexturePro(panel_tex, {336, 16, 16, 24},
                            {f32(i-1) * 16 * scale, f32(sh) - scale * 24, scale * 16, scale * 24},
                            {}, 0, rl.WHITE)
                        if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
                            selected_panel = i - 1
                        }        
                        break
                    }
                }
            }

            // if rl.GuiButton({24,24,120,30}, "#191#Show Message") { }
            rl.DrawFPS(1400, 0);
        rl.EndDrawing()
        
    }
}