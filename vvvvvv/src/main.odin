package src

import "core:fmt"

import rl "vendor:raylib"

main :: proc () {
    
    rl.InitWindow(1280, 720, "Demo")
    defer rl.CloseWindow()

    for !rl.WindowShouldClose() {

        rl.BeginDrawing()
            rl.ClearBackground(rl.GRAY)

            rl.DrawCircle(100, 100, 20, rl.RED)
        rl.EndDrawing()
    }

    
}