#+feature using-stmt

package kolori

import "../odin-imgui/imgui_impl_opengl3"
import "../odin-imgui/imgui_impl_sdl3"
import opengl "vendor:OpenGL"
import imgui "../odin-imgui"
import sdl "vendor:sdl3"
import "base:runtime"
import "core:strings"
import "core:c/libc"
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
	running:  bool,
}

custom_allocator_proc :: proc (
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (result: []byte, err: mem.Allocator_Error)
{
	// don't want to "io.write_*" for a bunch of lines...
	// libc's printf gives us an api similar to fmt.printf's
	// while not relying on context.allocator, which is nice
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		libc.printf(
			"[Tracking Allocator] Allocation made of size %i and alignment %i\n",
			size,
			alignment
		)
	case .Resize, .Resize_Non_Zeroed:
		libc.printf(
			"[Tracking Allocator] Free of size %i\n",
			size
		)
	case .Free, .Free_All:
		libc.printf(
			"[Tracking Allocator] Resize from size %i to size %i with alignment %i\n",
			old_size,
			size,
			alignment
		)
	}

	return mem.tracking_allocator_proc(allocator_data, mode, size, alignment, old_memory, old_size, loc)
}

main :: proc() 
{
	context.logger = log.create_console_logger()
	context.logger.lowest_level = ODIN_DEBUG ? .Debug : .Info
	defer log.destroy_console_logger(context.logger)

	// Lets all love Odin.
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.Allocator{
			data = &track,
			procedure = custom_allocator_proc
		}

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
		sdl.DestroySurface(window_icon)
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
		// free_all(context.temp_allocator)
		// free_all(context.allocator)
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

exit :: proc(using app: ^App_State) 
{
	runtime._cleanup_runtime()
	os.exit(1)
}
