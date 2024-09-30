package src

import "core:fmt"
import mat "core:math"

import rl "vendor:raylib"

AABB :: struct {
    pos         : rl.Vector2, 
    size        : rl.Vector2, // dimensions
    velocity    : rl.Vector2, 
}

Direction :: enum {
    NONE, UP, DOWN, LEFT, RIGHT,
}

Player :: struct {
    rect : rl.Rectangle,

    direction : Direction,

    velocity : rl.Vector2,
    acceleration : rl.Vector2,
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
    if t_hit_near < 0.0 || t_hit_near > 1.0 {
        return false, 1.0, {}, {}
    }

    if t_hit_far < 0 {return false, 1.0, {}, {}}

    contact_point = ray_origin + t_hit_near * ray_dir

    if t_near.x > t_near.y {
        contact_normal = inv_dir.x < 0 ? {1,0} : {-1,0}  
    } else if t_near.x < t_near.y {
        contact_normal = inv_dir.y < 0 ? {0,1} : {0,-1}
    }

    return true, t_hit_near, contact_point, contact_normal
}

rect_vs_rect :: proc(r1, r2 : AABB, dt : f32) -> (bool, f32, rl.Vector2, rl.Vector2) {
    if r1.velocity.x == 0 && r1.velocity.y == 0 {return false, 1.0, {},{}}

    expanded_target : AABB
    expanded_target.pos = r2.pos - r1.size / 2
    expanded_target.size = r2.size + r1.size

    ray_origin := r1.pos + r1.size / 2
    ray_dir    := r1.velocity * dt

    return ray_vs_rect(ray_origin, ray_dir, expanded_target)
}

GRAVITY := f32(800)
DEBUG_ON := true

main :: proc () { 

    player := Player{rect = {600, 200, 120, 120}, direction = .NONE, acceleration = {0, GRAVITY}}

    rl.InitWindow(1280, 720, "Demo")
    defer rl.CloseWindow()

    player_tex := rl.LoadTexture("assets/player.png")
    defer rl.UnloadTexture(player_tex)

    wall_up   := rl.Rectangle{100, 0, 1000, 100}
    wall_left   := rl.Rectangle{100, 100, 100, 500}
    wall_right := rl.Rectangle{1000, 100, 100, 500}

    walls := [dynamic]rl.Rectangle{wall_up,
        wall_left, wall_right}

    for i in 0..<10 {
        append(&walls, rl.Rectangle{f32(100 + i * 100), 500, 100, 100})
    }

    for !rl.WindowShouldClose() {

        if rl.IsKeyDown(rl.KeyboardKey.D) {
            if player.direction == .LEFT {
                player.direction = .RIGHT
                player.velocity.x = 0
            } else {
                player.velocity.x = 300
            }
        } else if rl.IsKeyDown(rl.KeyboardKey.A) {
            if player.direction == .RIGHT {
                player.direction = .LEFT
                player.velocity.x = 0
            } else {
                player.velocity.x = -300
            }
        } else {
            player.velocity.x = 0
        }


        if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
            player.acceleration.y = -player.acceleration.y 
        }
        if rl.IsKeyPressed(rl.KeyboardKey.F1) {
            DEBUG_ON = !DEBUG_ON
        }

        player.velocity += player.acceleration * rl.GetFrameTime()

        // Collision check
        player_aabb := AABB{{player.rect.x, player.rect.y}, {player.rect.width, player.rect.height},
         player.velocity}
        
        for w, i in walls {
            wall_aabb := AABB{{w.x, w.y}, {w.width, w.height}, 0}
            // Do collision
            collided, collision_time, _, normal := rect_vs_rect(player_aabb, wall_aabb, rl.GetFrameTime())
            // Handle collision 
            
            // TODO(Alikhan) 
            // Understand why absolute value of velocity vector must be taken
            // The line below does not detect collisions when moving left, and up (i.e when velocity < 0)
            player.velocity += normal * rl.Vector2{abs(player.velocity.x), abs(player.velocity.y)} * (1-collision_time)
            //player.velocity += (1 - collision_time) * player.velocity * normal  
        }

        player.rect.x += player.velocity.x * rl.GetFrameTime()
        player.rect.y += player.velocity.y * rl.GetFrameTime()


        rl.BeginDrawing()
            rl.ClearBackground(rl.GRAY)

            for w, i in walls {
                rl.DrawRectangleV({w.x, w.y}, {w.width, w.height},
                     rl.Color{u8(i * 10), u8(i * 10), u8(i * 20),
                255}) 
            }

            rl.DrawTexturePro(player_tex, rl.Rectangle{0,0,32,32}, player.rect,
            rl.Vector2{}, 0.0, rl.WHITE )
            
            if DEBUG_ON {
                p_pos_center := rl.Vector2{player.rect.x + player.rect.width / 2, player.rect.y + player.rect.height / 2} 
                rl.DrawLineEx(p_pos_center, p_pos_center + (player.velocity * 5), 10, rl.BROWN)
                rl.DrawRectangleLinesEx(player.rect, 5, rl.YELLOW)
            }

        rl.EndDrawing()
    }

    
}