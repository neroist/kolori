#+feature using-stmt

package kolori

import "base:runtime"
import "odin-imgui/imgui_impl_opengl3"
import "odin-imgui/imgui_impl_sdl3"
import imgui "odin-imgui"
import opengl "vendor:OpenGL"
import sdl "vendor:sdl3"
import "core:strings"
import "core:log"
import "core:fmt"
import "core:mem"
import "core:os"

// four coloring modes:
//  1. predefined coloring functions for H, S, and L
//  2. user-provided coloring functions (HSL)
//  3. image (texture)
//  4. palette (https://iquilezles.org/articles/palettes/)

App_State :: struct {
	using gl: GL_State,
	using ui: Ui_State,
	window:   ^sdl.Window,
	running:  bool,
}

main :: proc() 
{
	context.logger = log.create_console_logger()
	context.logger.lowest_level = ODIN_DEBUG ? .Debug : .Info
	defer log.destroy_console_logger(context.logger)

	// Lets all love Odin <3
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf(
					"=== %v allocations not freed: ===\n",
					len(track.allocation_map),
				)
				for _, entry in track.allocation_map {
					fmt.eprintf(
						"- %v bytes @ %v\n",
						entry.size,
						entry.location,
					)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	using app: App_State
	setup_app(&app)
	defer {
		delete(function)
		delete(err_msg)
	}

	setup_sdl(&app)
	defer {
		sdl.GL_DestroyContext(gl.ctx)
		sdl.DestroyWindow(window)
		sdl.Quit()
	}

	setup_gl(&app)
	defer {
		opengl.DeleteShader(vertex_shader_id)
		opengl.DeleteProgram(program)
	}

	setup_imgui(&app)
	defer {
		imgui_impl_opengl3.Shutdown()
		imgui_impl_sdl3.Shutdown()
		imgui.DestroyContext()
	}

	last_time := sdl.GetTicks()
	for app.running {
		process_events(&app)

		// advance time for animations
		if !animation_paused {
			delta_time := (f32)(sdl.GetTicks() - last_time)
			time += delta_time
			opengl.Uniform1f(uniforms.time, time * 1e-3 * time_speed)
		}

		last_time = sdl.GetTicks()

		// draw everything to window
		render_graph(&app)
		draw_ui(&app)

		sdl.GL_SwapWindow(window)
		free_all(context.temp_allocator)
	}
}

setup_app :: proc(using app: ^App_State) 
{
	zoom = 1
	show_ui = true
	time_speed = 1
	gamma_correction = 0.65
	running = true
	// coloring_method = .Use_Texture
	err_msg = strings.clone_to_cstring("")
	function = (cstring)(make([^]u8, 1024))
	([^]u8)(function)[0] = 'z'
}

setup_sdl :: proc(using app: ^App_State) 
{
	_ = sdl.SetAppMetadata("Kolori", "0.1.0", "com.neroist.kolori")
	_ = sdl.SetAppMetadataProperty(
		sdl.PROP_APP_METADATA_URL_STRING,
		"https://github.com/neroist/kolori",
	)

	if !sdl.Init({.VIDEO}) {
		log.fatal("[sdl.Init]", sdl.GetError())

		app.running = false
		return
	}

	window_flags := sdl.WindowFlags{.OPENGL, .RESIZABLE, .HIGH_PIXEL_DENSITY}
	window = sdl.CreateWindow("Kolori", 800, 600, window_flags)
	if window == nil {
		log.fatal("[sdl.CreateWindow]", sdl.GetError())

		app.running = false
		return
	}

	sdl.SetWindowPosition(
		window,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
	)
	sdl.ShowWindow(window)
}

exit :: proc(using app: ^App_State) 
{
	runtime._cleanup_runtime()
	os.exit(1)
}
