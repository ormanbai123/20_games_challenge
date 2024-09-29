package src

import "core:fmt"
import "core:math/rand"

import mat "core:math"

import rl "vendor:raylib"

SCREEN_WIDTH    :: 640
SCREEN_HEIGHT   :: 480

START_POS_X     :: 50
START_POS_Y     :: 50

GameState :: enum {
    PLAYING, START
}
game_state := GameState.START

Player :: struct {
    pos_x       : f32,
    pos_y       : f32,

    w           : f32,
    h           : f32,

    velocity     : f32,
    acceleration : f32,

    on_floor    : bool,
    is_dead     : bool,
}
player := Player {pos_x = START_POS_X, pos_y = START_POS_Y, w = 40, h = 40} 


GRAVITY :: 1200.0
dt : f32 // Delta Time

Wall :: struct {
    thickness   : f32,
    pos_x       : f32,

    upper_y     : f32,
    lower_y     : f32,
}
walls: [40]Wall
farthest_wall_x : f32


check_collision :: proc(p :^Player, wall :^Wall) -> bool {
    collision_x := (p.pos_x < (wall.pos_x + wall.thickness)) && ((p.pos_x + p.w) > wall.pos_x) 
    collision_y := (p.pos_y < wall.upper_y) || (p.pos_y + p.h > wall.lower_y)

    return collision_x && collision_y
}

generate_map :: proc(walls : []Wall) {
    wall_x      := f32(600) // "600" - x position of the first wall.
    thickness   := f32(40) 

    minimum_gap     := i32(player.h * 2)
    minimum_pipe_h  := i32(SCREEN_HEIGHT * 0.2)

    for i := 0; i < len(walls); i += 1 {
        walls[i].thickness = thickness
        walls[i].pos_x = wall_x
        wall_x += 320
        
        walls[i].upper_y = f32(minimum_pipe_h + rand.int31_max(SCREEN_HEIGHT - minimum_gap - minimum_pipe_h * 2))
        gap := f32(minimum_gap + rand.int31_max(SCREEN_HEIGHT - i32(walls[i].upper_y) - minimum_pipe_h - minimum_gap))
        walls[i].lower_y = walls[i].upper_y + gap
    }

    farthest_wall_x = walls[len(walls) - 1].pos_x 
}

move_walls :: proc(walls: []Wall) {
    for &wall in walls {
        // TODO change this.
        if wall.pos_x + wall.thickness < mat.F32_EPSILON  {
            wall.pos_x = farthest_wall_x + 160
            farthest_wall_x = wall.pos_x  
        } else {
            wall.pos_x -= 300 * dt
        }
    }
}

reset_map :: proc(walls: []Wall) {
    generate_map(walls[:])

    player.is_dead, player.on_floor = false, false
    player.pos_x, player.pos_y = START_POS_X, START_POS_Y
    player.velocity, player.acceleration = 0, 0
}


main :: proc() {
    score       := 0
    max_score   := 0

    current_wall_indx := 0

	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Demo")
    defer rl.CloseWindow()

    rl.InitAudioDevice()
    defer rl.CloseAudioDevice()

	//rl.SetTargetFPS(60)

    die_sound := rl.LoadSound("assets/audio_hit.ogg")
    defer rl.UnloadSound(die_sound)

    point_sound := rl.LoadSound("assets/audio_point.ogg")
    defer rl.UnloadSound(point_sound)

    message_tex := rl.LoadTexture("assets/message.png")
    defer rl.UnloadTexture(message_tex)

    floor_tex := rl.LoadTexture("assets/base.png")
    defer rl.UnloadTexture(floor_tex)

    background_tex := rl.LoadTexture("assets/background.png")
    defer rl.UnloadTexture(background_tex)

    upflap_tex := rl.LoadTexture("assets/bird_sheet.png")
    defer rl.UnloadTexture(upflap_tex)

    pipe_tex := rl.LoadTexture("assets/pipe.png")
    defer rl.UnloadTexture(pipe_tex)

    reset_map(walls[:])

    dt = rl.GetFrameTime()

    floor_pos_x := f32(0)
    floor_w, floor_h := floor_tex.width, floor_tex.height

	for !rl.WindowShouldClose()
    {   
        // Draw
        //----------------------------------------------------------------------------------
        rl.BeginDrawing()
            rl.ClearBackground(rl.RAYWHITE)

            rl.DrawTexturePro(background_tex,
                 rl.Rectangle{0,0, f32(background_tex.width), f32(background_tex.height)},
                  rl.Rectangle{0,0, f32(rl.GetScreenWidth()-1), f32(rl.GetScreenHeight()-1)}, 
            rl.Vector2{}, 0, rl.WHITE)
            
            // Drawing floor
            if floor_pos_x > f32(floor_w / 2) {
                floor_pos_x = floor_pos_x - f32(floor_w / 2)
            }
            rl.DrawTexturePro(floor_tex,
                rl.Rectangle{floor_pos_x, 0, f32(floor_w), f32(floor_h)},
                rl.Rectangle{0, SCREEN_HEIGHT * 0.9, 
                SCREEN_WIDTH - 1, SCREEN_HEIGHT * 0.1},
                rl.Vector2{}, 0.0, rl.WHITE)

            // Drawing walls
            for wall in walls {
                if i32(wall.pos_x + wall.thickness) > 0 && i32(wall.pos_x) < SCREEN_WIDTH {
                    // Upper pipe
                    rl.DrawTexturePro(pipe_tex, rl.Rectangle{0,0, f32(pipe_tex.width),
                        -wall.upper_y},
                         rl.Rectangle{wall.pos_x, f32(0), wall.thickness, wall.upper_y},
                          rl.Vector2{}, 0.0, rl.WHITE)

                    // Lower pipe
                    rl.DrawTexturePro(pipe_tex,
                        rl.Rectangle{0,0, f32(pipe_tex.width), (SCREEN_HEIGHT * 0.9) - wall.lower_y},
                        rl.Rectangle{wall.pos_x, wall.lower_y, wall.thickness,
                             (SCREEN_HEIGHT * 0.9) - wall.lower_y}, rl.Vector2{}, 0.0, rl.WHITE)    
                }
            }

            bird_indx := f32((game_state == GameState.START) ? 2 : player.velocity > 0 ? 0 : 1) 
            bird_tex_width := f32(upflap_tex.width / 3)

            bird_rect := rl.Rectangle{bird_indx * bird_tex_width, 0, f32(bird_tex_width), f32(upflap_tex.height)}
            player_rect := rl.Rectangle{player.pos_x, player.pos_y, player.w, player.h}

            rl.DrawTexturePro(upflap_tex, bird_rect, player_rect, rl.Vector2{}, 0.0, rl.WHITE)
            
            if game_state == .START {
                rl.DrawTexturePro(message_tex,
                    rl.Rectangle{0,0, f32(message_tex.width), f32(message_tex.height)},
                    rl.Rectangle{f32(rl.GetScreenWidth() / 2) - (0.3 * f32(rl.GetScreenWidth())),
                        f32(rl.GetScreenHeight() / 2) - (0.3 * f32(rl.GetScreenHeight())),
                        0.6 * f32(rl.GetScreenWidth()), 0.6 * f32(rl.GetScreenHeight())},
                        rl.Vector2{}, 0.0, rl.WHITE)
            } else {
                rl.DrawText(rl.TextFormat("SCORE: %i", score), rl.GetScreenWidth() / 3, 0, 30, rl.YELLOW)
            }

            dt = rl.GetFrameTime()
       rl.EndDrawing()
        //----------------------------------------------------------------------------------

        switch game_state {
            case .START : {
                if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    // Start playing
                    current_wall_indx = 0
                    score = 0

                    game_state = GameState.PLAYING
                }
            }
            case .PLAYING : {
                
                player.acceleration += GRAVITY * dt

                if !player.is_dead {
                    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                        player.acceleration = 0
                        player.velocity = -GRAVITY / 7 
                    }
                } else {
                    if player.on_floor {
                        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                            // Reset map, go to start state
                            reset_map(walls[:])
                            game_state = GameState.START
                            break
                        }
                    } else {
                        // player.pos_y += GRAVITY * 2 * dt // Faster fall when dead   
                        player.acceleration += GRAVITY * dt 
                    }
                }
                
                // Update player's position
                player.velocity += player.acceleration * dt
                player.pos_y += player.velocity * dt 


                // Check if player fell 
                if !player.on_floor && player.pos_y + player.h >= SCREEN_HEIGHT * 0.9 {
                    player.on_floor = true
                    player.is_dead = true
                }

                if !player.is_dead {
                    if player.pos_x > (walls[current_wall_indx].pos_x + walls[current_wall_indx].thickness / 2) {
                        // If crossed halfway through pipe then score += 1
                        rl.PlaySound(point_sound)
                        score += 1
                        current_wall_indx = (current_wall_indx + 1) % len(walls)
                    }
                    
                    // Collision detection
                    for i := 0; i < len(walls); i += 1 {
                        if check_collision(&player, &walls[i]) {
                            player.is_dead = true
                            rl.PlaySound(die_sound)
                            break
                        }
                    }

                    // Move floor
                    floor_pos_x += 200 * dt;
                    
                    // Move walls
                    move_walls(walls[:])
                } 

            }
        }

    }
}