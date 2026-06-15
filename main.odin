#+feature using-stmt

package kolori

import "base:runtime"
import "odin-imgui/imgui_impl_opengl3"
import "odin-imgui/imgui_impl_sdl3"
import imgui "odin-imgui"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import "core:strings"
import "core:time"
import "core:log"
import "core:fmt"
import "core:mem"
import "core:os"

// four coloring modes:
//  1. predefined coloring functions for H, S, and L
//  2. user-provided coloring functions (HSL)
//  3. image (texture)
//  4. palette (https://iquilezles.org/articles/palettes/)

App_Context :: struct {
	window:           ^sdl.Window,
	gl_ctx:           sdl.GLContext,
	vao:              u32,
	program:          u32,
	vertex_shader_id: u32,
	texture:          u32,
	coloring_method:  Coloring_Method,
	uniforms:         Uniforms,
	io:               ^imgui.IO,
	math_font:        ^imgui.Font,
	function:         cstring,
	err_msg:          cstring,
	time_speed:       f32,
	animation_paused: bool,
	show_ui:          bool,
	zoom:             f32,
	time:             f32,
	/* */
	shift:            [2]f32,
	/* */
	abcd:			  [4][3]f32,
	gamma_correction: f32,
	vsync: bool
}

// use uniform buffer object and a single "set_uniforms" proc?
// Uniform :: struct($T: typeid) {
// 	location: i32,
// 	value: T
// }
// Uniforms :: struct {
// 	zoom:             Uniform(f32),
// 	time:             Uniform(f32),
// 	resolution:       Uniform([2]f32),
// 	shift:            Uniform([2]f32),
// 	abcd:             Uniform([4][3]f32),
// 	gamma_correction: Uniform(f32),
// }

Uniforms :: struct {
	zoom:             i32,
	time:             i32,
	resolution:       i32,
	shift:            i32,
	abcd:             i32,
	gamma_correction: i32,
}

Coloring_Method :: enum i32 {
	Use_Default,
	Use_Texture,
	Use_Palette,
	// Use_User,
}

when ODIN_DEBUG {
	GL_MAJOR_VERSION :: 4
	GL_MINOR_VERSION :: 3
} else {
	GL_MAJOR_VERSION :: 3
	GL_MINOR_VERSION :: 3
}

@(rodata) VERTEX_SHADER := #load("shaders/graph.vert", string)
@(rodata) FRAGMENT_SHADER := #load("shaders/graph.frag", cstring)
PAN_SPEED :: (f32)(10)
ZOOM_SPEED :: (f32)(1.1)

main :: proc() 
{
	context.logger = log.create_console_logger()
	context.logger.lowest_level = ODIN_DEBUG ? .Debug : .Info
	defer log.destroy_console_logger(context.logger)

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

	using app: App_Context
	setup_app(&app)
	defer {
		delete(function)
		delete(err_msg)
	}

	setup_sdl(&app)
	defer {
		sdl.GL_DestroyContext(gl_ctx)
		sdl.DestroyWindow(window)
		sdl.Quit()
	}

	setup_gl(&app)
	defer {
		gl.DeleteShader(vertex_shader_id)
		gl.DeleteProgram(program)
	}

	setup_imgui(&app)
	defer {
		imgui_impl_opengl3.Shutdown()
		imgui_impl_sdl3.Shutdown()
		imgui.DestroyContext()
	}

	last_time := sdl.GetTicks()
	render_loop: for {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			imgui_impl_sdl3.ProcessEvent(&event)

			if event.type == .QUIT {
				break render_loop
			}

			handle_event(&app, &event)
		}

		if !animation_paused {
			time += (f32)(sdl.GetTicks() - last_time)
			gl.Uniform1f(uniforms.time, time * 1e-3 * time_speed)
		}
		last_time = sdl.GetTicks()

		render_graph(&app)
		draw_ui(&app)

		sdl.GL_SwapWindow(window)
		free_all(context.temp_allocator)
	}
}

setup_app :: proc(using app: ^App_Context) 
{
	zoom = 1
	show_ui = true
	time_speed = 1
	gamma_correction = 0.65
	// coloring_method = .Use_Texture
	err_msg = strings.clone_to_cstring("")
	function = (cstring)(make([^]u8, 1024))
	([^]u8)(function)[0] = 'z'
}

setup_sdl :: proc(using app: ^App_Context) 
{
	if !sdl.Init({.VIDEO}) {
		log.fatal("[sdl.Init]", sdl.GetError())
		sdl.Quit()
	}

	window_flags := sdl.WindowFlags{.OPENGL, .RESIZABLE, .HIGH_PIXEL_DENSITY}
	window = sdl.CreateWindow("Kolori", 800, 600, window_flags)
	if window == nil {
		log.fatal("[sdl.CreateWindow]", sdl.GetError())
		sdl.Quit()
	}
	sdl.SetWindowPosition(
		window,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
	)
	sdl.ShowWindow(window)
}

exit :: proc(using app: ^App_Context)
{
	runtime._cleanup_runtime()
	os.exit(1)
}
