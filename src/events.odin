#+feature using-stmt

package kolori

import "../odin-imgui/imgui_impl_sdl3"
import imgui "../odin-imgui"
import opengl "vendor:OpenGL"
import sdl "vendor:sdl3"
import "core:time"
import "core:log"
import "core:fmt"

PAN_SPEED :: (f32)(10)
ZOOM_SPEED :: (f32)(1.1)

process_events :: proc(app: ^App_State) 
{
	event: sdl.Event
	for sdl.PollEvent(&event) {
		imgui_impl_sdl3.ProcessEvent(&event)
		handle_event(app, &event)
	}
}

handle_event :: proc(app: ^App_State, event: ^sdl.Event) 
{
	opengl.UseProgram(app.program)

	#partial switch event.type {
	// todo(touchscreens) support pinching motions for zoom in/out 
	case .QUIT:
		app.running = false
	case .WINDOW_RESIZED:
		width, height: i32
		sdl.GetWindowSizeInPixels(app.window, &width, &height)
		opengl.Viewport(0, 0, width, height)
		opengl.Uniform2i(app.uniforms.resolution, width, height)
	case .KEY_DOWN:
		if app.io.WantCaptureKeyboard {
			break
		}

		handle_key(app, event)
	case .MOUSE_WHEEL:
		if app.io.WantCaptureMouse || event.wheel.y == 0 {
			break
		}

		zoom(app, event.wheel.y < 0 ? ZOOM_SPEED : 1 / ZOOM_SPEED)
	case .MOUSE_MOTION:
		if app.io.WantCaptureMouse {
			break
		}

		if .LEFT in event.motion.state {
			pan(app, {-event.motion.xrel, event.motion.yrel})
		}
	}
}

handle_key :: proc(app: ^App_State, event: ^sdl.Event) 
{
	shift_key := .LSHIFT in event.key.mod || .RSHIFT in event.key.mod

	switch event.key.key {
	case sdl.K_F12:
		width, height: i32
		sdl.GetWindowSizeInPixels(app.window, &width, &height)

		take_screenshot(app.window, width, height)
	case sdl.K_F11, sdl.K_F:
		is_fullscreen := .FULLSCREEN in sdl.GetWindowFlags(app.window)
		sdl.SetWindowFullscreen(app.window, !is_fullscreen)
		sdl.SyncWindow(app.window)
	case sdl.K_ESCAPE:
		reset_view(app)
	case sdl.K_R:
		if shift_key {
			reset_view(app)
		}

		reload_shaders(app)
	case sdl.K_P: app.animation_paused = !app.animation_paused
	case sdl.K_H:
		app.show_ui = !app.show_ui

		if shift_key {
			ok: bool
			if sdl.CursorVisible() {
				ok = sdl.HideCursor()
			} else {
				ok = sdl.ShowCursor()
			}

			if !ok {
				log.error(
                    "[sdl.ShowCursor] Failed to change cursor visiblity. Error msg:",
                    sdl.GetError()
                )
			}
		}
	case sdl.K_MINUS, sdl.K_Z:
		zoom(app, ZOOM_SPEED)
	case sdl.K_EQUALS, sdl.K_X:
		zoom(app, 1 / ZOOM_SPEED)
	case sdl.K_W, sdl.K_UP:
		pan(app, {0, 1}, PAN_SPEED * (shift_key ? 2 : 1))
	case sdl.K_A, sdl.K_LEFT:
		pan(app, {-1, 0}, PAN_SPEED * (shift_key ? 2 : 1))
	case sdl.K_S, sdl.K_DOWN:
		pan(app, {0, -1}, PAN_SPEED * (shift_key ? 2 : 1))
	case sdl.K_D, sdl.K_RIGHT:
		pan(app, {1, 0}, PAN_SPEED * (shift_key ? 2 : 1))
	}
}

take_screenshot :: proc(window: ^sdl.Window, width, height: i32) 
{
	surface := sdl.CreateSurface(width, height, .RGB24)

	opengl.ReadBuffer(opengl.BACK)
	opengl.PixelStorei(opengl.PACK_ALIGNMENT, 1)
	opengl.ReadPixels(
		0,
		0,
		width,
		height,
		opengl.RGB,
		opengl.UNSIGNED_BYTE,
		surface.pixels,
	)

	sdl.FlipSurface(surface, .VERTICAL)
	defer sdl.DestroySurface(surface)

	filename := fmt.ctprintf("kolori_screenshot%s.png", now_to_string())

	if sdl.SavePNG(surface, filename) {
		log.info("Saved screenshot to", filename)
	} else {
		log.error(
            "[sdl.SavePNG] Failed to save screenshot. Error msg:",
            sdl.GetError()
        )

        sdl.ShowSimpleMessageBox(
			{.ERROR},
			"Failure!",
			"Failed to save screenshot :(",
			window,
		)
	}
}

zoom :: proc(app: ^App_State, speed: f32) 
{
	app.zoom *= speed
	opengl.Uniform1f(app.uniforms.zoom, app.zoom)
}

pan :: proc(app: ^App_State, direction: [2]f32, speed: f32 = 1) 
{
	width, height: i32
	sdl.GetWindowSizeInPixels(app.window, &width, &height)

	scale := (f32)(min(width, height))
	app.shift += speed * direction / scale * app.zoom

	opengl.Uniform2f(app.uniforms.shift, app.shift.x, app.shift.y)
}

@(private = "file")
now_to_string :: proc() -> (buf: [17]u8) 
{
	now := time.now()

	// dd-mm-yyyy
	y, _month, d := time.date(now)
	month := (u8)(_month)

	buf[9] = '0' + (u8)(y % 10);y /= 10
	buf[8] = '0' + (u8)(y % 10);y /= 10
	buf[7] = '0' + (u8)(y % 10);y /= 10
	buf[6] = '0' + (u8)(y)
	buf[5] = '-'
	buf[4] = '0' + (u8)(month % 10);month /= 10
	buf[3] = '0' + (u8)(month % 10)
	buf[2] = '-'
	buf[1] = '0' + (u8)(d % 10);d /= 10
	buf[0] = '0' + (u8)(d % 10)

	// sep
	buf[10] = '_'

	// hhmmss
	h, minute, s := time.clock(now)

	buf[16] = '0' + (u8)(s % 10);s /= 10
	buf[15] = '0' + (u8)(s)
	buf[14] = '0' + (u8)(minute % 10);minute /= 10
	buf[13] = '0' + (u8)(minute)
	buf[12] = '0' + (u8)(h % 10);h /= 10
	buf[11] = '0' + (u8)(h)

	return buf // (string)(buf[:16])
}
